# frozen_string_literal: true

require_relative '../adapters/vendors/claude_helper'

module Monadic
  module Agents
    module ClaudeOpusAgent
      include ClaudeHelper

      CLAUDE_MODEL = 'claude-opus-4-1-20250805'.freeze

      def claude_opus_agent(prompt, app_name = 'ClaudeOpusAgent', max_tokens: 8000, temperature: 0.3, reasoning_effort: 'medium', &block)
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
