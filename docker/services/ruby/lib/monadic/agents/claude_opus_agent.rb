# frozen_string_literal: true

module Monadic
  module Agents
    module ClaudeOpusAgent
      CLAUDE_MODEL = 'claude-sonnet-4-5-20250929'.freeze

      def claude_opus_agent(prompt, app_name = 'ClaudeOpusAgent', max_tokens: 8000, temperature: 0.3, reasoning_effort: 'medium', &block)
        # Check if we have the necessary methods (from ClaudeHelper or compatible module)
        unless respond_to?(:send_query)
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[ClaudeOpusAgent] ERROR: send_query not available"
            puts "[ClaudeOpusAgent] Included modules: #{self.class.included_modules.map(&:name).join(', ')}"
          end
          return {
            error: "ClaudeHelper not available",
            success: false
          }
        end

        progress_payload = {
          'type' => 'wait',
          'content' => 'Claude Opus is generating code…',
          'source' => 'ClaudeOpusAgent',
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
          { success: false, error: 'Claude Opus returned empty content' }
        else
          { success: true, code: code }
        end
      rescue => e
        { success: false, error: "Claude Opus generation failed: #{e.message}" }
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
