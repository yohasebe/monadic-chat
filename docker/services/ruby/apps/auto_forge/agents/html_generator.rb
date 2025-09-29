# frozen_string_literal: true

require 'json'

module AutoForge
  module Agents
    class HtmlGenerator
      def initialize(context)
        @context = context || {}
      end

      def generate(prompt, existing_content: nil, file_name: 'index.html', &block)
        start_time = Time.now
        puts "[HTMLGenerator] Starting generation at #{start_time.strftime('%Y-%m-%d %H:%M:%S')}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

        agent = (@context[:agent] || :openai).to_sym

        # Select appropriate code generation interface
        codex_caller = nil

        if agent == :claude
          if @context[:app_instance] && @context[:app_instance].respond_to?(:claude_opus_agent)
            puts "[HTMLGenerator] Using app_instance for Claude Opus" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            codex_caller = @context[:app_instance]
          elsif @context[:codex_callback] && @context[:codex_callback].respond_to?(:call)
            puts "[HTMLGenerator] Using codex_callback for Claude Opus" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            codex_caller = @context[:codex_callback]
          end
        else
          if @context[:app_instance] && @context[:app_instance].respond_to?(:call_gpt5_codex)
            puts "[HTMLGenerator] Using app_instance for GPT-5-Codex" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            codex_caller = @context[:app_instance]
          elsif @context[:codex_callback] && @context[:codex_callback].respond_to?(:call)
            puts "[HTMLGenerator] Using codex_callback for GPT-5-Codex" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            codex_caller = @context[:codex_callback]
          end
        end

        if codex_caller
          # Build appropriate prompt
          full_prompt = build_prompt(prompt, existing_content)
          agent_name = agent == :claude ? 'Claude Opus' : 'GPT-5-Codex'
          puts "[HTMLGenerator] Calling #{agent_name} with prompt length: #{full_prompt.length}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

          result =
            if agent == :claude
              if codex_caller.respond_to?(:claude_opus_agent)
                codex_caller.claude_opus_agent(full_prompt, 'ClaudeOpusAgent', &block)
              else
                codex_caller.call(full_prompt, 'ClaudeOpusAgent', &block)
              end
            else
              if codex_caller.respond_to?(:call_gpt5_codex)
                codex_caller.call_gpt5_codex(
                  prompt: full_prompt,
                  app_name: 'AutoForgeOpenAI',
                  &block
                )
              else
                codex_caller.call(full_prompt, 'AutoForgeOpenAI', &block)
              end
            end

          end_time = Time.now
          duration = end_time - start_time
          puts "[HTMLGenerator] #{agent_name} returned at #{end_time.strftime('%Y-%m-%d %H:%M:%S')}" if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "[HTMLGenerator] Generation took #{duration.round(2)} seconds" if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "[HTMLGenerator] #{agent_name} result: #{result.inspect[0..500]}" if CONFIG && CONFIG["EXTRA_LOGGING"]

          if result && result[:success]
            code = result[:code]
            puts "[HTMLGenerator] Got code, length: #{code.length}" if CONFIG && CONFIG["EXTRA_LOGGING"]

            # Check if it's a patch
            if existing_content && code.match?(/^(---|diff|@@|\+|\-)/m)
              puts "[HTMLGenerator] Returning patch" if CONFIG && CONFIG["EXTRA_LOGGING"]
              return { mode: :patch, patch: code }
            end

            # Extract HTML if wrapped in markdown
            html = extract_html_content(code)
            if html
              puts "[HTMLGenerator] Extracted HTML from markdown, length: #{html.length}" if CONFIG && CONFIG["EXTRA_LOGGING"]
              return { mode: :full, content: html }
            else
              puts "[HTMLGenerator] Using raw code as HTML, length: #{code.length}" if CONFIG && CONFIG["EXTRA_LOGGING"]
              return { mode: :full, content: code }
            end
          else
            puts "[HTMLGenerator] Failed - result: #{result.inspect}" if CONFIG && CONFIG["EXTRA_LOGGING"]
            # Return detailed error information instead of nil
            error_msg = if result && result[:error]
              result[:error]
            elsif result && result[:timeout]
              "GPT-5-Codex request timed out. The task may be too complex."
            else
              agent == :claude ? "Claude Opus generation failed" : "GPT-5-Codex generation failed"
            end
            return { mode: :error, error: error_msg, details: result }
          end
        else
          if CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[HTMLGenerator] No suitable code generation method available"
            puts "[HTMLGenerator] agent: #{agent}, app_instance: #{@context[:app_instance].class if @context[:app_instance]}"
          end
          error_msg = agent == :claude ? "Claude Opus integration not available" : "GPT-5-Codex integration not available"
          return { mode: :error, error: error_msg, details: nil }
        end
      end

      private

      def build_prompt(base_prompt, existing_content)
        if existing_content && !existing_content.to_s.strip.empty?
          <<~PROMPT
            You are an expert web developer. Please modify the following HTML file according to the requirements.

            Current HTML file:
            ```html
            #{existing_content}
            ```

            Requirements:
            #{base_prompt}

            Generate the complete updated HTML file or a unified diff patch. Output only code, no explanations.
          PROMPT
        else
          <<~PROMPT
            You are an expert web developer. Generate a complete, self-contained HTML file based on these requirements.

            Requirements:
            #{base_prompt}

            CRITICAL INSTRUCTIONS:
            1. Output ONLY the HTML code - no explanations or markdown
            2. Start with <!DOCTYPE html> and end with </html>
            3. Include all CSS in <style> tags within <head>
            4. Include all JavaScript in <script> tags before </body>
            5. DO NOT use external dependencies - everything must be self-contained
            6. Implement ALL functionality described - the app must be fully functional
            7. Include actual working logic, not just UI elements
            8. If algorithms or calculations are needed, implement them completely
            9. Ensure all interactive features work correctly
            10. Test that the code actually performs the described functions

            ABSOLUTELY FORBIDDEN:
            - DO NOT write comments like "// Dummy implementation" or "// This is simplified"
            - DO NOT use placeholder logic or stub functions
            - DO NOT leave any functionality unimplemented
            - Every feature described MUST work exactly as specified

            Generate a COMPLETE, WORKING application with ALL algorithms and logic fully implemented.
          PROMPT
        end
      end

      def extract_html_content(response)
        return nil unless response

        content = response.to_s

        # Remove markdown code blocks if present
        content = content.gsub(/```html?\n?/, '').gsub(/```\n?/, '').strip

        # Try to extract complete HTML document
        if content.match?(/<!DOCTYPE/i)
          match = content.match(/<!DOCTYPE.*?<\/html>/mi)
          return match[0] if match
        end

        # Return if it looks like HTML
        return content if content.match?(/<html/i) && content.match?(/<\/html>/i)

        # If content starts with HTML-like tags, assume it's HTML
        return content if content.match?(/^\s*</)

        # Otherwise return nil
        nil
      end
    end
  end
end
