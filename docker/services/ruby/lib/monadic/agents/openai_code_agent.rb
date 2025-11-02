# OpenAI Code Agent Module
# Shared functionality for calling OpenAI Code from various apps
#
# This module provides a common implementation for apps that need to
# delegate complex coding tasks to OpenAI Code via the Responses API.

module Monadic
  module Agents
    module OpenAICodeAgent
      # Check if the user has access to OpenAI Code model
      # @return [Boolean] true if OpenAI Code is available
      def has_openai_code_access?
        return @openai_code_access if defined?(@openai_code_access)

        # OpenAI Code is available to all OpenAI API users
        # Simply check if OpenAI API key is configured
        api_key = CONFIG && CONFIG["OPENAI_API_KEY"]
        @openai_code_access = !api_key.nil? && !api_key.to_s.strip.empty?

        if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "OpenAI Code access check: #{@openai_code_access ? 'Available (API key present)' : 'Not available (no API key)'}"
        end

        @openai_code_access
      end

      # Default timeout for OpenAI Code requests (in seconds)
      # Can be overridden by OPENAI_CODE_TIMEOUT environment variable
      # OpenAI Code can adapt reasoning time from seconds to hours for complex tasks
      # We set a practical limit of 20 minutes for interactive use
      OPENAI_CODE_DEFAULT_TIMEOUT = (ENV['OPENAI_CODE_TIMEOUT'] || 1200).to_i  # 20 minutes default

      # Call OpenAI Code agent for complex coding tasks
      # @param prompt [String] The complete prompt to send to OpenAI Code
      # @param app_name [String] Name of the calling app for logging (optional)
      # @param timeout [Integer] Request timeout in seconds (optional)
      # @param model [String] Model to use (optional, defaults to MDSL config or "openai-code")
      # @param block [Proc] Block to call with progress updates (optional)
      # @return [Hash] Response with :code, :success, :model, and optionally :error
      def call_openai_code(prompt:, app_name: nil, timeout: nil, model: nil, &block)
        begin
          # Track timing for performance analysis
          start_time = Time.now

          # Set timeout value with guard
          actual_timeout = timeout || OPENAI_CODE_DEFAULT_TIMEOUT
          actual_timeout = OPENAI_CODE_DEFAULT_TIMEOUT unless actual_timeout.is_a?(Integer) && actual_timeout > 0

          # Initialize progress thread variable at proper scope
          progress_thread = nil

          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            app_label = app_name || self.class.name
            puts "[OpenAICodeAgent] ========== TIMING START =========="
            puts "[OpenAICodeAgent] Start time: #{start_time.strftime('%Y-%m-%d %H:%M:%S.%L')}"
            puts "[OpenAICodeAgent] App: #{app_label}"
            puts "[OpenAICodeAgent] Prompt length: #{prompt.length} chars"
            puts "[OpenAICodeAgent] Timeout: #{actual_timeout} seconds"
          end

          # Always show progress for OpenAI Code calls since they can take a while
          if app_name
            puts "[#{app_name}] 🤖 OpenAI Code is generating code..."
            puts "[#{app_name}]    Note: Complex tasks may take 5-20 minutes."
          end

          # Start progress thread if block given and timeout is long enough
          progress_enabled = !CONFIG || CONFIG["OPENAI_CODE_PROGRESS_ENABLED"] != false  # Default true
          progress_interval = (CONFIG && CONFIG["OPENAI_CODE_PROGRESS_INTERVAL"] || 60).to_i
          progress_interval = 60 unless progress_interval > 0  # Guard against invalid values

          if block_given? && actual_timeout > 120 && progress_enabled
            progress_thread = start_progress_thread(
              actual_timeout: actual_timeout,
              interval: progress_interval,
              app_name: app_name,
              &block
            )
          end

          # Debug logging
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[OpenAICodeAgent] Starting call_openai_code"
            puts "[OpenAICodeAgent] App: #{app_name}"
            puts "[OpenAICodeAgent] Self class: #{self.class}"
            puts "[OpenAICodeAgent] Responds to api_request: #{respond_to?(:api_request)}"
          end

          # Check if we have the necessary methods (from OpenAIHelper or compatible module)
          unless respond_to?(:api_request)
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[OpenAICodeAgent] ERROR: api_request not available"
              puts "[OpenAICodeAgent] Included modules: #{self.class.included_modules.map(&:name).join(', ')}"
            end
            return {
              error: "OpenAIHelper not available",
              success: false
            }
          end

          # Check if user has access to OpenAI Code
          unless has_openai_code_access?
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[OpenAICodeAgent] ERROR: No OpenAI Code access"
              puts "[OpenAICodeAgent] API Key present: #{!CONFIG['OPENAI_API_KEY'].nil?}"
              puts "[OpenAICodeAgent] API Key length: #{CONFIG['OPENAI_API_KEY']&.length}"
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

          # Determine model to use with priority: argument > MDSL config > env var > default
          actual_model = model ||
                         @context&.dig(:agents, :code_generator) ||
                         ENV['OPENAI_CODE_MODEL'] ||
                         "openai-code"

          # Log model selection for debugging
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[OpenAICodeAgent] Using model: #{actual_model}"
          end

          # Create a proper session object for the API call using abstraction layer
          session = build_session(prompt: prompt, model: actual_model)

          # Call api_request with timeout handling
          # Note: OpenAIHelper already sets 600s timeout for Responses API
          # This is additional application-level timeout handling
          results = nil

          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[OpenAICodeAgent] About to call api_request"
            puts "[OpenAICodeAgent] Timeout: #{actual_timeout}s"
          end

          begin
            require 'timeout'

            # Track API call timing
            api_start_time = Time.now if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

            Timeout::timeout(actual_timeout) do
              results = api_request("user", session, call_depth: 0, &block)
            end

            # Log API call duration
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              api_end_time = Time.now
              api_duration = api_end_time - api_start_time
              puts "[OpenAICodeAgent] API call completed"
              puts "[OpenAICodeAgent] API duration: #{api_duration.round(2)} seconds"
              puts "[OpenAICodeAgent] End time: #{api_end_time.strftime('%Y-%m-%d %H:%M:%S.%L')}"
            end
          rescue Timeout::Error
            return {
              error: "OpenAI Code request timed out after #{actual_timeout} seconds",
              suggestion: "The task may be too complex. Try breaking it into smaller parts.",
              timeout: true,
              success: false
            }
          ensure
            # Always clean up thread if it exists
            cleanup_progress_thread(progress_thread)
          end

          # Parse the response
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[OpenAICodeAgent] API Response received"
            puts "[OpenAICodeAgent] Results class: #{results.class}"
            puts "[OpenAICodeAgent] Results: #{results.inspect[0..500]}"
          end

          if results && results.is_a?(Array) && results.first
            response = results.first

            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[OpenAICodeAgent] First response: #{response.class}"
              puts "[OpenAICodeAgent] Response keys: #{response.keys if response.is_a?(Hash)}"
            end

            # Check if response contains an error (from API)
            if response.is_a?(Hash) && (response["error"] || response[:error])
              error_msg = response["error"] || response[:error]
              if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
                puts "[OpenAICodeAgent] API returned error: #{error_msg}"
              end
              return {
                error: error_msg,
                success: false
              }
            end

            # Check if response is an API error string
            if response.is_a?(String) && response.include?("[OpenAI] API Error:")
              if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
                puts "[OpenAICodeAgent] API error string: #{response}"
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
                puts "[OpenAICodeAgent] Content is empty or nil"
              end
              return {
                error: "OpenAI Code returned empty response",
                success: false
              }
            end

            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[OpenAICodeAgent] Success! Content length: #{content.length}"
              total_time = Time.now - start_time
              puts "[OpenAICodeAgent] ========== TIMING END =========="
              puts "[OpenAICodeAgent] Total processing time: #{total_time.round(2)} seconds"
              puts "[OpenAICodeAgent] ================================"
            end

            {
              code: content,
              success: true,
              model: actual_model
            }
          else
            if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
              puts "[OpenAICodeAgent] No valid response from API"
            end
            {
              error: "No response from OpenAI Code",
              success: false
            }
          end

        rescue StandardError => e
          # Ensure thread cleanup even on exceptions
          cleanup_progress_thread(progress_thread) if progress_thread

          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[OpenAICodeAgent] EXCEPTION: #{e.class} - #{e.message}"
            puts "[OpenAICodeAgent] Backtrace: #{e.backtrace.first(5).join("\n")}"
          end
          {
            error: "Error calling OpenAI Code: #{e.message}",
            suggestion: "Try breaking the task into smaller pieces",
            success: false
          }
        end
      end

      # Build a minimal prompt for OpenAI Code following "less is more" principle
      # @param task [String] The main task description
      # @param options [Hash] Optional context to add to the prompt
      # @option options [String] :current_code Current code for debugging/refactoring
      # @option options [String] :error_context Error message to fix
      # @option options [String] :context Additional context
      # @option options [Array<Hash>] :files Array of file objects with :path and :content
      # @return [String] The built prompt
      def build_openai_code_prompt(task:, **options)
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
      def build_session(prompt:, model: "openai-code")
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
            "max_completion_tokens" => 128000,
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

        # Detect user's language preference if possible
        # This is a simple implementation - could be enhanced
        {
          error: "OpenAI Code is not available in your OpenAI account",
          suggestion: "To use this advanced coding feature, you need access to OpenAI Code. " \
                     "This is a specialized model that may require a specific subscription tier. " \
                     "Please check your OpenAI account settings or contact OpenAI support.",
          fallback: "#{app_label} will use the main GPT-5 model instead. " \
                   "While it can handle many coding tasks, OpenAI Code would provide " \
                   "more specialized code generation capabilities."
        }
      end

      # Start progress monitoring thread
      # @param actual_timeout [Integer] Total timeout for the operation
      # @param interval [Integer] Update interval in seconds
      # @param app_name [String] Application name for logging
      # @param block [Proc] Block to call with progress updates
      # @return [Thread] The progress monitoring thread
      def start_progress_thread(actual_timeout:, interval:, app_name:, &block)
        # Get session ID from parent thread BEFORE creating new thread
        parent_session_id = Thread.current[:websocket_session_id]

        Thread.new do
          Thread.current.report_on_exception = false
          Thread.current[:app_name] = app_name

          begin
            # Use session ID from parent thread
            session_id = parent_session_id

            start_time = Time.now
            last_update = start_time

            while !Thread.current[:should_stop]
              # Sleep in small increments for responsive shutdown
              (interval * 2).times do
                sleep 0.5
                break if Thread.current[:should_stop]
              end

              break if Thread.current[:should_stop]

              elapsed = Time.now - start_time
              since_last = Time.now - last_update

              if since_last >= interval
                begin
                  minutes = (elapsed / 60).floor
                  remaining = actual_timeout - elapsed.to_i

                  # Build message with guards
                  progress_message = build_progress_message(minutes, remaining)

                  # Create complete fragment object with i18n data
                  fragment = {
                    "type" => "wait",
                    "content" => progress_message,
                    "source" => "OpenAICodeAgent",
                    "elapsed" => elapsed.to_i,
                    "minutes" => minutes,
                    "remaining" => remaining.to_i
                  }

                  # Send through block if available
                  if block
                    block.call(fragment)
                  elsif defined?(::WebSocketHelper)
                    # Fallback to WebSocketHelper with session ID (or broadcast if no session)
                    helper = ::WebSocketHelper
                    if helper.respond_to?(:send_progress_fragment)
                      helper.send_progress_fragment(fragment, session_id)

                      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
                        if session_id
                          puts "[OpenAICodeAgent] Sent progress to session #{session_id}: #{progress_message[0..50]}..."
                        else
                          puts "[OpenAICodeAgent] Broadcasting progress to all: #{progress_message[0..50]}..."
                        end
                      end
                    end
                  elsif defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
                    puts "[OpenAICodeAgent] Progress (no WebSocket): #{progress_message}"
                  end

                  last_update = Time.now
                rescue => msg_error
                  # Silently handle message building/sending errors
                  if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
                    puts "[OpenAICodeAgent] Progress message error: #{msg_error.message}"
                  end
                end
              end
            end
          rescue => e
            # Silent handling - log only if extra logging enabled
            if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
              puts "[OpenAICodeAgent] Progress thread error: #{e.message}"
            end
          end
        end
      end

      # Clean up progress monitoring thread
      # @param thread [Thread] Thread to clean up
      def cleanup_progress_thread(thread)
        return unless thread

        begin
          thread[:should_stop] = true
          thread.join(1.0)  # Wait max 1 second
          thread.kill if thread.alive?  # Force kill if still running
        rescue => e
          # Even cleanup errors should be silent
          if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[OpenAICodeAgent] Thread cleanup error: #{e.message}"
          end
        end
      end

      # Build progress message based on elapsed time
      # @param minutes [Integer] Elapsed time in minutes
      # @param remaining_seconds [Integer] Remaining seconds until timeout
      # @return [String] HTML-formatted progress message
      def build_progress_message(minutes, remaining_seconds)
        # Guards for nil/invalid values
        minutes = 0 unless minutes.is_a?(Integer) && minutes >= 0
        remaining_seconds = 1200 unless remaining_seconds.is_a?(Integer)

        time_str = format_elapsed_time(minutes)

        # Add warning when approaching timeout
        timeout_warning = if remaining_seconds < 120 && remaining_seconds > 0
          " (Timeout in #{remaining_seconds} seconds)"
        elsif remaining_seconds < 300 && remaining_seconds > 0
          " (#{(remaining_seconds / 60).floor} minutes remaining)"
        else
          ""
        end

        # Use same HTML/icon format as existing wait messages
        case minutes
        when 0
          "<i class='fas fa-robot'></i> OpenAI Code is analyzing requirements..."
        when 1..2
          "<i class='fas fa-laptop-code'></i> OpenAI Code is generating code (#{time_str} elapsed)...#{timeout_warning}"
        when 3..4
          "<i class='fas fa-cogs'></i> OpenAI Code is structuring the solution (#{time_str} elapsed)...#{timeout_warning}"
        when 5..9
          "<i class='fas fa-brain'></i> OpenAI Code is optimizing the implementation (#{time_str} elapsed)...#{timeout_warning}"
        when 10..14
          "<i class='fas fa-hourglass-half'></i> Complex task in progress (#{time_str} elapsed)#{timeout_warning}"
        when 15..20
          "<i class='fas fa-clock'></i> Advanced reasoning in progress (#{time_str} elapsed)#{timeout_warning}"
        else
          "<i class='fas fa-exclamation-triangle'></i> Extended processing (#{time_str} elapsed)#{timeout_warning}"
        end
      rescue => e
        # Fallback message if formatting fails
        "<i class='fas fa-spinner'></i> Processing..."
      end

      # Format elapsed time in human-readable format
      # @param minutes [Integer] Time in minutes
      # @return [String] Formatted time string
      def format_elapsed_time(minutes)
        return "less than a minute" if minutes < 1

        if minutes == 1
          "1 minute"
        else
          "#{minutes} minutes"
        end
      rescue
        "several minutes"
      end
    end
  end
end