# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'time'
require_relative 'store'
require_relative 'image_check'
require_relative '../workspace/chats'

module Monadic
  module Workbench
    # A chat's workbench: the images on it (each with its candidate's bytes),
    # in the order they arrived, and the operations the user started on
    # them: saving an image to the shared folder, or removing it from the
    # board. Any image can be saved or removed at any time; nothing waits
    # for an answer. Kept in the chat's manifest (Store) so it outlives a
    # restart; a Private chat's board is kept in memory only and nothing of
    # it is written.
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
      ACTIONS = %w[save remove].freeze
      # Removed items remembered, so that a removal sent again is answered.
      REMOVED_LIMIT = 50

      class Refused < StandardError; end

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
        @data['removed'] ||= {}
      end

      def private?
        @private
      end

      # A view of the board for the pages of the chat: what the items are and
      # what may be done with them. Holds no token and no path.
      def snapshot
        @lock.synchronize do
          {
            board_id: @data['board_id'], chat_id: @chat_id, epoch: Monadic::Workspace::Chats.epoch(@chat_id),
            revision: @data['revision'],
            items: @data['items'].values.map { |item| public_item(item) }
          }
        end
      end

      # Puts a checked image on the board. Returns the item. Refused for a
      # Private chat (nothing of it may be kept), at another epoch of the
      # chat, and when unless_closed (asked under the board's lock) says
      # the reply that made it was stopped. derived_from: the image it was
      # made from ({id:, sha256:}, as read when the generation began).
      def add_candidate(bytes:, epoch:, origin:, name:, derived_from: nil, unless_closed: nil)
        raise Refused, 'a Private chat keeps no candidate' if @private

        image = ImageCheck.check!(bytes)
        sha256 = Digest::SHA256.hexdigest(bytes)
        candidate_id = "k_#{SecureRandom.hex(10)}"
        ext = image[:content_type].split('/').last.sub('jpeg', 'jpg')
        relative = "candidates/#{candidate_id}/image.#{ext}"

        change do |data|
          check_epoch!(epoch)
          raise Refused, 'the reply was stopped' if unless_closed&.call

          put_away_for_room!(data)
          @store.write_new(@chat_id, relative, bytes)
          item_id = "i_#{SecureRandom.hex(10)}"
          data['items'][item_id] = {
            'id' => item_id, 'kind' => 'image', 'origin' => stringify(origin), 'mid' => nil,
            'candidate' => {
              'id' => candidate_id, 'path' => relative, 'sha256' => sha256, 'size' => bytes.bytesize,
              'content_type' => image[:content_type], 'width' => image[:width], 'height' => image[:height],
              'name' => name, 'derived_from' => derived_from && stringify(derived_from)
            }
          }
          deep_dup(data['items'][item_id])
        end
      end

      # The image that arrived on the board last, or nil.
      def latest_image
        @lock.synchronize { deep_dup(@data['items'].values.reverse.find { |item| item['candidate'] }) }
      end

      # The bytes of an item's candidate, read and checked against its sha256
      # under the board's lock (no removal comes in between): {id:, sha256:,
      # name:, content_type:, bytes:}. Refused when the item is gone or its
      # bytes changed.
      def candidate_input(item_id)
        @lock.synchronize do
          candidate = @data.dig('items', item_id, 'candidate') or raise Refused, 'no such image'
          bytes = @store.read(@chat_id, candidate['path'])
          raise Refused, 'the image changed' unless Digest::SHA256.hexdigest(bytes) == candidate['sha256']

          { id: item_id, sha256: candidate['sha256'], name: candidate['name'],
            content_type: candidate['content_type'], bytes: bytes }
        end
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

      # The message of an item with none (the note made for a save of an
      # image whose reply recorded no message).
      def attach_note(item_id, mid)
        change do |data|
          item = data['items'][item_id]
          item['mid'] = mid if item && item['mid'].nil?
        end
      end

      # Takes the user's operation on an image. One change: the operation is
      # made and the board updated, so a second operation finds it. sha256 is
      # the candidate's the user's token was given for. Returns [:accepted,
      # operation] for a new operation, [:same, operation] for the same
      # operation sent again (also once a removed item is gone), [:taken,
      # operation] when the image was saved by another operation, or raises
      # Refused.
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
          raise Refused, 'this image changed' unless item.dig('candidate', 'sha256') == sha256

          action == 'save' ? accept_save(data, item, operation_id) : accept_remove(data, item, operation_id)
        end
      end

      # Moves an operation on (Saver), keeping what its step found.
      def advance(operation_id, state, **fields)
        change do |data|
          operation = data['operations'][operation_id] or raise Refused, 'no such operation'
          operation.merge!(stringify(fields))
          operation['state'] = state
          deep_dup(operation)
        end
      end

      # Records a saved artifact (the kept original), for the record of the
      # message and the export.
      def keep_artifact(artifact_id, record)
        change { |data| data['artifacts'][artifact_id] = stringify(record) }
      end

      def artifact(artifact_id)
        @lock.synchronize { deep_dup(@data['artifacts'][artifact_id]) }
      end

      def operation(operation_id)
        @lock.synchronize { deep_dup(@data['operations'][operation_id]) }
      end

      def item(item_id)
        @lock.synchronize { deep_dup(@data['items'][item_id]) }
      end

      # Saves that were accepted and not finished (a restart in the middle):
      # the Saver finishes them.
      def unfinished_operations
        @lock.synchronize do
          @data['operations'].values.select { |op| op['action'] == 'save' && !finished?(op) }.map { |op| deep_dup(op) }
        end
      end

      # Saves that reached the message's record.
      def recorded_operations
        @lock.synchronize do
          @data['operations'].values.select { |op| op['action'] == 'save' && op['state'] == 'recorded' }.map { |op| deep_dup(op) }
        end
      end

      def path(relative)
        @store.path(@chat_id, relative)
      end

      def read(relative)
        @store.read(@chat_id, relative)
      end

      def write_new(relative, bytes)
        @store.write_new(@chat_id, relative, bytes)
      end

      private

      def fresh
        { 'schema' => Store::SCHEMA, 'chat_id' => @chat_id, 'board_id' => SecureRandom.hex(8),
          'revision' => 0, 'items' => {}, 'operations' => {}, 'artifacts' => {}, 'removed' => {} }
      end

      # Candidates taken off the board lose their bytes once the manifest
      # without them is saved (a crash before leaves bytes no item names,
      # never an item without its bytes).
      # A change is not cut off by a thread being stopped (the reply's thread
      # when the reply is cancelled): the manifest saved and the board held
      # here stay the same.
      def change
        Thread.handle_interrupt(Object => :never) do
          @lock.synchronize do
            @trash = []
            working = deep_dup(@data)
            result = yield working
            working['revision'] += 1
            @store.save(@chat_id, working) unless @private
            @data = working
            @trash.compact.each { |id| @store.remove_candidate(@chat_id, id) } unless @private
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

      # One save per image: an image saved (or being saved) by another
      # operation answers with that one.
      def accept_save(data, item, operation_id)
        if (saved = item['save_operation_id'])
          return [:taken, deep_dup(data['operations'][saved])]
        end

        operation = save_operation(item, operation_id)
        item['save_operation_id'] = operation_id
        data['operations'][operation_id] = operation
        [:accepted, deep_dup(operation)]
      end

      # An image being saved stays until its save is finished. What a save
      # made (the original, the shared copy, the message's record) stays
      # when the image is removed: only the candidate's bytes go.
      def accept_remove(data, item, operation_id)
        raise Refused, 'this image is being saved' if saving?(data, item)

        operation = base_operation(item, operation_id, 'remove').merge('state' => 'removed')
        data['operations'][operation_id] = operation
        take_off!(data, item, operation_id)
        [:accepted, deep_dup(operation)]
      end

      def take_off!(data, item, removed_by)
        data['items'].delete(item['id'])
        data['removed'][item['id']] = removed_by
        data['removed'].shift while data['removed'].size > REMOVED_LIMIT
        @trash << item.dig('candidate', 'id')
      end

      # Room for one more image: the oldest saved image is put away first
      # (the shared folder has it), then the oldest not saved. The latest
      # image (what an edit starts from) and one being saved stay.
      def put_away_for_room!(data)
        return if data['items'].size < ITEM_LIMIT

        latest = data['items'].values.reverse.find { |item| item['candidate'] }
        spare = data['items'].values.reject { |item| item.equal?(latest) || saving?(data, item) }
        victim = spare.find { |item| saved?(data, item) } || spare.first
        raise Refused, 'the workbench is full' unless victim

        take_off!(data, victim, 'room')
      end

      def saved?(data, item)
        data.dig('operations', item['save_operation_id'].to_s, 'state') == 'recorded'
      end

      def saving?(data, item)
        id = item['save_operation_id']
        id && !finished?(data.dig('operations', id) || {})
      end

      def finished?(operation)
        %w[recorded failed removed].include?(operation['state'])
      end

      def base_operation(item, operation_id, action)
        candidate = item['candidate']
        { 'id' => operation_id, 'action' => action, 'item_id' => item['id'], 'candidate_id' => candidate['id'],
          'sha256' => candidate['sha256'], 'accepted_at' => Time.now.utc.iso8601 }
      end

      def save_operation(item, operation_id)
        candidate = item['candidate']
        artifact_id = "r_#{SecureRandom.hex(10)}"
        ext = File.extname(candidate['path'])
        base_operation(item, operation_id, 'save').merge(
          'state' => 'accepted', 'mid' => item['mid'], 'artifact_id' => artifact_id,
          'original' => "artifacts/#{artifact_id}/image#{ext}", 'reserved_name' => candidate['name'],
          'temp_name' => ".monadic-op-#{artifact_id}"
        )
      end

      def public_item(item)
        candidate = item['candidate'] || {}
        save = item['save_operation_id'] && @data['operations'][item['save_operation_id']]
        {
          id: item['id'], kind: item['kind'], actor: item.dig('origin', 'actor'), mid: item['mid'],
          name: candidate['name'], content_type: candidate['content_type'],
          width: candidate['width'], height: candidate['height'], sha256: candidate['sha256'],
          derived_from: candidate.dig('derived_from', 'sha256'),
          save: save && { state: save['state'], name: save['final_name'] }
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
