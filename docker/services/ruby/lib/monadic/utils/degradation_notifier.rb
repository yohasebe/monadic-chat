# frozen_string_literal: true

require_relative 'environment'

module Monadic
  module Utils
    # Single funnel for "the app keeps working but a component is degraded"
    # events: a dependency container failed to start, privacy masking is
    # unavailable, an internal service is unreachable, and so on.
    #
    # Unlike ExtraLogger (gated behind EXTRA_LOGGING), reports are ALWAYS
    # recorded — to STDERR and to log/degradation.log — because infrastructure
    # degradation that only debug users can see is indistinguishable from a
    # silent failure. If an active WebSocket session exists, the user is also
    # shown a System card once per component within DEDUP_TTL_SECONDS.
    #
    # Usage:
    #   DegradationNotifier.report(
    #     component: "privacy",
    #     message: "Masking unavailable; snippet withheld from provider",
    #     severity: :error
    #   )
    module DegradationNotifier
      DEDUP_TTL_SECONDS = 300
      LOG_FILE_NAME = 'degradation.log'

      SEVERITIES = %i[info warning error].freeze

      @mutex = Mutex.new
      @last_notified = {}

      class << self
        # Record a degradation event. Never raises.
        #
        # @param component [String] stable identifier of the degraded part
        #   (e.g. "container:python", "privacy", "embeddings"); also the UI
        #   dedup key.
        # @param message [String] human-readable description of the degradation
        #   and its consequence.
        # @param severity [Symbol] :info, :warning (default) or :error.
        def report(component:, message:, severity: :warning)
          severity = :warning unless SEVERITIES.include?(severity)
          line = format_line(component, message, severity)
          write_stderr(line)
          write_log_file(line)
          notify_ui(component, message, severity)
          nil
        end

        # Test hook: clear the UI dedup state.
        def reset!
          @mutex.synchronize { @last_notified.clear }
        end

        private

        def format_line(component, message, severity)
          timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
          "[#{timestamp}] [DEGRADED] [#{severity.to_s.upcase}] #{component}: #{message}"
        end

        def write_stderr(line)
          warn line
        rescue StandardError
          # Reporting must never break the caller.
        end

        def write_log_file(line)
          path = File.join(Monadic::Utils::Environment.log_path, LOG_FILE_NAME)
          Monadic::Utils::Environment.rotate_log(path)
          File.open(path, 'a') { |f| f.puts(line) }
        rescue StandardError
          # Reporting must never break the caller (log dir may not exist yet).
        end

        # Show a System card in the conversation via the existing system_info
        # message type. Deduplicated per component so a flapping component
        # does not spam the chat (the log file still records every event).
        def notify_ui(component, message, severity)
          return unless ui_notification_due?(component)
          return unless defined?(::WebSocketHelper) &&
                        ::WebSocketHelper.respond_to?(:broadcast_to_all)

          prefix = severity == :info ? '' : '⚠️ '
          payload = {
            'type' => 'system_info',
            'content' => "#{prefix}#{component}: #{message}"
          }.to_json
          ::WebSocketHelper.broadcast_to_all(payload)
        rescue StandardError
          # Reporting must never break the caller.
        end

        def ui_notification_due?(component)
          @mutex.synchronize do
            now = Time.now
            last = @last_notified[component]
            return false if last && (now - last) < DEDUP_TTL_SECONDS

            @last_notified[component] = now
            true
          end
        end
      end
    end
  end
end
