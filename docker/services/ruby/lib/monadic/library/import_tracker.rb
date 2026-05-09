# frozen_string_literal: true

require 'securerandom'

module Monadic
  module Library
    # In-memory tracker for asynchronous file imports.
    #
    # POST /library/import returns immediately with an `import_id`; a
    # background worker thread does the heavy work (extract → embed →
    # store) and updates the tracker as it progresses. The frontend
    # polls GET /library/import/status/:id to display progress.
    #
    # State is in-process and ephemeral. A server restart loses status
    # entries, but in-flight imports complete in seconds-to-minutes so
    # this rarely matters in practice; a successful import is reflected
    # in Qdrant regardless of whether the status entry survives. The
    # client treats a 404 on poll as "import already finished AND was
    # purged" rather than as a hard error.
    #
    # Entries are auto-purged after TTL_SECONDS once they reach a
    # terminal state, to prevent unbounded growth from forgotten polls.
    module ImportTracker
      TTL_SECONDS = 3600  # 1 hour after completion

      # Stage values are an open vocabulary used by both the backend
      # (writing) and the frontend (rendering progress text). Keep them
      # in sync with the labels in `library-panel.js`.
      STAGES = %w[queued extracting embedding_storing done error].freeze

      @entries = {}
      @mutex = Mutex.new

      module_function

      def create
        id = SecureRandom.uuid
        @mutex.synchronize do
          @entries[id] = {
            stage: 'queued',
            started_at: Time.now,
            updated_at: Time.now
          }
          purge_expired_locked
        end
        id
      end

      def update(id, **fields)
        @mutex.synchronize do
          entry = @entries[id]
          return unless entry
          entry.merge!(fields)
          entry[:updated_at] = Time.now
        end
      end

      # Returns a snapshot copy so the caller cannot accidentally mutate
      # tracker state outside the mutex.
      def get(id)
        @mutex.synchronize do
          entry = @entries[id]
          entry && entry.dup
        end
      end

      def delete(id)
        @mutex.synchronize { @entries.delete(id) }
      end

      # Test helper. Production code should never call this.
      def reset!
        @mutex.synchronize { @entries.clear }
      end

      # Test helper.
      def size
        @mutex.synchronize { @entries.size }
      end

      def purge_expired_locked
        cutoff = Time.now - TTL_SECONDS
        @entries.delete_if do |_id, entry|
          # Only purge entries that finished or errored — in-flight
          # entries (no :finished_at) keep their slot regardless of age,
          # since killing a stale-but-still-running import is worse than
          # a small memory leak.
          entry[:finished_at] && entry[:finished_at] < cutoff
        end
      end
    end
  end
end
