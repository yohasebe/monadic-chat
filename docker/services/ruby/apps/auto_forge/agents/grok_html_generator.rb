# frozen_string_literal: true

require 'json'

module AutoForge
  module Agents
    class GrokHtmlGenerator
      def initialize(context)
        @context = context || {}
      end

      def generate(prompt, existing_content: nil, file_name: 'index.html', &block)
        start_time = Time.now
        puts "[GrokHTMLGenerator] Starting generation at #{start_time.strftime('%Y-%m-%d %H:%M:%S')}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

        # Get Grok code generator
        codex_caller = nil

        if @context[:app_instance] && @context[:app_instance].respond_to?(:call_grok_code)
          puts "[GrokHTMLGenerator] Using app_instance for Grok-Code" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
          codex_caller = @context[:app_instance]
        elsif @context[:codex_callback] && @context[:codex_callback].respond_to?(:call)
          puts "[GrokHTMLGenerator] Using codex_callback for Grok-Code" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
          codex_caller = @context[:codex_callback]
        end

        if codex_caller
          # Build optimized prompt for Grok-Code-Fast-1
          full_prompt = build_prompt(prompt, existing_content)
          puts "[GrokHTMLGenerator] Calling Grok-Code with prompt length: #{full_prompt.length}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

          result =
            if codex_caller.respond_to?(:call_grok_code)
              codex_caller.call_grok_code(
                prompt: full_prompt,
                app_name: 'AutoForgeGrok',
                &block
              )
            else
              codex_caller.call(full_prompt, 'AutoForgeGrok', &block)
            end

          end_time = Time.now
          duration = end_time - start_time
          puts "[GrokHTMLGenerator] Grok-Code returned at #{end_time.strftime('%Y-%m-%d %H:%M:%S')}" if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "[GrokHTMLGenerator] Generation took #{duration.round(2)} seconds" if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "[GrokHTMLGenerator] Grok-Code result: #{result.inspect[0..500]}" if CONFIG && CONFIG["EXTRA_LOGGING"]

          if result && result[:success]
            code = result[:code]
            puts "[GrokHTMLGenerator] Got code, length: #{code.length}" if CONFIG && CONFIG["EXTRA_LOGGING"]

            # Check if it's a patch
            if existing_content && code.match?(/^(---|diff|@@|\+|\-)/m)
              puts "[GrokHTMLGenerator] Returning patch" if CONFIG && CONFIG["EXTRA_LOGGING"]
              return { mode: :patch, patch: code }
            end

            # Extract HTML if wrapped in markdown
            html = extract_html_content(code)
            if html
              puts "[GrokHTMLGenerator] Extracted HTML from markdown, length: #{html.length}" if CONFIG && CONFIG["EXTRA_LOGGING"]
              return { mode: :full, content: html }
            else
              puts "[GrokHTMLGenerator] Using raw code as HTML, length: #{code.length}" if CONFIG && CONFIG["EXTRA_LOGGING"]
              return { mode: :full, content: code }
            end
          else
            puts "[GrokHTMLGenerator] Failed - result: #{result.inspect}" if CONFIG && CONFIG["EXTRA_LOGGING"]
            # Return detailed error information
            error_msg = if result && result[:error]
              result[:error]
            elsif result && result[:timeout]
              "Grok-Code request timed out. The task may be too complex. Try breaking it into smaller parts."
            else
              "Grok-Code generation failed"
            end
            return { mode: :error, error: error_msg, details: result }
          end
        else
          if CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[GrokHTMLGenerator] No suitable code generation method available"
            puts "[GrokHTMLGenerator] app_instance: #{@context[:app_instance].class if @context[:app_instance]}"
          end
          return { mode: :error, error: "Grok-Code integration not available", details: nil }
        end
      end

      private

      def build_prompt(base_prompt, existing_content)
        if existing_content && !existing_content.to_s.strip.empty?
          # Modification task - keep it focused
          <<~PROMPT
            You are an expert web developer. Modify the following HTML file according to the requirements.

            Current HTML file:
            ```html
            #{existing_content}
            ```

            Requirements:
            #{base_prompt}

            Generate the complete updated HTML file or a unified diff patch. Output only code, no explanations.
          PROMPT
        else
          # New file generation - optimized for Grok-Code-Fast-1's strengths
          <<~PROMPT
            You are an expert web developer. Generate a complete, self-contained HTML file.

            Requirements:
            #{base_prompt}

            OUTPUT INSTRUCTIONS:
            1. Output ONLY the HTML code - no explanations, no markdown
            2. Start with <!DOCTYPE html> and end with </html>
            3. Include all CSS in <style> tags within <head>
            4. Include all JavaScript in <script> tags before </body>
            5. Use vanilla JavaScript - no external libraries unless specified
            6. Implement ALL functionality completely - every feature must work
            7. Use modern CSS (Grid, Flexbox, CSS variables)
            8. Make it responsive and accessible

            CRITICAL RULES:
            - NO placeholder functions or dummy implementations
            - NO comments like "TODO" or "implement later"
            - ALL algorithms must be fully implemented
            - ALL interactive features must work correctly
            - Test that the code performs exactly as specified

            Generate a COMPLETE, WORKING application with ALL logic fully implemented.
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
