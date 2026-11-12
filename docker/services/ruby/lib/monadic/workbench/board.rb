# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'time'
require_relative 'store'
require_relative 'image_check'
require_relative 'artifact'
require_relative 'file_item'
require_relative '../workspace/chats'

module Monadic
  module Workbench
    # A chat's workbench: what is on it, in the order it arrived (the page
    # shows it as a row to move through). An image a generator made is a
    # file of the chat's folder in the shared folder, recorded in the ledger
    # (Artifact); a file someone opened is a reference to a file of the
    # shared folder and the version it had (FileItem). An item holds what
    # the page shows, never the bytes. Removing an item takes it off the
    # board only: the file stays. Kept in the chat's manifest (Store) so it
    # outlives a restart.
    #
    # The chat's browser is an item too, while it is open and after it
    # closed (until the user takes it off); it is held in memory only (a
    # browser does not outlive the server).
    #
    # Which item each tab has selected is held in memory, for the
    # connection that said so (select), and goes with it.
    #
    # Every change happens under the board's lock and is saved before the
    # lock is let go, so of two operations on one image (two tabs, a resend)
    # one is accepted and the other is told about it.
    #
    # Epochs (Chats.epoch) are kept in memory and start again at a restart,
    # so none is kept here: an operation is accepted only at the chat's
    # current epoch.
    class Board
      ITEM_LIMIT = 8
      # What an origin keeps in the manifest (not the tab or connection).
      ORIGIN_KEYS = %i[actor source request_id].freeze
      ACTIONS = %w[remove].freeze
      # Removed items remembered, so that a removal sent again is answered.
      REMOVED_LIMIT = 50

      class Refused < StandardError; end

      # The image was placed in the chat's folder, and the board did not
      # take it (the reply was stopped meanwhile, or the board could not be
      # saved). path: where the image is.
      class PlacedOnly < StandardError
        attr_reader :path

        def initialize(message, path:)
          super(message)
          @path = path
        end
      end

      @boards = {}
      @boards_lock = Mutex.new

      class << self
        # The board of a chat, loaded from its manifest the first time.
        def for(chat_id, store: Store.default)
          @boards_lock.synchronize do
            @boards[chat_id] ||= new(chat_id, store: store)
          end
        end

        # The board of a chat that has one (loaded, or kept in a manifest),
        # or nil: nothing is made for a chat that never used the workbench.
        def existing(chat_id, store: Store.default)
          loaded = @boards_lock.synchronize { @boards[chat_id] }
          return loaded if loaded
          return nil unless store.exists?(chat_id)

          self.for(chat_id, store: store)
        end

        def forget(chat_id)
          @boards_lock.synchronize { @boards.delete(chat_id) }
        end

        # For tests (the socket layer's live check goes too).
        def reset!
          @boards_lock.synchronize { @boards.clear }
          @live = nil
        end

        # The generation of the connection a tab has now (set by the socket
        # layer). A selection counts only for that connection; without it
        # (tests, no socket) every selection counts.
        attr_accessor :live
      end

      attr_reader :chat_id

      def initialize(chat_id, store: Store.default)
        @chat_id = chat_id
        @store = store
        @lock = Mutex.new
        @data = store.load(chat_id) || fresh
        @selected = {}
        # Each selection a tab's connection makes (select, select_for_origin)
        # takes the next number, kept with it: a capture asked for one
        # selection is not answered for a later one of the same item.
        @selection_serial = 0
        # Browsers the user took off: the same browser is not put back.
        @browsers_off = []
        # What a use of a file found (FileItem.read): changed or missing for
        # the version given, until the file is opened again.
        @verdicts = {}
        # What a text item shows of its version (note_text): its lines and
        # whether it is cut short.
        @texts = {}
      end

      # A view of the board for the pages of the chat: what the items are,
      # where each image is in the shared folder, and whether its file is
      # still the one recorded (status: ok, changed or missing). Holds no
      # token.
      def snapshot
        data = @lock.synchronize { deep_dup(@data) }
        {
          board_id: data['board_id'], chat_id: @chat_id, epoch: Monadic::Workspace::Chats.epoch(@chat_id),
          revision: data['revision'],
          items: data['items'].values.map { |item| public_item(item) }
        }
      end

      # What a message from the tab's connection (generation) tells of the
      # board (Observation): the items as a view shows them, the one the
      # connection selected, and what the server served of it as text, read
      # together under the lock (the statuses are then read from the files).
      # nil for a connection that is no longer the tab's.
      def observe(tab:, generation:)
        data, selected, text = @lock.synchronize do
          next nil unless live?(tab, generation)

          held = @selected[tab.to_s]
          id = held && held[:generation] == generation && @data['items'].key?(held[:item_id]) ? held[:item_id] : nil
          shown = id && @texts[id]
          version = id && @data.dig('items', id, 'file', 'sha256')
          [deep_dup(@data), id, shown && shown[:sha256] == version ? shown.slice(:lines, :truncated) : nil]
        end
        return nil unless data

        { epoch: Monadic::Workspace::Chats.epoch(@chat_id), selected: selected, text: text,
          items: data['items'].values.map { |item| public_item(item) } }
      end

      # Places a generator's image in the chat's folder and puts it on the
      # board, under the board's lock: the chat must be at epoch and the
      # reply not stopped (unless_closed) when it starts. Once those checks
      # pass the image is this chat's: a Cancel or a Reset that comes while
      # it is placed does not cut it off (change). Returns the item.
      #
      # A run is placed once. The same run again (same chat, reply and
      # bytes) gives the item it put on the board; when the user took that
      # item off, it is not put back (PlacedOnly). A run of another image is
      # refused.
      #
      # Refused (nothing placed) at another epoch, for a
      # stopped reply, for bytes that are not an image. PlacedOnly when the
      # image was placed and the board did not take it.
      def add_image(bytes:, epoch:, origin:, name:, run:, app_name:, derived_from: nil, unless_closed: nil)
        image = ImageCheck.check!(bytes)
        record = nil
        change do |data|
          check_epoch!(epoch)
          raise Refused, 'the reply was stopped' if unless_closed&.call

          if (placed = placed_item(data, run, origin[:request_id], bytes))
            select_for_origin(origin, placed['id'])
            next placed
          end

          room_for_one!(data)
          record = Artifact.place!(chat_id: @chat_id, app_name: app_name, bytes: bytes, image: image, name: name,
                                   run: run, request_id: origin[:request_id], derived_from: derived_from)
          item_id = "i_#{SecureRandom.hex(10)}"
          data['items'][item_id] = {
            'id' => item_id, 'kind' => 'image', 'origin' => kept_origin(origin), 'mid' => nil,
            'artifact' => stringify(Artifact.entry(record).merge('width' => record[:width], 'height' => record[:height]))
          }
          select_for_origin(origin, item_id)
          deep_dup(data['items'][item_id])
        end
      rescue Artifact::NotPlaced => e
        raise PlacedOnly.new(e.message, path: e.path) if e.path

        raise Refused, e.message
      rescue SystemCallError, IOError => e
        raise unless record

        raise PlacedOnly.new("the work screen could not take the image (#{e.class.name.split('::').last})",
                             path: record[:copy_path])
      end

      # Opens a file of the shared folder on the board (FileItem): a file the
      # board has is selected rather than added again, and taken at the
      # version it has now (the board refers to the file and keeps no copy,
      # so an item of an earlier version would show nothing of it). origin:
      # who opened it (actor :user from the
      # Shared Folder panel, :agent from a tool), and the tab and connection
      # it was opened for (tab:, generation:), which then selects it.
      # Returns [item, added]. Refused at another epoch, for a file the work
      # screen does not show, or when every item is kept (room_for_one!);
      # FileItem::Busy when no turn to read it came within wait.
      # wait: seconds to wait for a turn to read the file (FileItem.turn).
      # sha256: the version asked for (a message's record names it): another
      # version, as read now, is refused ('changed') and not added.
      def add_file(path:, origin:, epoch:, wait: FileItem::READ_WAIT, sha256: nil)
        entry = FileItem.entry_for(path, wait: wait)
        raise Refused, 'changed' if sha256 && entry['sha256'] != sha256

        change do |data|
          check_epoch!(epoch)
          raise Refused, 'not_allowed' if origin[:actor].to_s == 'user' && !live?(origin[:tab], origin[:generation])

          found = data['items'].values.find { |item| item['kind'] == 'file' && item.dig('file', 'path') == entry['path'] }
          if found
            # What is seen of the file now is taken (the same bytes saved
            # again, or new ones), and what a use found before is dropped.
            found['file'] = entry
            @verdicts.delete(found['id'])
            @texts.delete(found['id'])
            select_for_origin(origin, found['id'])
            next [deep_dup(found), false]
          end

          room_for_one!(data)
          item_id = "i_#{SecureRandom.hex(10)}"
          data['items'][item_id] = { 'id' => item_id, 'kind' => 'file', 'origin' => kept_origin(origin), 'mid' => nil,
                                     'file' => entry }
          select_for_origin(origin, item_id)
          [deep_dup(data['items'][item_id]), true]
        end
      rescue FileItem::Refused => e
        raise Refused, e.message
      end

      # The chat's browser (instance: BrowserOwner's number for it) opened:
      # it is put on the board, and the tab of origin selects it. The same
      # browser again is selected, not added; one the user took off is not
      # put back (nil). Returns the item or nil.
      def add_browser(instance:, origin:, epoch:)
        change do |data|
          check_epoch!(epoch)
          next nil if @browsers_off.include?(instance)

          found = data['items'].values.find { |item| item['kind'] == 'browser' && item.dig('browser', 'instance') == instance }
          if found
            select_for_origin(origin, found['id'])
            next deep_dup(found)
          end

          room_for_one!(data)
          item_id = "i_#{SecureRandom.hex(10)}"
          data['items'][item_id] = { 'id' => item_id, 'kind' => 'browser', 'origin' => kept_origin(origin), 'mid' => nil,
                                     'browser' => { 'instance' => instance } }
          select_for_origin(origin, item_id)
          deep_dup(data['items'][item_id])
        end
      end

      # The bytes of a file item, read now and checked against its version
      # (FileItem.read), with its entry. sha256: the version the asker was
      # given (a token); another version is Artifact::Changed.
      # limit: the most bytes this use takes (FileItem.read).
      def file_read(item_id, sha256:, limit: FileItem::LIMIT)
        entry = file_entry(item_id, sha256: sha256)
        { entry: entry, bytes: FileItem.read(entry, limit: limit) }
      end

      # The file item's entry at the version sha256, without reading the file.
      def file_entry(item_id, sha256:)
        entry = @lock.synchronize { deep_dup(@data.dig('items', item_id, 'file')) } or raise Artifact::NotAllowed, 'no such file'
        raise Artifact::Changed, 'the file changed after it was opened' unless entry['sha256'] == sha256

        entry
      end

      # A use of the file item found it changed or missing (status) at the
      # version sha256: views say so until it is opened again.
      def mark(item_id, sha256:, status:)
        @lock.synchronize do
          next unless @data.dig('items', item_id, 'file', 'sha256') == sha256

          @verdicts[item_id] = { sha256: sha256, status: status }
        end
      end

      # The text item item_id shows lines lines of the version sha256
      # (truncated: only its beginning), as served.
      def note_text(item_id, sha256:, lines:, truncated:)
        @lock.synchronize do
          next unless @data.dig('items', item_id, 'file', 'sha256') == sha256

          @texts[item_id] = { sha256: sha256, lines: lines, truncated: truncated }
        end
      end

      # What note_text kept for the item's version, or nil (not served yet).
      def text_shown(item_id, sha256:)
        @lock.synchronize do
          shown = @texts[item_id]
          shown && shown[:sha256] == sha256 ? shown.slice(:lines, :truncated) : nil
        end
      end

      # The tab's connection (generation) selects item_id, or nothing (nil).
      # Refused for an item that is not on the board. Returns item_id.
      # Refused too when the connection is no longer the tab's (live?): an
      # older connection does not replace what a newer one selected.
      def select(tab:, generation:, item_id:)
        choose(tab: tab, generation: generation, item_id: item_id).first
      end

      # select, and the number this selection took: [item_id, serial].
      def choose(tab:, generation:, item_id:)
        @lock.synchronize do
          raise Refused, 'not_allowed' unless live?(tab, generation)
          raise Refused, 'no such item' if item_id && !@data['items'].key?(item_id)

          [item_id, selected!(tab, generation, item_id)[:serial]]
        end
      end

      # What the tab's connection has selected and the number of that
      # selection: [item_id or nil, serial or nil].
      def selection(tab:, generation:)
        @lock.synchronize do
          held = @selected[tab.to_s]
          next [nil, nil] unless held && held[:generation] == generation && live?(tab, generation)

          [@data['items'].key?(held[:item_id]) ? held[:item_id] : nil, held[:serial]]
        end
      end

      # What the tab's connection has selected (an item still on the board),
      # or nil (also for a connection that is no longer the tab's).
      def selected(tab:, generation:)
        @lock.synchronize do
          held = @selected[tab.to_s]
          next nil unless held && held[:generation] == generation && live?(tab, generation)

          @data['items'].key?(held[:item_id]) ? held[:item_id] : nil
        end
      end

      # What a look reads: the item the tab's connection has selected,
      # copied as it is now (its version included), and the number of that
      # selection. nil when nothing is selected, and :connection_gone when
      # the connection is no longer the tab's.
      Target = Struct.new(:item, :serial)

      def look_target(tab:, generation:)
        @lock.synchronize do
          next :connection_gone unless tab && generation && live?(tab, generation)

          held = @selected[tab.to_s]
          next nil unless held && held[:generation] == generation

          item = @data['items'][held[:item_id]]
          item && Target.new(deep_dup(item), held[:serial])
        end
      end

      # Whether the tab's connection still has item (look_target) selected,
      # at the same version, and (given serial) by the same selection.
      def still_selected?(tab:, generation:, item:, serial: nil)
        @lock.synchronize do
          held = @selected[tab.to_s]
          now = held && held[:generation] == generation && live?(tab, generation) && @data['items'][held[:item_id]]
          now && now['id'] == item['id'] && version_of(now) == version_of(item) && (serial.nil? || held[:serial] == serial)
        end
      end

      # The connection closed: what it selected is no longer kept for it.
      def drop_selection(tab, generation)
        @lock.synchronize do
          @selected.delete(tab.to_s) if @selected.dig(tab.to_s, :generation) == generation
        end
      end

      # The image that arrived on the board last, or nil.
      def latest_image
        @lock.synchronize { deep_dup(@data['items'].values.reverse.find { |item| item['artifact'] }) }
      end

      # The image of an item, read from the shared folder and checked
      # (Artifact.read): {id:, artifact_id:, sha256:, name:, content_type:,
      # bytes:}. Refused when the item is gone, its file changed or is gone.
      def image_input(item_id)
        entry = @lock.synchronize { deep_dup(@data.dig('items', item_id, 'artifact')) } or raise Refused, 'no such image'
        read = Artifact.read(entry['id'], chat_id: @chat_id)
        { id: item_id, artifact_id: entry['id'], sha256: read[:record][:sha256], name: entry['name'],
          content_type: read[:record][:content_type], bytes: read[:bytes] }
      rescue Artifact::Missing
        raise Refused, "the image #{entry['path']} is no longer in the shared folder"
      rescue Artifact::Changed
        raise Refused, "the image #{entry['path']} changed in the shared folder after it was made"
      rescue Artifact::NotAllowed
        raise Refused, 'no such image'
      end

      # The reply of request_id was recorded as the message mid, which names
      # item_ids: those of them the reply put on the board, and that have no
      # message yet, are that message's. Returns the ids of the items.
      def attach_reply(request_id, mid, item_ids)
        return [] if messageless(request_id, item_ids).empty?

        change do |data|
          messageless(request_id, item_ids, data).each { |item| item['mid'] = mid }.map { |item| item['id'] }
        end
      end

      # Takes the user's removal of an image. One change: the operation is
      # made and the board updated, so a second operation finds it. sha256 is
      # the image's the user's token was given for. Returns [:accepted,
      # operation] for a new operation, [:same, operation] for the same
      # operation sent again (also once the item is gone), or raises Refused.
      def accept(item_id:, action:, operation_id:, epoch:, sha256:)
        raise Refused, 'unknown action' unless ACTIONS.include?(action)
        raise Refused, 'invalid operation id' unless operation_id.is_a?(String) && operation_id.match?(/\A[A-Za-z0-9_-]{8,64}\z/)

        change do |data|
          check_epoch!(epoch)
          if (existing = data['operations'][operation_id])
            same = existing['item_id'] == item_id && existing['action'] == action && existing['sha256'] == sha256
            raise Refused, 'operation id used for another operation' unless same

            next [:same, deep_dup(existing)]
          end
          raise Refused, 'this image was removed' if data['removed'].key?(item_id)

          item = data['items'][item_id] or raise Refused, 'no such image'
          raise Refused, 'this item changed' unless version_of(item) == sha256

          operation = { 'id' => operation_id, 'action' => action, 'item_id' => item_id, 'sha256' => sha256,
                        'state' => 'removed', 'accepted_at' => Time.now.utc.iso8601 }
          data['operations'][operation_id] = operation
          data['operations'].shift while data['operations'].size > REMOVED_LIMIT
          take_off!(data, item, operation_id)
          @browsers_off << item.dig('browser', 'instance') if item['kind'] == 'browser'
          put_back_browser!(data)
          [:accepted, deep_dup(operation)]
        end
      end

      def item(item_id)
        @lock.synchronize { deep_dup(@data['items'][item_id]) }
      end

      # Takes off the file and image items of paths (relative to the shared
      # folder), and of the files inside a folder among them: what a deleted
      # turn made and moved to the trash. Returns the ids taken off.
      def drop_files(paths)
        prefixes = Array(paths).map { |path| "#{path}/" }
        change do |data|
          gone = data['items'].values.select do |item|
            path = { 'file' => 'file', 'image' => 'artifact' }[item['kind']]&.then { |key| item.dig(key, 'path') }
            path && (paths.include?(path) || prefixes.any? { |prefix| path.start_with?(prefix) })
          end
          gone.each { |item| take_off!(data, item, 'turn_deleted') }
          gone.map { |item| item['id'] }
        end
      end

      private

      def fresh
        { 'schema' => Store::SCHEMA, 'chat_id' => @chat_id, 'board_id' => SecureRandom.hex(8),
          'revision' => 0, 'items' => {}, 'operations' => {}, 'removed' => {} }
      end

      # A change is not cut off by a thread being stopped (the reply's thread
      # when the reply is cancelled): the file placed, the ledger's record,
      # the manifest saved and the board held here stay together.
      def change
        Thread.handle_interrupt(Object => :never) do
          @lock.synchronize do
            working = deep_dup(@data)
            result = yield working
            working['revision'] += 1
            @store.save(@chat_id, kept_data(working))
            @data = working
            result
          end
        end
      end

      # The items of request_id named in item_ids that have no message yet.
      def messageless(request_id, item_ids, data = nil)
        return [] unless request_id

        named = Array(item_ids)
        pick = lambda do |items|
          items.values.select do |item|
            named.include?(item['id']) && item.dig('origin', 'request_id') == request_id && item['mid'].nil?
          end
        end
        data ? pick.call(data['items']) : @lock.synchronize { pick.call(@data['items']) }
      end

      def check_epoch!(epoch)
        raise Refused, 'the chat was replaced' unless epoch == Monadic::Workspace::Chats.epoch(@chat_id)
      end

      def take_off!(data, item, removed_by)
        data['items'].delete(item['id'])
        data['removed'][item['id']] = removed_by
        data['removed'].shift while data['removed'].size > REMOVED_LIMIT
      end

      # The item of a run already placed (Artifact.recorded_run), or nil for
      # a run not placed. PlacedOnly when the item was taken off the board.
      def placed_item(data, run, request_id, bytes)
        found = Artifact.recorded_run(run, chat_id: @chat_id, request_id: request_id,
                                           sha256: Digest::SHA256.hexdigest(bytes))
        return nil unless found

        item = data['items'].values.find { |i| i.dig('artifact', 'id') == found[:artifact_id] }
        raise PlacedOnly.new('the image was placed before and is no longer on the work screen', path: found[:copy_path]) unless item

        deep_dup(item)
      end

      # Room for one more item: the oldest item that is not kept is taken
      # off the board (its file stays in the shared folder). Kept: an item
      # a tab's connection has selected, and the latest image (what an edit
      # starts from). Refused when every item is kept.
      def room_for_one!(data)
        return if data['items'].size < ITEM_LIMIT

        kept = @selected.select { |tab, held| live?(tab, held[:generation]) }.values.map { |held| held[:item_id] }
        latest = data['items'].values.reverse.find { |item| item['artifact'] }
        kept << latest['id'] if latest
        kept.concat(data['items'].values.select { |item| browser_status(item) == 'open' }.map { |item| item['id'] })
        oldest = data['items'].values.find { |item| !kept.include?(item['id']) }
        raise Refused, 'the work screen is full: remove an item first' unless oldest

        take_off!(data, oldest, 'room')
      end

      # The chat's open browser, when it is not on the board (it opened
      # while every item was kept) and the user did not take it off, is put
      # on in the room just made.
      def put_back_browser!(data)
        view = defined?(MonadicSharedTools::BrowserOwner) && MonadicSharedTools::BrowserOwner.view(@chat_id)
        return unless view && view.epoch == Monadic::Workspace::Chats.epoch(@chat_id)
        return if @browsers_off.include?(view.instance) || data['items'].size >= ITEM_LIMIT
        return if data['items'].values.any? { |item| item.dig('browser', 'instance') == view.instance }

        item_id = "i_#{SecureRandom.hex(10)}"
        data['items'][item_id] = { 'id' => item_id, 'kind' => 'browser', 'origin' => { 'actor' => 'agent', 'source' => 'browser' },
                                   'mid' => nil, 'browser' => { 'instance' => view.instance } }
      end

      # The item's content entry: the image's record or the file's version.
      def content_of(item)
        item['artifact'] || item['file']
      end

      # What an operation's token names of the item: the sha256 of an image
      # or a file, the instance of a browser.
      def version_of(item)
        item['kind'] == 'browser' ? "browser:#{item.dig('browser', 'instance')}" : content_of(item)&.dig('sha256')
      end

      # open while the chat's browser is this item's, closed after.
      def browser_status(item)
        return nil unless item['kind'] == 'browser'

        view = defined?(MonadicSharedTools::BrowserOwner) && MonadicSharedTools::BrowserOwner.view(@chat_id)
        view && view.instance == item.dig('browser', 'instance') ? 'open' : 'closed'
      end

      # The board as the manifest keeps it: without browsers.
      def kept_data(data)
        kept = data.dup
        kept['items'] = data['items'].reject { |_, item| item['kind'] == 'browser' }
        kept
      end

      # The origin as the manifest keeps it (no tab or connection).
      def kept_origin(origin)
        stringify(origin.to_h.slice(*ORIGIN_KEYS))
      end

      # The tab an item was made for selects it (inside change, under the
      # lock).
      def select_for_origin(origin, item_id)
        tab = origin[:tab]
        return unless tab && live?(tab, origin[:generation])

        selected!(tab, origin[:generation], item_id)
      end

      # The tab's connection selects item_id (under the lock), as a new
      # selection.
      def selected!(tab, generation, item_id)
        @selection_serial += 1
        @selected[tab.to_s] = { generation: generation, item_id: item_id, serial: @selection_serial }
      end

      # Whether generation is the connection tab has now (a work that began
      # on an older connection selects nothing).
      def live?(tab, generation)
        live = self.class.live
        live.nil? || (!tab.nil? && live.call(tab.to_s) == generation)
      end

      def public_item(item)
        return public_file(item) if item['kind'] == 'file'
        if item['kind'] == 'browser'
          return { id: item['id'], kind: 'browser', actor: item.dig('origin', 'actor'), mid: item['mid'],
                   instance: item.dig('browser', 'instance'), version: version_of(item), status: browser_status(item) }
        end

        entry = item['artifact'] || {}
        {
          id: item['id'], kind: item['kind'], actor: item.dig('origin', 'actor'), mid: item['mid'],
          artifact_id: entry['id'], name: entry['name'], path: entry['path'], content_type: entry['content_type'],
          width: entry['width'], height: entry['height'], sha256: entry['sha256'],
          derived_from: entry['derived_from'], version: entry['sha256'],
          status: entry['id'] ? Artifact.status(entry['id'], chat_id: @chat_id).to_s : 'missing'
        }
      end

      # What a use found (mark) for this version, or what the file's stat says.
      def file_status(item)
        verdict = @verdicts[item['id']]
        return verdict[:status] if verdict && verdict[:sha256] == item.dig('file', 'sha256')

        FileItem.status(item['file'])
      end

      def public_file(item)
        entry = item['file']
        {
          id: item['id'], kind: 'file', actor: item.dig('origin', 'actor'), mid: item['mid'],
          name: entry['name'], path: entry['path'], preview: entry['preview'], content_type: entry['content_type'],
          size: entry['size'], sha256: entry['sha256'], version: entry['sha256'], status: file_status(item),
          render: Monadic::Workspace::SharedFolderPreview.render_for(entry['path'])
        }
      end

      def stringify(value)
        case value
        when Hash then value.each_with_object({}) { |(k, v), out| out[k.to_s] = stringify(v) }
        when Array then value.map { |v| stringify(v) }
        when Symbol then value.to_s
        else value
        end
      end

      def deep_dup(value)
        value.nil? ? nil : Marshal.load(Marshal.dump(value))
      end
    end
  end
end
