# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'time'
require_relative 'store'
require_relative 'image_check'
require_relative 'artifact'
require_relative '../workspace/chats'

module Monadic
  module Workbench
    # A chat's workbench: the images on it, in the order they arrived. Each
    # image is a file of the chat's folder in the shared folder, recorded in
    # the ledger (Artifact); an item holds that record's id and what the
    # page shows, never the bytes. Removing an image takes it off the board
    # only: the file stays. Kept in the chat's manifest (Store) so it
    # outlives a restart. A Private chat has no board that holds anything:
    # nothing of it may be kept.
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
        def for(chat_id, private: false, store: Store.default)
          @boards_lock.synchronize do
            @boards[chat_id] ||= new(chat_id, private: private, store: store)
          end
        end

        # The board of a chat that has one (loaded, or kept in a manifest),
        # or nil: nothing is made for a chat that never used the workbench.
        def existing(chat_id, private: false, store: Store.default)
          loaded = @boards_lock.synchronize { @boards[chat_id] }
          return loaded if loaded
          return nil if private || !store.exists?(chat_id)

          self.for(chat_id, private: private, store: store)
        end

        def forget(chat_id)
          @boards_lock.synchronize { @boards.delete(chat_id) }
        end

        # For tests.
        def reset!
          @boards_lock.synchronize { @boards.clear }
        end
      end

      attr_reader :chat_id

      def initialize(chat_id, private: false, store: Store.default)
        @chat_id = chat_id
        @private = private
        @store = store
        @lock = Mutex.new
        @data = (private ? nil : store.load(chat_id)) || fresh
      end

      def private?
        @private
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
      # Refused (nothing placed) for a Private chat, at another epoch, for a
      # stopped reply, for bytes that are not an image. PlacedOnly when the
      # image was placed and the board did not take it.
      def add_image(bytes:, epoch:, origin:, name:, run:, app_name:, derived_from: nil, unless_closed: nil)
        raise Refused, 'a Private chat keeps no image' if @private

        image = ImageCheck.check!(bytes)
        record = nil
        change do |data|
          check_epoch!(epoch)
          raise Refused, 'the reply was stopped' if unless_closed&.call

          if (placed = placed_item(data, run, origin[:request_id], bytes))
            next placed
          end

          room_for_one!(data)
          record = Artifact.place!(chat_id: @chat_id, app_name: app_name, bytes: bytes, image: image, name: name,
                                   run: run, request_id: origin[:request_id], derived_from: derived_from)
          item_id = "i_#{SecureRandom.hex(10)}"
          data['items'][item_id] = {
            'id' => item_id, 'kind' => 'image', 'origin' => stringify(origin), 'mid' => nil,
            'artifact' => stringify(Artifact.entry(record).merge('width' => record[:width], 'height' => record[:height]))
          }
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
          raise Refused, 'this image changed' unless item.dig('artifact', 'sha256') == sha256

          operation = { 'id' => operation_id, 'action' => action, 'item_id' => item_id, 'sha256' => sha256,
                        'state' => 'removed', 'accepted_at' => Time.now.utc.iso8601 }
          data['operations'][operation_id] = operation
          data['operations'].shift while data['operations'].size > REMOVED_LIMIT
          take_off!(data, item, operation_id)
          [:accepted, deep_dup(operation)]
        end
      end

      def item(item_id)
        @lock.synchronize { deep_dup(@data['items'][item_id]) }
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
            @store.save(@chat_id, working) unless @private
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

      # Room for one more image: the oldest image is taken off the board
      # (its file stays in the shared folder).
      def room_for_one!(data)
        return if data['items'].size < ITEM_LIMIT

        take_off!(data, data['items'].values.first, 'room')
      end

      def public_item(item)
        entry = item['artifact'] || {}
        {
          id: item['id'], kind: item['kind'], actor: item.dig('origin', 'actor'), mid: item['mid'],
          artifact_id: entry['id'], name: entry['name'], path: entry['path'], content_type: entry['content_type'],
          width: entry['width'], height: entry['height'], sha256: entry['sha256'],
          derived_from: entry['derived_from'],
          status: entry['id'] ? Artifact.status(entry['id'], chat_id: @chat_id).to_s : 'missing'
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
