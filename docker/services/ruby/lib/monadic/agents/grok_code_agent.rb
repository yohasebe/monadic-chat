# Grok-Code Agent Module
# Shared functionality for calling Grok-Code-Fast-1 from various apps
#
# This module provides a common implementation for apps that need to
# delegate complex coding tasks to Grok-Code-Fast-1 via the xAI API.

module Monadic
  module Agents
    module GrokCodeAgent
      # Check if the user has access to Grok-Code model
      # @return [Boolean] true if Grok-Code is available
      def has_grok_code_access?
        return @grok_code_access if defined?(@grok_code_access)

        # Grok-Code is available to all xAI API users
        # Simply check if xAI API key is configured
        api_key = CONFIG && CONFIG["XAI_API_KEY"]
        @grok_code_access = !api_key.nil? && !api_key.to_s.strip.empty?

        if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "Grok-Code access check: #{@grok_code_access ? 'Available (API key present)' : 'Not available (no API key)'}"
        end

        @grok_code_access
      end

      # Default timeout for Grok-Code requests (in seconds)
      # Can be overridden by GROK_CODE_TIMEOUT environment variable
      GROK_CODE_DEFAULT_TIMEOUT = (ENV['GROK_CODE_TIMEOUT'] || 300).to_i  # 5 minutes default

      # Call Grok-Code agent for complex coding tasks
      # @param prompt [String] The complete prompt to send to Grok-Code
      # @param app_name [String] Name of the calling app for logging (optional)
      # @param timeout [Integer] Request timeout in seconds (optional)
      # @return [Hash] Response with :code, :success, :model, and optionally :error
      def call_grok_code(prompt:, app_name: nil, timeout: nil)
        begin
          # Set timeout value
          actual_timeout = timeout || GROK_CODE_DEFAULT_TIMEOUT

          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            app_label = app_name || self.class.name
            puts "#{app_label}: Calling Grok-Code agent"
            puts "Prompt length: #{prompt.length} chars"
            puts "Timeout: #{actual_timeout} seconds"
          end

          # Check if we have the necessary methods (from GrokHelper or compatible module)
          unless respond_to?(:api_request)
            return {
              error: "GrokHelper not available",
              success: false
            }
          end

          # Check if user has access to Grok-Code
          unless has_grok_code_access?
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
          session = build_session(prompt: prompt, model: "grok-code-fast-1")

          # Call api_request with timeout handling
          results = nil
          begin
            require 'timeout'
            Timeout::timeout(actual_timeout) do
              results = api_request("user", session, call_depth: 0)
            end
          rescue Timeout::Error
            return {
              error: "Grok-Code request timed out after #{actual_timeout} seconds",
              suggestion: "The task may be too complex. Try breaking it into smaller parts.",
              timeout: true,
              success: false
            }
          end

          # Parse the response
          if results && results.is_a?(Array) && results.first
            response = results.first

            # Check if response contains an error (from API)
            if response.is_a?(Hash) && (response["error"] || response[:error])
              error_msg = response["error"] || response[:error]
              return {
                error: error_msg,
                success: false
              }
            end

            # Check if response is an API error string
            if response.is_a?(String) && response.include?("[xAI] API Error:")
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
              return {
                error: "Grok-Code returned empty response",
                success: false
              }
            end

            {
              code: content,
              success: true,
              model: "grok-code-fast-1"
            }
          else
            {
              error: "No response from Grok-Code",
              success: false
            }
          end

        rescue StandardError => e
          {
            error: "Error calling Grok-Code: #{e.message}",
            suggestion: "Try breaking the task into smaller pieces",
            success: false
          }
        end
      end

      # Build a minimal prompt for Grok-Code following "less is more" principle
      # @param task [String] The main task description
      # @param options [Hash] Optional context to add to the prompt
      # @option options [String] :current_code Current code for debugging/refactoring
      # @option options [String] :error_context Error message to fix
      # @option options [String] :context Additional context
      # @option options [Array<Hash>] :files Array of file objects with :path and :content
      # @return [String] The built prompt
      def build_grok_code_prompt(task:, **options)
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
        :text
      end

      # Build a session object compatible with api_request
      # This abstraction layer protects against internal API changes
      # @param prompt [String] The prompt to send
      # @param model [String] The model to use
      # @return [Hash] Session object for api_request
      def build_session(prompt:, model: "grok-code-fast-1")
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
            "max_tokens" => 32768,
            "temperature" => 0.0
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

        {
          error: "Grok-Code-Fast-1 is not available in your xAI account",
          suggestion: "To use this advanced coding feature, you need an xAI API key. " \
                     "Please check your xAI account settings or contact xAI support.",
          fallback: "#{app_label} will use the main Grok model instead. " \
                   "While it can handle many coding tasks, Grok-Code-Fast-1 would provide " \
                   "more specialized code generation capabilities."
        }
      end
    end
  end
end