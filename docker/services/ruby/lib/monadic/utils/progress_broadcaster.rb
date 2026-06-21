module Monadic
  module Utils
    # Periodically broadcasts a `wait`-type WebSocket fragment while a
    # long-running block executes — gives users a visible heartbeat for
    # operations (image/video/audio generation, etc.) that can take
    # minutes and would otherwise look frozen.
    #
    # The block's return value is preserved unchanged. If the block
    # raises, the progress thread is still stopped and the exception
    # propagates.
    #
    # Usage:
    #   ProgressBroadcaster.with_progress(source: "ImageGenerator",
    #                                     label: "Generating image with gpt-image-2") do
    #     send_command(command: cmd, container: "ruby")
    #   end
    module ProgressBroadcaster
      DEFAULT_INTERVAL_SECONDS = 30

      module_function

      # Run +block+, broadcasting progress every +interval+ seconds.
      #
      # @param source [String] Identifier shown in the fragment's "source" field
      #   (e.g., "ImageGeneratorOpenAI"). Used by the frontend to disambiguate.
      # @param label [String] Human-readable operation description used in the
      #   "content" field shown in the temp card.
      # @param interval [Integer] Seconds between broadcasts. Defaults to 30s
      #   (faster than the code-agent's 60s because media latencies are 1-4 min,
      #   not 10-20 min).
      # @return [Object] Whatever +block+ returns.
      def with_progress(source:, label:, interval: DEFAULT_INTERVAL_SECONDS)
        # Capture parent thread's session id BEFORE spawning — child threads
        # don't inherit thread-local variables in Ruby, so we must read it
        # in the parent and pass it explicitly.
        parent_session_id = Thread.current[:websocket_session_id]
        # Same reason for the Conduit background-job id: when a generator runs
        # inside a headless Conduit job there is no WebSocket session, so we
        # also mirror progress into the job record for polling clients.
        parent_job_id = Thread.current[:conduit_job_id]

        progress_thread = spawn_progress_thread(
          source: source,
          label: label,
          interval: interval,
          session_id: parent_session_id,
          job_id: parent_job_id
        )

        begin
          yield
        ensure
          stop_thread(progress_thread)
        end
      end

      # Internal: build the fragment broadcast each tick.
      def build_fragment(source:, label:, elapsed:)
        minutes = (elapsed / 60).floor
        seconds = (elapsed % 60).floor
        elapsed_str = minutes > 0 ? "#{minutes}m #{seconds}s" : "#{seconds}s"
        {
          "type" => "wait",
          "content" => "#{label} — #{elapsed_str} elapsed",
          "source" => source,
          "elapsed" => elapsed.to_i,
          "minutes" => minutes
        }
      end

      def spawn_progress_thread(source:, label:, interval:, session_id:, job_id: nil)
        Thread.new do
          Thread.current.report_on_exception = false
          start = Time.now
          last_broadcast = start

          until Thread.current[:should_stop]
            # Sleep in small slices so :should_stop responds quickly
            # at block completion and we don't keep the parent waiting
            # in `ensure` for up to a full interval.
            (interval * 2).times do
              sleep 0.5
              break if Thread.current[:should_stop]
            end
            break if Thread.current[:should_stop]

            now = Time.now
            next if (now - last_broadcast) < interval

            elapsed = now - start
            fragment = build_fragment(source: source, label: label, elapsed: elapsed)
            broadcast(fragment, session_id)
            report_to_job(job_id, fragment)
            last_broadcast = now
          end
        rescue StandardError
          # Progress is best-effort. Never let a broadcast hiccup
          # propagate into the surrounding generator call.
        end
      end

      def broadcast(fragment, session_id)
        return unless defined?(::WebSocketHelper)
        return unless ::WebSocketHelper.respond_to?(:send_progress_fragment)
        ::WebSocketHelper.send_progress_fragment(fragment, session_id)
      rescue StandardError
        # silent — see spawn_progress_thread rescue
      end

      # Mirror progress into a Conduit background job, if one is driving this
      # work. Guarded by defined? so ProgressBroadcaster stays usable wherever
      # the MCP layer isn't loaded.
      def report_to_job(job_id, fragment)
        return unless job_id
        return unless defined?(Monadic::MCP::JobStore)

        Monadic::MCP::JobStore.report(job_id, fragment["content"])
      rescue StandardError
        # silent — see spawn_progress_thread rescue
      end

      def stop_thread(thread)
        return unless thread
        thread[:should_stop] = true
        # join with short timeout: the polling loop sleeps in 0.5s slices
        # so the thread should exit promptly. Fall back to kill if it doesn't.
        thread.join(2) || thread.kill
      rescue StandardError
        # ignore — thread may already be dead
      end
    end
  end
end
