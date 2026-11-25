# frozen_string_literal: true

require_relative 'sent'

module Monadic
  module Workbench
    # The images of the work screen an image edit of a reply handed to its
    # provider (the original, and the reference drawn on it), for its
    # message: one record per image of each call, kept in memory while the
    # reply runs and given to its message once (seal), or to the user's
    # message of the request when the reply ends without one (close). The
    # images themselves are kept as sent (Sent); a record names one by its
    # sha256 and gives no right to read it.
    module EditInputs
      KEY = 'workbench_edit_inputs'
      LIMIT = 40
      ROLES = %w[original reference].freeze
      STATES = %w[sent refused].freeze
      CALL = /\Ae_\h{16}\z/
      CLOSED_LIMIT = 1000

      @open = {}
      @closed = {}
      @lock = Mutex.new

      module_function

      # Records that a call (call: its id) of the reply request_id handed
      # the image sha256 (content_type, role) to the provider, which took it
      # or not (state). A reply that ended takes nothing more.
      def add(request_id, chat_id, call:, role:, sha256:, content_type:, state:, session: nil)
        record = clean([{ 'call' => call, 'role' => role, 'sha256' => sha256, 'content_type' => content_type,
                          'state' => state }])&.first or return false
        @lock.synchronize do
          next false if @closed.key?(request_id)

          entry = (@open[request_id] ||= { chat_id: chat_id, session: session, records: [] })
          next false if entry[:records].size >= LIMIT

          entry[:records] << record
          true
        end
      end

      # The reply's records, once: its message takes them, and the images
      # they name are no longer pending.
      def seal(request_id)
        take(request_id)&.fetch(:records) || []
      end

      # The reply's records with its chat and session ({ chat_id:, session:,
      # records: }), once, or nil; as seal.
      def take(request_id)
        entry = @lock.synchronize do
          next nil if @closed.key?(request_id)

          @closed[request_id] = true
          @closed.shift while @closed.size > CLOSED_LIMIT
          @open.delete(request_id)
        end
        return nil unless entry

        Sent.done(entry[:chat_id], entry[:records].map { |r| r['sha256'] })
        entry
      end

      # Records as a message keeps them (from a reply, from history or an
      # imported file): the known keys of the right form, at most LIMIT;
      # nil when none is left.
      def clean(records)
        return nil unless records.is_a?(Array)

        kept = records.first(LIMIT).filter_map do |record|
          next unless record.is_a?(Hash)

          out = record.transform_keys(&:to_s).slice('call', 'role', 'sha256', 'content_type', 'state')
          next unless out['call'].is_a?(String) && out['call'].match?(CALL) && ROLES.include?(out['role'])
          next unless out['sha256'].is_a?(String) && out['sha256'].match?(/\A\h{64}\z/)
          next unless Sent::EXTENSIONS.key?(out['content_type']) && STATES.include?(out['state'])

          out
        end
        kept.empty? ? nil : kept
      end
    end
  end
end
