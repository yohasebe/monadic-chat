# frozen_string_literal: true

require_relative '../../../lib/monadic/agents/grok_code_agent'

module AutoForge
  module Agents
    class GrokCLIGenerator
      include Monadic::Agents::GrokCodeAgent

      def initialize(context)
        @context = context
        @app_instance = context[:app_instance]
        @codex_callback = context[:codex_callback]
      end

      def generate(prompt:, app_name: 'CLI Tool', &block)
        full_prompt = build_generation_prompt(prompt)

        result =
          if @codex_callback
            @codex_callback.call(full_prompt, app_name, &block)
          elsif @app_instance && @app_instance.respond_to?(:call_grok_code)
            @app_instance.call_grok_code(
              prompt: full_prompt,
              app_name: app_name,
              &block
            )
          else
            return { success: false, error: "No Grok-Code access available" }
          end

        # Process result (same format as HtmlGenerator)
        process_grok_response(result)
      end

      private

      def build_generation_prompt(base_prompt)
        # Optimized prompt for Grok-Code-Fast-1's iterative strengths
        <<~PROMPT
          You are an expert developer. Generate a complete command-line tool based on these requirements.

          #{base_prompt}

          OUTPUT INSTRUCTIONS:
          1. Output ONLY the script code - no explanations, no markdown
          2. Start with appropriate shebang (#!/usr/bin/env python3, #!/usr/bin/env ruby, etc.)
          3. Choose the most suitable language for the task
          4. Include comprehensive --help text using argparse/optparse/etc
          5. Add robust error handling and input validation
          6. Use standard library modules when possible
          7. All code and comments must be in English
          8. Make it cross-platform compatible when feasible

          CRITICAL RULES:
          - Implement ALL functionality completely - no placeholders
          - NO comments like "TODO" or "implement later"
          - ALL features must work exactly as specified
          - Use clear, readable code structure
          - Include actual working logic for all features

          Generate a COMPLETE, WORKING script with ALL logic fully implemented.
        PROMPT
      end

      def process_grok_response(response)
        return { success: false, error: "No response" } unless response

        # Handle different response formats
        if response.is_a?(Hash)
          # Already in correct format
          return response if response[:success] == false

          code = response[:code] || response['code'] || response[:content] || response['content']
        else
          # Raw string response
          code = response.to_s
        end

        # Clean the code
        code = extract_script_content(code)

        if code && code.strip.length > 0
          { success: true, code: code }
        else
          { success: false, error: "Failed to extract valid script code" }
        end
      end

      def extract_script_content(response)
        return nil unless response

        content = response.to_s.strip

        # Remove markdown code blocks if present
        content = content.gsub(/```(?:python|ruby|bash|javascript|sh|js|perl)?\n?/, '')
                        .gsub(/```\n?/, '')
                        .strip

        # Ensure it starts with shebang or is valid code
        if content.start_with?('#!') ||
           content.match?(/^(import |from |require |const |let |var |function |def |class )/m)
          content
        else
          # If no shebang, but looks like valid code, return it
          # The orchestrator will add appropriate shebang based on language detection
          content if content.length > 50 && content.include?("\n")
        end
      end
    end
  end
end
