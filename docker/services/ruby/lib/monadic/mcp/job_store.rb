# frozen_string_literal: true

require 'securerandom'
require 'time'

module Monadic
  module MCP
    # In-memory, thread-safe registry of background Conduit jobs.
    #
    # Why this exists: Falcon runs a single worker (-n 1), so every Web UI
    # WebSocket and every Conduit tool call shares one Async reactor. Long or
    # blocking tools (TTS, media generation, code agents) would freeze the Web
    # UI if run inline on the reactor fiber — exactly the reason the Web UI
    # offloads such work to Thread.new (see websocket/tts_handler.rb). JobStore
    # generalizes that: a submitted job runs on its own Thread (off the
    # reactor) and the caller polls for completion.
    #
    # Jobs are process-local and lost on restart. ProgressBroadcaster is push-
    # based (WebSocket); this is the pull-side state a polling CLI needs.
    module JobStore
      module_function

      # Concurrency gate (design §5): cap simultaneously-running jobs so a CLI
      # agent cannot spawn unbounded threads / parallel API spend.
      MAX_CONCURRENT = 3

      # Finished jobs are swept this long after completion to bound memory.
      TTL_SECONDS = 1800

      RUNNING = "running"
      DONE = "done"
      ERROR = "error"
      CANCELLED = "cancelled"
      TERMINAL = [DONE, ERROR, CANCELLED].freeze

      Job = Struct.new(
        :id, :tool, :arguments, :status,
        :result, :error, :created_at, :finished_at, :thread,
        :progress, :progress_at,
        keyword_init: true
      )

      # Cap a single progress snapshot so streaming fragments can't bloat the
      # job record (poll returns the latest snapshot, not a log).
      PROGRESS_MAX_CHARS = 240

      class ConcurrencyLimit < StandardError; end

      @jobs = {}
      @mutex = Mutex.new

      # Register a job and start its worker thread. The block does the actual
      # work (off the reactor) and returns the tool result or raises.
      def submit(tool:, arguments:, &work)
        @mutex.synchronize do
          sweep_expired_locked
          if running_count_locked >= MAX_CONCURRENT
            raise ConcurrencyLimit,
                  "Too many concurrent jobs (#{MAX_CONCURRENT}). Poll or cancel existing jobs first."
          end

          id = SecureRandom.uuid
          job = Job.new(id: id, tool: tool, arguments: arguments,
                        status: RUNNING, created_at: Time.now)
          @jobs[id] = job
          job.thread = Thread.new do
            # The work block reads this once (on the job thread) to capture the
            # id into a progress closure; agent progress sub-threads then report
            # via the captured id, not this thread-local.
            Thread.current[:conduit_job_id] = id
            begin
              # Explicit block object (not `yield`): the work runs on this
              # separate thread, so capturing it as a Proc keeps the cross-
              # thread hand-off obvious.
              res = work.call # rubocop:disable Performance/RedundantBlockCall
              finish(id, status: DONE, result: res)
            rescue StandardError => e
              finish(id, status: ERROR, error: e.message)
            end
          end
          job
        end
      end

      def fetch(id)
        @mutex.synchronize { @jobs[id] }
      end

      # The id of the job whose work block is currently executing on this
      # thread (nil when a tool runs synchronously, outside any job). A handler
      # reads this on the job thread to build a progress closure.
      def current_job_id
        Thread.current[:conduit_job_id]
      end

      # Record a periodic progress snapshot for a job. Safe to call from an
      # agent's progress sub-thread (id is passed explicitly, not thread-local).
      def report(id, message)
        snapshot = message.to_s
        snapshot = "#{snapshot[0, PROGRESS_MAX_CHARS]}…" if snapshot.length > PROGRESS_MAX_CHARS
        @mutex.synchronize do
          job = @jobs[id]
          break unless job

          job.progress = snapshot
          job.progress_at = Time.now
        end
      end

      # Kill switch (design §5). Killing a thread mid-subprocess may leave an
      # orphaned child (e.g. tts_query.rb) running to completion with its
      # output discarded — acceptable for a cancel.
      def cancel(id)
        @mutex.synchronize do
          job = @jobs[id]
          return nil unless job
          if job.status == RUNNING
            job.thread&.kill
            job.status = CANCELLED
            job.finished_at = Time.now
          end
          job
        end
      end

      def list
        @mutex.synchronize do
          sweep_expired_locked
          @jobs.values.map { |j| summarize(j) }
        end
      end

      def summarize(job)
        {
          job_id: job.id,
          tool: job.tool,
          status: job.status,
          progress: job.progress,
          created_at: job.created_at&.iso8601,
          finished_at: job.finished_at&.iso8601
        }.compact
      end

      # Test/runtime helper: kill any running workers and clear the registry.
      def reset!
        @mutex.synchronize do
          @jobs.each_value { |j| j.thread&.kill if j.status == RUNNING }
          @jobs.clear
        end
      end

      # --- internal -----------------------------------------------------

      def finish(id, status:, result: nil, error: nil)
        @mutex.synchronize do
          job = @jobs[id]
          break unless job
          break if job.status == CANCELLED # a concurrent cancel wins

          job.status = status
          job.result = result
          job.error = error
          job.finished_at = Time.now
        end
      end

      def running_count_locked
        @jobs.values.count { |j| j.status == RUNNING }
      end

      def sweep_expired_locked
        now = Time.now
        @jobs.delete_if do |_, j|
          TERMINAL.include?(j.status) && j.finished_at && (now - j.finished_at) > TTL_SECONDS
        end
      end
    end
  end
end
