# frozen_string_literal: true

require_relative "../utils/step_progress"

module Monadic
  module Agents
    module ClaudeCodeAgent
      include Monadic::Utils::StepProgress

      # Resolve default Claude code model via providerDefaults SSOT
      def self.default_model
        Monadic::Utils::ModelSpec.default_code_model("anthropic")
      end

      CLAUDE_CODE_STEPS = [
        "Analyzing requirements",
        "Generating code",
        "Finalizing"
      ].freeze

      # Keyword argument interface matching GPT5CodexAgent pattern
      def call_claude_code(prompt:, app_name: 'ClaudeCodeAgent', max_tokens: 8000, temperature: 0.3, reasoning_effort: 'medium', &block)
        claude_code_agent(prompt, app_name, max_tokens: max_tokens, temperature: temperature, reasoning_effort: reasoning_effort, &block)
      end

      # Build prompt from structured parameters (matching GPT5CodexAgent pattern)
      def build_claude_code_prompt(task:, context: nil, files: nil)
        prompt_parts = []
        prompt_parts << "Task: #{task}"
        prompt_parts << "Context: #{context}" if context && !context.empty?

        if files && files.is_a?(Array) && !files.empty?
          prompt_parts << "\nFiles:"
          files.each do |file|
            path = file["path"] || file[:path]
            content = file["content"] || file[:content]
            prompt_parts << "\n--- #{path} ---\n#{content}\n" if path && content
          end
        end

        prompt_parts.join("\n\n")
      end

      def claude_code_agent(prompt, app_name = 'ClaudeCodeAgent', max_tokens: 8000, temperature: 0.3, reasoning_effort: 'medium', &block)
        # Check if we have the necessary methods (from ClaudeHelper or compatible module)
        unless respond_to?(:send_query)
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[ClaudeCodeAgent] ERROR: send_query not available"
            puts "[ClaudeCodeAgent] Included modules: #{self.class.included_modules.map(&:name).join(', ')}"
          end
          return {
            error: "ClaudeHelper not available",
            success: false
          }
        end

        # Send initial step_progress (step 0 = Analyzing)
        initial_fragment = {
          "type" => "wait",
          "content" => CLAUDE_CODE_STEPS[0],
          "source" => "ClaudeCodeAgent",
          "minutes" => 0,
          "step_progress" => {
            "mode" => "sequential",
            "current" => 0,
            "total" => CLAUDE_CODE_STEPS.length,
            "steps" => CLAUDE_CODE_STEPS
          }
        }
        block.call(initial_fragment) if block

        # Start progress thread for continuous updates
        parent_session_id = Thread.current[:websocket_session_id]
        progress_thread = start_claude_progress_thread(parent_session_id, &block)

        parameters = {
          model: Monadic::Agents::ClaudeCodeAgent.default_model,
          messages: [
            {
              'role' => 'user',
              'content' => prompt
            }
          ],
          max_tokens: max_tokens,
          temperature: temperature,
          reasoning_effort: reasoning_effort
        }

        response = send_query(parameters, model: Monadic::Agents::ClaudeCodeAgent.default_model)

        if response.is_a?(Hash) && response[:error]
          return { success: false, error: response[:error] }
        end

        code = normalize_response(response)

        if code.nil? || code.strip.empty?
          { success: false, error: 'Claude Code returned empty content' }
        else
          { success: true, code: code }
        end
      rescue => e
        { success: false, error: "Claude Code generation failed: #{e.message}" }
      ensure
        cleanup_claude_progress_thread(progress_thread)
      end

      private

      def normalize_response(response)
        content = response.to_s.strip
        return nil if content.empty?

        content = content.gsub(/```\w*\n?/, '').gsub(/```\s*$/, '').strip
        content
      end

      # Progress thread that advances through steps at 40-second intervals
      def start_claude_progress_thread(session_id, &block)
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            start_time = Time.now
            last_step = 0

            while !Thread.current[:should_stop]
              80.times do  # 40 seconds (80 * 0.5s)
                sleep 0.5
                break if Thread.current[:should_stop]
              end
              break if Thread.current[:should_stop]

              elapsed = Time.now - start_time
              step_index = [(elapsed / 40).floor, CLAUDE_CODE_STEPS.length - 1].min
              next if step_index == last_step

              last_step = step_index
              fragment = {
                "type" => "wait",
                "content" => CLAUDE_CODE_STEPS[step_index],
                "source" => "ClaudeCodeAgent",
                "minutes" => (elapsed / 60).floor,
                "step_progress" => {
                  "mode" => "sequential",
                  "current" => step_index,
                  "total" => CLAUDE_CODE_STEPS.length,
                  "steps" => CLAUDE_CODE_STEPS
                }
              }

              if block
                block.call(fragment)
              elsif defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_progress_fragment)
                WebSocketHelper.send_progress_fragment(fragment, session_id)
              end
            end
          rescue StandardError
            # Progress is best-effort
          end
        end
      end

      def cleanup_claude_progress_thread(thread)
        return unless thread

        begin
          thread[:should_stop] = true
          thread.join(1.0)
          thread.kill if thread.alive?
        rescue StandardError
          # Silent cleanup
        end
      end
    end
  end
end
