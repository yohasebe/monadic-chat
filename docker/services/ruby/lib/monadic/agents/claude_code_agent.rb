# frozen_string_literal: true

module Monadic
  module Agents
    module ClaudeCodeAgent
      CLAUDE_MODEL = 'claude-sonnet-4-5-20250929'.freeze

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

        progress_payload = {
          'type' => 'wait',
          'content' => 'Claude Code is generating code…',
          'source' => 'ClaudeCodeAgent',
          'minutes' => 0
        }
        block.call(progress_payload) if block

        parameters = {
          model: CLAUDE_MODEL,
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

        response = send_query(parameters, model: CLAUDE_MODEL)

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
      end

      private

      def normalize_response(response)
        content = response.to_s.strip
        return nil if content.empty?

        content = content.gsub(/```\w*\n?/, '').gsub(/```\s*$/, '').strip
        content
      end
    end
  end
end
