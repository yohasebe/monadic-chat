# GPT-5-Codex Agent Module
# Shared functionality for calling GPT-5-Codex from various apps
#
# This module provides a common implementation for apps that need to
# delegate complex coding tasks to GPT-5-Codex via the Responses API.

module Monadic
  module Agents
    module GPT5CodexAgent
      # Check if the user has access to GPT-5-Codex model
      # @return [Boolean] true if GPT-5-Codex is available
      def has_gpt5_codex_access?
        return @gpt5_codex_access if defined?(@gpt5_codex_access)

        # GPT-5-Codex is available to all OpenAI API users
        # Simply check if OpenAI API key is configured
        api_key = CONFIG && CONFIG["OPENAI_API_KEY"]
        @gpt5_codex_access = !api_key.nil? && !api_key.to_s.strip.empty?

        if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "GPT-5-Codex access check: #{@gpt5_codex_access ? 'Available (API key present)' : 'Not available (no API key)'}"
        end

        @gpt5_codex_access
      end

      # Default timeout for GPT-5-Codex requests (in seconds)
      # Can be overridden by GPT5_CODEX_TIMEOUT environment variable
      # GPT-5-Codex can adapt reasoning time from seconds to hours for complex tasks
      # We set a practical limit of 15 minutes for interactive use
      GPT5_CODEX_DEFAULT_TIMEOUT = (ENV['GPT5_CODEX_TIMEOUT'] || 900).to_i  # 15 minutes default

      # Call GPT-5-Codex agent for complex coding tasks
      # @param prompt [String] The complete prompt to send to GPT-5-Codex
      # @param app_name [String] Name of the calling app for logging (optional)
      # @param timeout [Integer] Request timeout in seconds (optional)
      # @return [Hash] Response with :code, :success, :model, and optionally :error
      def call_gpt5_codex(prompt:, app_name: nil, timeout: nil)
        begin
          # Track timing for performance analysis
          start_time = Time.now

          # Set timeout value
          actual_timeout = timeout || GPT5_CODEX_DEFAULT_TIMEOUT

          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            app_label = app_name || self.class.name
            puts "[GPT5CodexAgent] ========== TIMING START =========="
            puts "[GPT5CodexAgent] Start time: #{start_time.strftime('%Y-%m-%d %H:%M:%S.%L')}"
            puts "[GPT5CodexAgent] App: #{app_label}"
            puts "[GPT5CodexAgent] Prompt length: #{prompt.length} chars"
            puts "[GPT5CodexAgent] Timeout: #{actual_timeout} seconds"
          end

          # Always show progress for GPT-5-Codex calls since they can take a while
          if app_name
            puts "[#{app_name}] 🤖 GPT-5-Codex is generating code..."
            puts "[#{app_name}]    Note: Complex tasks may take 5-15 minutes."
          end

          # Debug logging
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[GPT5CodexAgent] Starting call_gpt5_codex"
            puts "[GPT5CodexAgent] App: #{app_name}"
            puts "[GPT5CodexAgent] Self class: #{self.class}"
            puts "[GPT5CodexAgent] Responds to api_request: #{respond_to?(:api_request)}"
          end

          # Check if we have the necessary methods (from OpenAIHelper or compatible module)
          unless respond_to?(:api_request)
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[GPT5CodexAgent] ERROR: api_request not available"
              puts "[GPT5CodexAgent] Included modules: #{self.class.included_modules.map(&:name).join(', ')}"
            end
            return {
              error: "OpenAIHelper not available",
              success: false
            }
          end

          # Check if user has access to GPT-5-Codex
          unless has_gpt5_codex_access?
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[GPT5CodexAgent] ERROR: No GPT-5-Codex access"
              puts "[GPT5CodexAgent] API Key present: #{!CONFIG['OPENAI_API_KEY'].nil?}"
              puts "[GPT5CodexAgent] API Key length: #{CONFIG['OPENAI_API_KEY']&.length}"
            end
            # Provide user-friendly error message with fallback option
            error_message = build_access_error_message(app_name)
            return {
              error: error_message[:error],
              suggestion: error_message[:suggestion],
              fallback: error_message[:fallback],
              success: false
            }
          end

          # Create a proper session object for the API call using abstraction layer
          session = build_session(prompt: prompt, model: "gpt-5-codex")

          # Call api_request with timeout handling
          # Note: OpenAIHelper already sets 600s timeout for Responses API
          # This is additional application-level timeout handling
          results = nil

          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[GPT5CodexAgent] About to call api_request"
            puts "[GPT5CodexAgent] Timeout: #{actual_timeout}s"
          end

          begin
            require 'timeout'

            # Track API call timing
            api_start_time = Time.now if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

            Timeout::timeout(actual_timeout) do
              results = api_request("user", session, call_depth: 0)
            end

            # Log API call duration
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              api_end_time = Time.now
              api_duration = api_end_time - api_start_time
              puts "[GPT5CodexAgent] API call completed"
              puts "[GPT5CodexAgent] API duration: #{api_duration.round(2)} seconds"
              puts "[GPT5CodexAgent] End time: #{api_end_time.strftime('%Y-%m-%d %H:%M:%S.%L')}"
            end
          rescue Timeout::Error
            return {
              error: "GPT-5-Codex request timed out after #{actual_timeout} seconds",
              suggestion: "The task may be too complex. Try breaking it into smaller parts.",
              timeout: true,
              success: false
            }
          end

          # Parse the response
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[GPT5CodexAgent] API Response received"
            puts "[GPT5CodexAgent] Results class: #{results.class}"
            puts "[GPT5CodexAgent] Results: #{results.inspect[0..500]}"
          end

          if results && results.is_a?(Array) && results.first
            response = results.first

            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[GPT5CodexAgent] First response: #{response.class}"
              puts "[GPT5CodexAgent] Response keys: #{response.keys if response.is_a?(Hash)}"
            end

            # Check if response contains an error (from API)
            if response.is_a?(Hash) && (response["error"] || response[:error])
              error_msg = response["error"] || response[:error]
              if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
                puts "[GPT5CodexAgent] API returned error: #{error_msg}"
              end
              return {
                error: error_msg,
                success: false
              }
            end

            # Check if response is an API error string
            if response.is_a?(String) && response.include?("[OpenAI] API Error:")
              if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
                puts "[GPT5CodexAgent] API error string: #{response}"
              end
              return {
                error: response,
                success: false
              }
            end

            content = if response.is_a?(Hash)
                        response["content"] || response[:content] || response.dig("choices", 0, "message", "content")
                      else
                        response.to_s
                      end

            # Check if we actually got content
            if content.nil? || content.to_s.strip.empty?
              if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
                puts "[GPT5CodexAgent] Content is empty or nil"
              end
              return {
                error: "GPT-5-Codex returned empty response",
                success: false
              }
            end

            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[GPT5CodexAgent] Success! Content length: #{content.length}"
              total_time = Time.now - start_time
              puts "[GPT5CodexAgent] ========== TIMING END =========="
              puts "[GPT5CodexAgent] Total processing time: #{total_time.round(2)} seconds"
              puts "[GPT5CodexAgent] ================================"
            end

            {
              code: content,
              success: true,
              model: "gpt-5-codex"
            }
          else
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[GPT5CodexAgent] No valid response from API"
            end
            {
              error: "No response from GPT-5-Codex",
              success: false
            }
          end

        rescue StandardError => e
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[GPT5CodexAgent] EXCEPTION: #{e.class} - #{e.message}"
            puts "[GPT5CodexAgent] Backtrace: #{e.backtrace.first(5).join("\n")}"
          end
          {
            error: "Error calling GPT-5-Codex: #{e.message}",
            suggestion: "Try breaking the task into smaller pieces",
            success: false
          }
        end
      end

      # Build a minimal prompt for GPT-5-Codex following "less is more" principle
      # @param task [String] The main task description
      # @param options [Hash] Optional context to add to the prompt
      # @option options [String] :current_code Current code for debugging/refactoring
      # @option options [String] :error_context Error message to fix
      # @option options [String] :context Additional context
      # @option options [Array<Hash>] :files Array of file objects with :path and :content
      # @return [String] The built prompt
      def build_codex_prompt(task:, **options)
        prompt = task

        # Add current code context if debugging/refactoring
        if options[:current_code] && !options[:current_code].empty?
          prompt += "\n\nCurrent code:\n```\n#{options[:current_code]}\n```"
        end

        # Add error context if fixing issues
        if options[:error_context] && !options[:error_context].empty?
          prompt += "\n\nError to fix:\n#{options[:error_context]}"
        end

        # Add file context if provided (limited to avoid token overflow)
        if options[:files] && !options[:files].empty? && options[:files].is_a?(Array)
          prompt += "\n\nFiles to consider:\n"
          options[:files].take(3).each do |file|  # Limit to 3 files
            if file.is_a?(Hash) && file[:path] && file[:content]
              # Limit content to 1000 chars per file
              content_preview = file[:content].to_s[0..1000]
              prompt += "\n#{file[:path]}:\n```\n#{content_preview}\n```\n"
            end
          end
        end

        # Add general context if provided
        if options[:context] && !options[:context].empty?
          prompt += "\n\nContext: #{options[:context]}"
        end

        prompt
      end

      private

      # Get the message content field name that api_request expects
      # Current Monadic Chat uses "text" field internally
      # @return [Symbol] :text for current format
      def message_content_field
        # For now, Monadic Chat always uses "text" field
        # This method exists as a single point of change if the format changes
        #
        # If the format changes in the future, we could:
        # 1. Check method signatures of api_request
        # 2. Check for presence of specific methods
        # 3. Look for configuration flags
        #
        # But for now, keep it simple and explicit
        :text
      end

      # Build a session object compatible with api_request
      # This abstraction layer protects against internal API changes
      # @param prompt [String] The prompt to send
      # @param model [String] The model to use
      # @return [Hash] Session object for api_request
      def build_session(prompt:, model: "gpt-5-codex")
        # Get the field name for message content
        content_field = message_content_field.to_s

        # Build message with appropriate field name
        # Currently always "text" but abstracted for future changes
        message = {
          "role" => "user",
          content_field => prompt,
          "active" => true
        }

        messages = [message]

        # Validate message structure
        messages.each do |msg|
          unless msg["role"] && (msg["text"] || msg["content"])
            raise ArgumentError, "Invalid message structure: missing role or content field"
          end
        end

        # Build session with both legacy and new fields for compatibility
        {
          parameters: {
            "model" => model,
            "max_completion_tokens" => 128000
          },
          messages: messages
        }
      rescue StandardError => e
        # If message building fails, log and return a minimal valid structure
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "Warning: Message building failed: #{e.message}"
          puts "Using fallback message structure"
        end

        # Fallback to most basic structure
        {
          parameters: { "model" => model },
          messages: [{ "role" => "user", "text" => prompt.to_s, "active" => true }]
        }
      end

      # Build user-friendly error message for access denial
      # @param app_name [String] Name of the calling app
      # @return [Hash] Error message components
      def build_access_error_message(app_name = nil)
        app_label = app_name || "The application"

        # Detect user's language preference if possible
        # This is a simple implementation - could be enhanced
        {
          error: "GPT-5-Codex is not available in your OpenAI account",
          suggestion: "To use this advanced coding feature, you need access to GPT-5-Codex. " \
                     "This is a specialized model that may require a specific subscription tier. " \
                     "Please check your OpenAI account settings or contact OpenAI support.",
          fallback: "#{app_label} will use the main GPT-5 model instead. " \
                   "While it can handle many coding tasks, GPT-5-Codex would provide " \
                   "more specialized code generation capabilities."
        }
      end
    end
  end
end