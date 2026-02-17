# frozen_string_literal: true

module Monadic
  module Utils
    module StepProgress
      # Build and send a step_progress fragment via block or WebSocketHelper.
      #
      # @param source  [String]  Agent name shown on the client (e.g. "OpenAICodeAgent")
      # @param steps   [Array<String>]  Ordered list of human-readable step labels
      # @param current [Integer] 0-based index of the step currently in progress
      # @param mode    [String]  "sequential" or "parallel"
      # @param ws_session_id [String, nil] WebSocket session for targeted delivery
      # @param block   [Proc, nil]  If given, the fragment is yielded instead of sent via WebSocketHelper
      def send_step_progress(source:, steps:, current:, mode: "sequential",
                             ws_session_id: nil, &block)
        fragment = {
          "type" => "wait",
          "content" => steps[current] || "Processing...",
          "source" => source,
          "step_progress" => {
            "mode" => mode,
            "current" => current,
            "total" => steps.length,
            "steps" => steps
          }
        }

        if block
          block.call(fragment)
        elsif defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_progress_fragment)
          WebSocketHelper.send_progress_fragment(fragment, ws_session_id)
        end
      rescue StandardError
        # Progress is best-effort; never fail the caller
      end
    end
  end
end
