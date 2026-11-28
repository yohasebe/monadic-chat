# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'time'
require 'json'
require_relative 'store'
require_relative 'image_check'
require_relative 'artifact'
require_relative 'file_item'
require_relative 'item_text'
require_relative 'marks'
require_relative 'turn_records'
require_relative 'drawings'
require_relative '../utils/privacy/outbound'
require_relative '../library/file_importer'
require_relative '../library/entry_text'
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
    #
    # The items are in four places, layered by turn: current (Now, what the
    # speaker of this turn places), latest (what the last turn that placed
    # anything put out), previous (the turn before that) and stash (put
    # away, everything older). A turn ends when the user's message is
    # accepted (begin_reply) or the reply ends (end_reply); when current
    # holds anything then, the layers move down one: current to latest,
    # latest to previous, previous to stash. While a reply runs the user
    # does not change the desk (one writer for current).
    class Board
      PLACES = %w[current latest previous stash].freeze
      LAYERS = %w[latest previous].freeze
      # The most items in current (Now); latest and previous were Nows.
      NOW_LIMIT = 10
      # The most items on the desk (current, latest, previous).
      ITEM_LIMIT = NOW_LIMIT * 3
      BUSY = 'the assistant is replying: the work screen can be changed when the reply ends'
      FULL = "the work screen has #{NOW_LIMIT} items in Now: take one off or put one away first".freeze
      # One whiteboard is placed in a turn (the user's, the AI's).
      WHITEBOARD_USED = 'a whiteboard was placed in this turn already: draw on it, or place another in the next turn'
      # A whiteboard that left Now is kept as it was.
      FROZEN = 'this whiteboard left Now and is kept as it was: place a new whiteboard to draw'
      # The texts of a board kept with its image at most (characters).
      BOARD_TEXTS_LIMIT = 20_000
      # What the AI is told of a put-away item it named: it reads only what
      # is on the desk.
      PUT_AWAY = 'that item is put away: bring it into Now first (show_on_workbench with its item), then use it'
      # What an origin keeps in the manifest (not the tab or connection).
      ORIGIN_KEYS = %i[actor source request_id].freeze
      # remove: off the board when the user placed it in this turn and it
      # was not sent yet, else put away; stash: put away; bring: into Now.
      ACTIONS = %w[remove stash bring].freeze
      # Removed items remembered, so that a removal sent again is answered.
      REMOVED_LIMIT = 50
      # What happened on the board (events): the most kept. Each has the
      # next number of the chat's board; the model is told those after the
      # last one a finished reply was told of (Observation).
      EVENT_LIMIT = 30
      # Why an item was taken off when nobody chose to: a deleted turn.
      SYSTEM_REMOVALS = %w[turn_deleted].freeze

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
      # The chat of each reply running on a board (begin_reply), so that
      # its end (end_reply, by request only) finds the board.
      @replies = {}
      # Its own lock: a board made under @boards_lock reads it.
      @replies_lock = Mutex.new

      class << self
        # The reply request_id of chat_id begins: the user's turn ends (its
        # Now moves down when it holds anything) and the reply's opens.
        # marks: what the user's message sent of the marks on its items
        # (Board#record_marks!).
        def begin_reply(chat_id, request_id, marks: nil)
          return unless Monadic::Workspace::Ids.valid?(:chat, chat_id) && request_id

          @replies_lock.synchronize do
            @replies.delete_if { |_, chat| chat == chat_id }
            @replies[request_id] = chat_id
          end
          board = existing(chat_id)
          return board.begin_reply(request_id, marks: marks) if board

          # No work screen: the turn held nothing.
          TurnRecords.write(chat_id, request_id, 'user', { 'at' => Time.now.utc.iso8601, 'items' => [], 'put_away' => 0 })
          nil
        end

        # The reply running for chat_id, or nil (a board loaded while it
        # runs takes it).
        def running_reply(chat_id)
          @replies_lock.synchronize { @replies.key(chat_id) }
        end

        # The reply request_id ended (any outcome): its turn ends. Returns
        # its chat (its pages are told, also when it has no board), or nil
        # for a reply that did not begin here.
        def end_reply(request_id)
          chat_id = @replies_lock.synchronize { @replies.delete(request_id) }
          return nil unless chat_id

          board = @boards_lock.synchronize { @boards[chat_id] }
          board&.end_reply(request_id)
          chat_id
        end

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
          @replies_lock.synchronize { @replies.clear }
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
        # The reply whose turn is open (begin_reply), in memory only: no
        # reply outlives the server.
        @reply = self.class.running_reply(chat_id)
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
        # A reply a restart stopped ends its turn (the board set up first:
        # its turn's record reads the items as the page does).
        recover_reply! unless @reply
      end

      # A view of the board for the pages of the chat: what the items are,
      # where each image is in the shared folder, and whether its file is
      # still the one recorded (status: ok, changed or missing). Holds no
      # token.
      def snapshot
        data = @lock.synchronize { deep_dup(@data) }
        {
          board_id: data['board_id'], chat_id: @chat_id, epoch: Monadic::Workspace::Chats.epoch(@chat_id),
          revision: data['revision'], layers: public_layers(data), replying: !@reply.nil?, now_limit: NOW_LIMIT,
          items: data['items'].values.map { |item| desk_item(data, item) }
        }
      end

      # The user's message request_id was accepted: the user's turn ends
      # and the reply's opens (its placements go into current).
      # The revision moves on also when nothing moves, so that a page's view
      # of whether a reply runs is never replaced by an older one.
      def begin_reply(request_id, marks: nil)
        change do |data|
          # The marks the message sent, on the items where they were made
          # (before they move down).
          record_marks!(data, request_id, marks) if marks
          turn_record!(data, request_id, 'user')
          data['reply_request'] = request_id
          shift!(data, 'user', request_id)
          data['items'].each_value { |item| item.delete('fresh') }
          data.delete('turn_whiteboards')
          @reply = request_id
          nil
        end
      end

      # The reply request_id ended: its turn ends. Returns whether the desk
      # changed.
      def end_reply(request_id)
        return false unless @lock.synchronize { @reply == request_id }

        changed = false
        change do |data|
          next unless @reply == request_id

          @reply = nil
          turn_record!(data, request_id, 'agent')
          data.delete('reply_request')
          changed = shift!(data, 'agent', request_id)
          data.delete('turn_whiteboards')
        end
        changed
      end

      # A whiteboard is about to be made for origin: its place in Now and the
      # turn's one whiteboard are taken before its file is written. Refused
      # as placing is (BUSY, FULL), and when the turn placed one already
      # (WHITEBOARD_USED). release_whiteboard gives the turn's back when the
      # board could not be made.
      def reserve_whiteboard(origin:, epoch:)
        change do |data|
          check_epoch!(epoch)
          target_place!(data, origin)
          raise Refused, WHITEBOARD_USED if data['turn_whiteboards'].to_i.positive?

          data['turn_whiteboards'] = 1
          nil
        end
      end

      def release_whiteboard
        change do |data|
          data.delete('turn_whiteboards')
          nil
        end
      end

      # Writes the whiteboard item_id (the block writes its file, by origin)
      # and takes its new version, in one step with the board held: the
      # board cannot leave Now between the check, the write and the version
      # it is frozen at. Refused (FROZEN) when it cannot be drawn on, and for
      # the user while a reply runs (BUSY). event: what changed, told as an
      # edit. Returns the item.
      def write_whiteboard(item_id, origin:, epoch:, event: nil)
        change do |data|
          check_epoch!(epoch)
          item = data['items'][item_id.to_s] or raise Refused, 'the whiteboard is not on the work screen'
          raise Refused, BUSY if user?(origin) && @reply
          raise Refused, FROZEN unless editable_whiteboard?(item)

          yield
          item['file'] = FileItem.entry_for(item.dig('file', 'path'), wait: 0)
          @verdicts.delete(item['id'])
          @texts.delete(item['id'])
          record!(data, event.merge('item_id' => item['id']), origin) if event
          deep_dup(item)
        end
      rescue FileItem::Refused => e
        raise Refused, e.message
      end

      # A whiteboard that left Now and waits for its image (a plain board,
      # Whiteboard version 1: one drawn on a picture stays a board): the
      # version of its file to be painted, or nil.
      def image_pending(item_id)
        @lock.synchronize do
          item = @data['items'][item_id.to_s]
          item && pending_image?(item) ? item.dig('file', 'sha256') : nil
        end
      end

      # The texts of the board an image item was made of (Whiteboard
      # take_image): nil for an item that is no such image, :unknown when
      # they were not kept.
      def board_texts(item_id)
        @lock.synchronize do
          item = @data['items'][item_id.to_s]
          next nil unless item && item['board_source']
          next :unknown if item['board_texts_unknown'] || !item['board_texts'].is_a?(Array)

          deep_dup(item['board_texts'])
        end
      end

      # Whether item_id may go to a model as an image for a chat hiding words
      # (nil: they could not be read): any item but an image made of a
      # whiteboard; that one when none of the texts written on it holds one
      # of the words (checked when it goes, as the words can change).
      def board_texts_clear?(item_id, words)
        texts = board_texts(item_id)
        return true if texts.nil?
        return false if texts == :unknown
        return true if texts.empty? || words&.empty?
        return false if words.nil?

        texts.none? { |text| Monadic::Utils::Privacy::Outbound.leaks_word?(text, words) }
      end

      # The image a page painted of the whiteboard item_id at version: the
      # first taken is the board's from then on. The block writes the bytes
      # under each of names in turn until one is free (it returns the path
      # written, or nil for a name taken), the board held so that no two are
      # written; the item becomes that
      # image file (its id, place and who placed it kept; source: the board
      # file and version it was made from). Refused 'done' when the board is
      # an image already, 'stale' when it is not one waiting at version.
      # Returns the item.
      def take_whiteboard_image(item_id, version:, names:, epoch:, texts: :unknown)
        change do |data|
          check_epoch!(epoch)
          item = data['items'][item_id.to_s] or raise Refused, 'stale'
          raise Refused, 'done' if item.dig('board_source', 'sha256') == version
          raise Refused, 'stale' unless pending_image?(item) && item.dig('file', 'sha256') == version

          board_path = item.dig('file', 'path')
          written = names.lazy.map { |name| yield name }.find(&:itself) or raise Refused, 'no free name'
          item['file'] = FileItem.entry_for(written, wait: 0)
          item['board_source'] = { 'path' => board_path, 'sha256' => version }
          # The texts written on the board, checked against the chat's words
          # whenever the image goes to a model (board_texts_clear?).
          if texts.is_a?(Array) && texts.sum(&:size) <= BOARD_TEXTS_LIMIT
            item['board_texts'] = texts
          else
            item['board_texts_unknown'] = true
          end
          @verdicts.delete(item['id'])
          @texts.delete(item['id'])
          record!(data, { 'kind' => 'whiteboard_image', 'item_id' => item['id'] }, { actor: 'user' })
          deep_dup(item)
        end
      rescue FileItem::Refused => e
        raise Refused, e.message
      end

      # The whiteboard in Now that can be drawn on, the one made last first;
      # nil when there is none.
      def editable_whiteboard
        @lock.synchronize do
          deep_dup(@data['items'].values.reverse.find { |item| editable_whiteboard?(item) })
        end
      end

      # Whether a reply's turn is open (the user does not change the desk).
      def replying?
        @lock.synchronize { !@reply.nil? }
      end

      # Moves the item into current (bring) or puts it away (stash) for the
      # AI, in its reply. Refused for an item not on the board, and for
      # current when it is full. Returns the item.
      def move(item_id:, to:, origin:, epoch:)
        raise Refused, 'unknown place' unless %w[current stash].include?(to)

        change do |data|
          check_epoch!(epoch)
          item = data['items'][item_id.to_s] or raise Refused, 'that item is not on the work screen now'
          to == 'current' ? into_current!(data, item, origin) : put_away!(data, item, origin)
          deep_dup(data['items'][item['id']])
        end
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
          version = id && version_of(@data.dig('items', id))
          [deep_dup(@data), id, shown && shown[:sha256] == version ? shown.slice(:lines, :truncated) : nil]
        end
        return nil unless data

        told = data['told'].to_i
        { epoch: Monadic::Workspace::Chats.epoch(@chat_id), selected: selected, text: text,
          items: data['items'].values.map { |item| public_item(item) }, layers: public_layers(data),
          events: Array(data['events']).select { |e| e['seq'].to_i > told },
          events_tail: data['event_seq'].to_i, events_lost: data['events_lost'].to_i > told }
      end

      # A finished reply was told of the board's events up to tail (what
      # its message's observation held): those are not told again. Never
      # goes back (replies that finish out of order).
      def told!(tail)
        return if tail.to_i <= @lock.synchronize { @data['told'].to_i }

        change do |data|
          data['told'] = [data['told'].to_i, tail.to_i].max
          nil
        end
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

          place = target_place!(data, origin)
          record = Artifact.place!(chat_id: @chat_id, app_name: app_name, bytes: bytes, image: image, name: name,
                                   run: run, request_id: origin[:request_id], derived_from: derived_from)
          item_id = "i_#{SecureRandom.hex(10)}"
          placed!(data, {
                    'id' => item_id, 'kind' => 'image', 'origin' => kept_origin(origin), 'mid' => nil,
                    'artifact' => stringify(Artifact.entry(record).merge('width' => record[:width], 'height' => record[:height]))
                  }, place, origin)
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
      # screen does not show, or when Now is full (FULL);
      # FileItem::Busy when no turn to read it came within wait.
      # wait: seconds to wait for a turn to read the file (FileItem.turn).
      # sha256: the version asked for (a message's record names it): another
      # version, as read now, is refused ('changed') and not added.
      # event: what the change was, for an item already there (a
      # whiteboard's edit: its counts); a new item is told as placed.
      # draft: what a conversation record put by the server says of itself
      # ({ 'source_chat_id' => … }, Library::ConversationDraft); kept on the
      # item, so it stays when the file is edited.
      def add_file(path:, origin:, epoch:, wait: FileItem::READ_WAIT, sha256: nil, event: nil, attachment_id: nil, draft: nil)
        entry = FileItem.entry_for(path, wait: wait)
        raise Refused, 'changed' if sha256 && entry['sha256'] != sha256

        # The upload it came from (the ledger's), for the tools that use it.
        entry['attachment_id'] = attachment_id if attachment_id

        change do |data|
          check_epoch!(epoch)
          raise Refused, 'not_allowed' if origin[:actor].to_s == 'user' && !live?(origin[:tab], origin[:generation])

          found = data['items'].values.find { |item| item['kind'] == 'file' && item.dig('file', 'path') == entry['path'] }
          if found
            # What is seen of the file now is taken (the same bytes saved
            # again, or new ones), and what a use found before is dropped.
            # The upload it came from stays while the version is the same.
            kept = found.dig('file', 'attachment_id')
            entry['attachment_id'] ||= kept if kept && found.dig('file', 'sha256') == entry['sha256']
            found['file'] = entry
            found['draft'] = stringify(draft) if draft
            @verdicts.delete(found['id'])
            @texts.delete(found['id'])
            # Opened again (not an edit of it): it comes into Now.
            into_current!(data, found, origin) unless event || late?(origin)
            select_for_origin(origin, found['id'])
            record!(data, event.merge('item_id' => found['id']), origin) if event
            next [deep_dup(found), false]
          end

          place = target_place!(data, origin)
          item_id = "i_#{SecureRandom.hex(10)}"
          placed!(data, { 'id' => item_id, 'kind' => 'file', 'origin' => kept_origin(origin), 'mid' => nil,
                          'file' => entry, 'draft' => (stringify(draft) if draft) }.compact, place, origin)
          select_for_origin(origin, item_id)
          record!(data, { 'kind' => 'placed', 'item_id' => item_id }, origin)
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

          place = target_place!(data, origin)
          item_id = "i_#{SecureRandom.hex(10)}"
          placed!(data, { 'id' => item_id, 'kind' => 'browser', 'origin' => kept_origin(origin), 'mid' => nil,
                          'browser' => { 'instance' => instance } }, place, origin)
          select_for_origin(origin, item_id)
          deep_dup(data['items'][item_id])
        end
      end

      # An entry of the Library opened on the board (entry: EntryText.of),
      # shown as EntryText.shown says (its kept file, or its text, at that
      # version): the tab of origin selects it. The same entry at the same
      # version again is selected, not added. Returns [item, added].
      def add_library(entry:, origin:, epoch:)
        shown = Monadic::Library::EntryText.shown(entry)
        record = { 'id' => entry[:id].to_s, 'title' => entry[:title].to_s, 'version' => shown[:version].to_s,
                   'preview' => shown[:preview], 'source' => shown[:source], 'original' => shown[:original],
                   'content_type' => shown[:content_type] }.compact
        change do |data|
          check_epoch!(epoch)
          raise Refused, 'not_allowed' if origin[:actor].to_s == 'user' && !live?(origin[:tab], origin[:generation])

          found = data['items'].values.find do |item|
            item['kind'] == 'library' && item.dig('library', 'id') == record['id'] && item.dig('library', 'version') == record['version']
          end
          if found
            into_current!(data, found, origin) unless late?(origin)
            select_for_origin(origin, found['id'])
            next [deep_dup(found), false]
          end

          place = target_place!(data, origin)
          item_id = "i_#{SecureRandom.hex(10)}"
          placed!(data, { 'id' => item_id, 'kind' => 'library', 'origin' => kept_origin(origin), 'mid' => nil,
                          'library' => record }, place, origin)
          select_for_origin(origin, item_id)
          record!(data, { 'kind' => 'placed', 'item_id' => item_id }, origin)
          [deep_dup(data['items'][item_id]), true]
        end
      end

      # The Library item's record at the version given (no Library read).
      def library_entry(item_id, version:)
        record = @lock.synchronize { deep_dup(@data.dig('items', item_id, 'library')) } or raise Artifact::NotAllowed, 'no such entry'
        raise Artifact::Changed, 'the entry changed after it was opened' unless record['version'] == version

        record
      end

      # An item already on the board, brought before the tab of origin (the
      # reply's): it selects it, and the page shows it as it shows an item
      # made for it. Refused at another epoch, or for an item that is not
      # on the board (no other one is shown in its place). Returns the item.
      def bring(item_id:, origin:, epoch:)
        change do |data|
          check_epoch!(epoch)
          item = data['items'][item_id.to_s] or raise Refused, 'that item is not on the work screen now'
          into_current!(data, item, origin) unless late?(origin)
          select_for_origin(origin, item['id'])
          deep_dup(data['items'][item['id']])
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
          item = @data.dig('items', item_id)
          next unless item && %w[file library].include?(item['kind']) && version_of(item) == sha256

          @verdicts[item_id] = { sha256: sha256, status: status }
        end
      end

      # The text item item_id shows lines lines of the version sha256
      # (truncated: only its beginning), as served.
      def note_text(item_id, sha256:, lines:, truncated:)
        @lock.synchronize do
          item = @data.dig('items', item_id)
          next unless item && %w[file library].include?(item['kind']) && version_of(item) == sha256

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

      # Selects item_id for the tab's connection only when it selects
      # nothing (checked and done under one lock). quiet: an item for an
      # empty work screen only (the notes after a reply): the page shows it
      # where nothing is shown and brings nothing forward. Returns whether
      # it was selected.
      def offer(tab:, generation:, item_id:, quiet: false)
        @lock.synchronize do
          next false unless live?(tab, generation) && @data['items'].key?(item_id)

          held = @selected[tab.to_s]
          next false if held && held[:generation] == generation && @data['items'].key?(held[:item_id])

          selected!(tab, generation, item_id)[:quiet] = quiet
          true
        end
      end

      # selection, and whether it was offered quietly (offer), read
      # together: [item_id or nil, serial or nil, quiet].
      def selection_with_quiet(tab:, generation:)
        @lock.synchronize do
          held = @selected[tab.to_s]
          next [nil, nil, false] unless held && held[:generation] == generation && live?(tab, generation)

          item_id = @data['items'].key?(held[:item_id]) ? held[:item_id] : nil
          [item_id, held[:serial], !!(item_id && held[:quiet])]
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

      # Whether item (as it was read) is still on the board at the same
      # version.
      def still_there?(item)
        @lock.synchronize do
          now = @data['items'][item['id']]
          now && version_of(now) == version_of(item)
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

      # The image on the desk (not put away) that arrived there last, or nil.
      def latest_image
        @lock.synchronize do
          deep_dup(@data['items'].values.reverse.find { |item| item['artifact'] && item['place'] != 'stash' })
        end
      end

      # The put-away items whose name holds query (any case), the newest
      # first: { items: [{ 'id', 'kind', 'name' }] (at most limit), total: }.
      def find_put_away(query, limit: 20)
        needle = query.to_s.strip.downcase
        found = @lock.synchronize do
          @data['items'].values.reverse.filter_map do |item|
            next unless item['place'] == 'stash'

            name = name_of(item)
            { 'id' => item['id'], 'kind' => kind_name(item), 'name' => name } if name.downcase.include?(needle)
          end
        end
        { items: found.first(limit), total: found.size }
      end

      # The marks of item_id's original at its version that the message
      # request_id sent (new) and the others shown (earlier), or nil.
      def mark_counts(item_id, request_id)
        @lock.synchronize do
          item = @data['items'][item_id.to_s] or next nil
          origin = Marks.origin_of(item) or next nil
          Marks.counts(@data, origin, version_of(item), request_id)
        end
      end

      # Takes out what the message request_id recorded of the marks (it was
      # deleted). Returns how many marks it erased stayed erased (bringing
      # them back would show more than an item shows at most).
      def undo_marks(request_id)
        return 0 unless @lock.synchronize { Marks.recorded?(@data, request_id) }

        change { |data| Marks.undo!(data, request_id) }
      end

      # Whether the item is on the board and not put away.
      def on_desk?(item_id)
        @lock.synchronize do
          item = @data['items'][item_id.to_s]
          !item.nil? && item['place'] != 'stash'
        end
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
          raise Refused, BUSY if @reply

          state = user_operation!(data, item, action, operation_id)
          operation = { 'id' => operation_id, 'action' => action, 'item_id' => item_id, 'sha256' => sha256,
                        'state' => state, 'accepted_at' => Time.now.utc.iso8601 }
          data['operations'][operation_id] = operation
          data['operations'].shift while data['operations'].size > REMOVED_LIMIT
          [:accepted, deep_dup(operation)]
        end
      end

      def item(item_id)
        @lock.synchronize { deep_dup(@data['items'][item_id]) }
      end

      # The file item of path (relative to the shared folder), or nil.
      def item_at(path)
        @lock.synchronize { deep_dup(@data['items'].values.find { |i| i.dig('file', 'path') == path }) }
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

      # Adds an event to the board's (inside change): the next number, who
      # made it (the origin's actor), what it was. The oldest go past
      # EVENT_LIMIT; when one not yet told goes, the next observation says
      # some were left out.
      def record!(data, event, origin)
        data['event_seq'] = data['event_seq'].to_i + 1
        actor = origin && (origin[:actor] || origin['actor'])
        events = (data['events'] ||= [])
        events << event.merge('seq' => data['event_seq'], 'by' => actor.to_s.empty? ? 'system' : actor.to_s)
        while events.size > EVENT_LIMIT
          gone = events.shift
          data['events_lost'] = gone['seq'] if gone['seq'].to_i > data['told'].to_i
        end
      end

      def check_epoch!(epoch)
        raise Refused, 'the chat was replaced' unless epoch == Monadic::Workspace::Chats.epoch(@chat_id)
      end

      def take_off!(data, item, removed_by)
        # Its kind and name from the record (no file is read under the lock).
        entry = item['file'] || item['artifact'] || {}
        entry = { 'name' => item.dig('library', 'title') } if item['kind'] == 'library'
        kind = item['kind'] == 'file' ? entry['preview'].to_s : item['kind'].to_s
        actor = SYSTEM_REMOVALS.include?(removed_by) ? 'system' : 'user'
        record!(data, { 'kind' => 'removed', 'item_id' => item['id'], 'item_kind' => kind,
                        'name' => (entry['name'] || kind).to_s, 'reason' => (actor == 'system' ? removed_by : nil) }.compact,
                { actor: actor })
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

      # Where a new item of origin goes, checked before anything is placed:
      # current, or for the AI's placement after its reply ended (late?) the
      # layer that reply made. Refused when the user acts while a reply runs
      # (BUSY) and when the place is full (FULL): nothing is pushed out.
      def target_place!(data, origin)
        raise Refused, BUSY if user?(origin) && @reply

        place = late?(origin) ? late_layer!(data, origin[:request_id] || origin['request_id']) : 'current'
        raise Refused, FULL if count_in(data, place) >= NOW_LIMIT

        place
      end

      # A new item in place, put there by origin's actor; the user's is
      # fresh (taken off, not put away, until the turn ends).
      def placed!(data, item, place, origin)
        item['place'] = place
        item['by'] = actor_of(origin)
        item['fresh'] = true if place == 'current' && item['by'] == 'user'
        data['items'][item['id']] = item
      end

      # The item comes into current (at its end), placed now by origin's
      # actor. Refused while a reply runs for the user, and when current is
      # full.
      def into_current!(data, item, origin)
        return if item['place'] == 'current'
        raise Refused, BUSY if user?(origin) && @reply
        raise Refused, FULL if count_in(data, 'current') >= NOW_LIMIT

        moved!(data, item, 'current', origin)
        item['by'] = actor_of(origin)
      end

      # The item is put away. Refused while a reply runs for the user.
      def put_away!(data, item, origin)
        return if item['place'] == 'stash'
        raise Refused, BUSY if user?(origin) && @reply

        moved!(data, item, 'stash', origin)
        item.delete('fresh')
      end

      def moved!(data, item, place, origin)
        data['items'].delete(item['id'])
        item['place'] = place
        data['items'][item['id']] = item
        freeze_left!(data)
        record!(data, { 'kind' => 'moved', 'item_id' => item['id'], 'to' => place }, origin)
      end

      # The user's operation on item (accept): its state. remove takes off
      # what the user placed in this turn and did not send yet, and puts
      # anything else away.
      def user_operation!(data, item, action, operation_id)
        origin = { actor: 'user' }
        case action
        when 'bring'
          into_current!(data, item, origin)
          'brought'
        when 'stash'
          put_away!(data, item, origin)
          'stashed'
        else
          # A browser is not kept (it does not outlive the server): it goes.
          unless (item['place'] == 'current' && item['fresh']) || item['kind'] == 'browser'
            put_away!(data, item, origin)
            return 'stashed'
          end

          take_off!(data, item, operation_id)
          @browsers_off << item.dig('browser', 'instance') if item['kind'] == 'browser'
          put_back_browser!(data)
          'removed'
        end
      end

      # The turn of by (request_id) ends: when current holds anything, the
      # layers move down one. Returns whether they moved.
      def shift!(data, by, request_id)
        return false unless data['items'].values.any? { |item| item['place'] == 'current' }

        down = { 'current' => 'latest', 'latest' => 'previous', 'previous' => 'stash' }
        data['items'].each_value { |item| item['place'] = down.fetch(item['place'], item['place']) }
        freeze_left!(data)
        layers = (data['layers'] ||= {})
        layers['previous'] = layers['latest']
        layers['latest'] = { 'by' => by, 'request_id' => request_id }
        layers.compact!
        record!(data, { 'kind' => 'turn_ended' }, { actor: by })
        true
      end

      # The layer of the AI's reply request_id that ended (its items there
      # still); a new latest layer when that reply placed nothing yet (the
      # layers move down one, current stays).
      def late_layer!(data, request_id)
        layers = (data['layers'] ||= {})
        found = LAYERS.find { |layer| layers.dig(layer, 'by') == 'agent' && layers.dig(layer, 'request_id') == request_id }
        return found if found

        data['items'].each_value do |item|
          item['place'] = { 'latest' => 'previous', 'previous' => 'stash' }.fetch(item['place'], item['place'])
        end
        freeze_left!(data)
        layers['previous'] = layers['latest']
        layers['latest'] = { 'by' => 'agent', 'request_id' => request_id }
        layers.compact!
        'latest'
      end

      # Whether origin is the AI's, placing after its reply's turn ended (a
      # job that finished later): the item joins that reply's layer.
      def late?(origin)
        !user?(origin) && @reply.nil? && !(origin[:request_id] || origin['request_id']).nil?
      end

      def user?(origin)
        actor_of(origin) == 'user'
      end

      def actor_of(origin)
        (origin && (origin[:actor] || origin['actor'])).to_s == 'user' ? 'user' : 'agent'
      end

      # A whiteboard (a board file of the work screen).
      def whiteboard?(item)
        item['kind'] == 'file' && Monadic::Workspace::SharedFolderPreview.render_for(item.dig('file', 'path').to_s) == 'whiteboard'
      end

      # A whiteboard that can be drawn on: in Now, and never out of it since.
      def editable_whiteboard?(item)
        whiteboard?(item) && item['place'] == 'current' && !item['frozen']
      end

      # A board out of Now not yet made an image: a plain one (version 1).
      def pending_image?(item)
        whiteboard?(item) && !editable_whiteboard?(item) && plain_board?(item)
      end

      # A plain whiteboard (not drawn on a picture), as its file says;
      # remembered on the item once read.
      def plain_board?(item)
        return item['board_kind'] == 'plain' if item.key?('board_kind')

        kind = begin
          JSON.parse(FileItem.read_whole(item.dig('file', 'path'), wait: 0)[:bytes].to_s)['version'] == 2 ? 'picture' : 'plain'
        rescue StandardError
          nil
        end
        item['board_kind'] = kind if kind
        kind == 'plain'
      end

      # Whiteboards out of Now are kept as they are, also when brought back.
      def freeze_left!(data)
        data['items'].each_value { |item| item['frozen'] = true if item['place'] != 'current' && whiteboard?(item) }
      end

      def count_in(data, place)
        data['items'].count { |_, item| item['place'] == place }
      end

      # After a restart no reply runs: the AI's items left in current end
      # their turn (interrupted).
      def recover_reply!
        request_id = @data.delete('reply_request')
        turn_record!(@data, request_id, 'agent') if request_id
        return unless @data['items'].values.any? { |item| item['place'] == 'current' && item['by'] == 'agent' }

        shift!(@data, 'agent', request_id)
      end

      # The desk as the turn of by (request_id) leaves it, kept for its card
      # (TurnRecords): Now, Latest and Before in their order, each with the
      # marks shown on it, and how many are put away.
      def turn_record!(data, request_id, by)
        desk = %w[current latest previous].flat_map do |place|
          data['items'].values.select { |item| item['place'] == place }
        end
        # A drawing by its digests only (the shapes are kept once, by them).
        items = desk.map do |item|
          view = desk_item(data, item)
          view[:drawing] ? view.merge(drawing: { digests: view[:drawing][:digests] }) : view
        end
        TurnRecords.write(@chat_id, request_id, by,
                          { 'at' => Time.now.utc.iso8601, 'items' => JSON.parse(JSON.generate(items)),
                            'put_away' => data['items'].values.count { |item| item['place'] == 'stash' } })
      rescue SystemCallError, ArgumentError => e
        Monadic::Utils::ExtraLogger.log { "[Workbench] turn not recorded: #{e.class}" } if defined?(Monadic::Utils::ExtraLogger)
      end

      # The marks a message sent ({ pictures: [Picture], erased: [{ 'item_id',
      # 'version', 'targets' }] }), recorded on the items they were made on:
      # only items on the desk where marks are made, at the version the
      # message saw.
      def record_marks!(data, request_id, marks)
        sent = Array(marks[:pictures]).flat_map do |picture|
          item = markable_item(data, picture.item_id, picture.version) or next []
          picture.marks.map do |mark|
            mark.merge('page' => picture.page, origin: Marks.origin_of(item), version: picture.version)
          end
        end
        erased = Array(marks[:erased]).filter_map do |erase|
          item = markable_item(data, erase['item_id'], erase['version']) or next nil
          { origin: Marks.origin_of(item), version: erase['version'], targets: erase['targets'] }
        end
        # What the message drew on images (kept by digest), and the drawings
        # it erased: those shown on the version it saw.
        drawn = Array(marks[:pictures]).filter_map do |picture|
          next nil unless picture.drawing

          item = markable_item(data, picture.item_id, picture.version) or next nil
          { origin: Marks.origin_of(item), version: picture.version, digest: Drawings.keep!(@chat_id, picture.drawing, store: @store) }
        end
        drawing_erased = Array(marks[:erased]).filter_map do |erase|
          given = Array(erase['drawings'])
          next nil if given.empty?

          item = markable_item(data, erase['item_id'], erase['version']) or next nil
          origin = Marks.origin_of(item)
          { origin: origin, version: erase['version'], digests: Marks.drawn(data, origin, erase['version']) & given }
        end
        Marks.record!(data, request_id, sent: sent, erased: erased, drawn: drawn, drawing_erased: drawing_erased)
      end

      def markable_item(data, item_id, version)
        item = data['items'][item_id.to_s]
        return nil unless item && %w[current latest].include?(item['place']) && version_of(item) == version

        Marks.origin_of(item) ? item : nil
      end

      # What was drawn on a desk item's original at its version, as the page
      # draws it under this turn's: { digests, shapes } (shapes of every
      # drawing shown, in order), or nil.
      def shown_drawing(data, item)
        return nil if item['place'] == 'stash'

        origin = Marks.origin_of(item) or return nil
        digests = Marks.drawn(data, origin, version_of(item))
        return nil if digests.empty?

        shapes = digests.flat_map { |digest| Drawings.read(@chat_id, digest, store: @store) || [] }
        { digests: digests, shapes: shapes }
      end

      # The marks shown on a desk item's original at its version (none put
      # away: a put-away item is drawn only when opened).
      def shown_marks(data, item)
        return nil if item['place'] == 'stash'

        origin = Marks.origin_of(item) or return nil
        marks = Marks.shown(data, origin, version_of(item))
        marks.empty? ? nil : marks
      end

      # An item's name and kind from its record (no file is read).
      def name_of(item)
        (item.dig('file', 'name') || item.dig('artifact', 'name') || item.dig('library', 'title') || item['kind']).to_s
      end

      def kind_name(item)
        item['kind'] == 'file' ? item.dig('file', 'preview').to_s : item['kind'].to_s
      end

      def public_layers(data)
        LAYERS.to_h { |layer| [layer, data.dig('layers', layer, 'by')] }.compact
      end

      # The chat's open browser, when it is not on the board (it opened
      # while every item was kept) and the user did not take it off, is put
      # on in the room just made.
      def put_back_browser!(data)
        view = defined?(MonadicSharedTools::BrowserOwner) && MonadicSharedTools::BrowserOwner.view(@chat_id)
        return unless view && view.epoch == Monadic::Workspace::Chats.epoch(@chat_id)
        return if @browsers_off.include?(view.instance) || count_in(data, 'current') >= NOW_LIMIT
        return if data['items'].values.any? { |item| item.dig('browser', 'instance') == view.instance }

        item_id = "i_#{SecureRandom.hex(10)}"
        placed!(data, { 'id' => item_id, 'kind' => 'browser', 'origin' => { 'actor' => 'agent', 'source' => 'browser' },
                        'mid' => nil, 'browser' => { 'instance' => view.instance } }, 'current', { actor: 'agent' })
      end

      # The item's content entry: the image's record or the file's version.
      def content_of(item)
        item['artifact'] || item['file']
      end

      # What an operation's token names of the item: the sha256 of an image
      # or a file, the instance of a browser.
      def version_of(item)
        return "browser:#{item.dig('browser', 'instance')}" if item['kind'] == 'browser'
        return item.dig('library', 'version') if item['kind'] == 'library'

        content_of(item)&.dig('sha256')
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

      # What a view shows of an item: where it is on the desk with it.
      # An item as the page draws it, with the marks shown on it and what was
      # drawn on it.
      def desk_item(data, item)
        view = public_item(item)
        marks = shown_marks(data, item)
        view = view.merge(marks: marks) if marks
        drawing = shown_drawing(data, item)
        drawing ? view.merge(drawing: drawing) : view
      end

      def public_item(item)
        item_view(item).merge(place: item['place'] || 'stash', by: item['by'], fresh: item['fresh'] ? true : nil)
      end

      def item_view(item)
        return public_file(item) if item['kind'] == 'file'
        if item['kind'] == 'library'
          entry = item['library']
          return { id: item['id'], kind: 'library', actor: item.dig('origin', 'actor'), mid: item['mid'],
                   name: entry['title'], library_id: entry['id'], version: entry['version'], sha256: entry['version'],
                   preview: entry['preview'] || 'text', content_type: entry['content_type'],
                   original: entry['original'] ? true : nil, status: library_status(item) }.compact
        end
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

      # What a use found (mark) for this version, else ok: the Library is
      # read when the item is shown or looked at, not for every view.
      def library_status(item)
        verdict = @verdicts[item['id']]
        verdict && verdict[:sha256] == item.dig('library', 'version') ? verdict[:status] : 'ok'
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
          render: Monadic::Workspace::SharedFolderPreview.render_for(entry['path']),
          # A document the Library takes (Library::DeskImport).
          library: Monadic::Library::FileImporter.importable?(entry['path']) || nil,
          # A document is named by its title where its file's name is not it.
          title: defined?(Document) ? Document.shown_title(entry['path']) : nil,
          # A record of a conversation, to keep in the Library as one.
          draft: item['draft'] ? true : nil,
          # A whiteboard no longer drawn on (it left Now), and the version of
          # it a page is to paint as its image (a plain board).
          frozen: (true if whiteboard?(item) && !editable_whiteboard?(item)),
          image_pending: (entry['sha256'] if pending_image?(item))
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
