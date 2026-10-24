# frozen_string_literal: true

require_relative "secret_redactor"

module Monadic
  module Utils
    # Centralized logger for EXTRA_LOGGING output. Every line passes through
    # SecretRedactor before it is written. Nothing is written for the work of
    # a Private chat: a line cannot be told to hold none of the chat.
    # Caches file handle to avoid repeated open/close overhead
    #
    # Usage:
    #   ExtraLogger.log("message") if ExtraLogger.enabled?
    #   # or
    #   ExtraLogger.log { "expensive #{computation}" }
    #
    module ExtraLogger
      @mutex = Mutex.new
      @file_handle = nil
      @enabled = nil

      class << self
        # Check if extra logging is enabled (cached)
        def enabled?
          return @enabled unless @enabled.nil?

          @enabled = CONFIG["EXTRA_LOGGING"] == true || CONFIG["EXTRA_LOGGING"] == "true"
        end

        # Log a message to the extra log file
        # @param message [String] the message to log (optional if block given)
        # @yield block that returns the message (lazy evaluation)
        def log(message = nil, &block)
          return unless enabled?
          return if private_work?

          msg = block ? block.call : message
          return if msg.nil?

          timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")
          formatted = "[#{timestamp}] #{SecretRedactor.redact(msg.to_s)}"

          @mutex.synchronize do
            ensure_file_open
            @file_handle.puts(formatted)
            @file_handle.flush # Ensure immediate write for debugging
          end
        rescue StandardError => e
          # Fail silently - logging should never break the app
          STDERR.puts "[ExtraLogger] Error writing to log: #{e.message}"
        end

        # Log JSON data with pretty formatting
        # @param label [String] label for the log entry
        # @param data [Object] data to log as JSON
        def log_json(label, data)
          return unless enabled?
          return if private_work?

          log("#{label}:\n#{JSON.pretty_generate(data)}")
        rescue JSON::GeneratorError
          log("#{label}: [JSON generation failed] #{data.inspect}")
        end

        # Log raw data without timestamp (for multi-line output)
        def log_raw(message)
          return unless enabled?
          return if private_work?

          @mutex.synchronize do
            ensure_file_open
            @file_handle.puts(SecretRedactor.redact(message.to_s))
            @file_handle.flush
          end
        rescue StandardError
          # Fail silently
        end

        # Close the file handle (call on shutdown if needed)
        def close
          @mutex.synchronize do
            if @file_handle && !@file_handle.closed?
              @file_handle.close
            end
            @file_handle = nil
          end
        end

        # Reset state (for testing)
        def reset!
          close
          @enabled = nil
        end

        def private_work?
          defined?(Monadic::History::Policy) && Monadic::History::Policy.current_work_private?
        end

        private

        def ensure_file_open
          return if @file_handle && !@file_handle.closed?

          log_file = defined?(MonadicApp::EXTRA_LOG_FILE) ? MonadicApp::EXTRA_LOG_FILE : "/monadic/log/extra.log"
          @file_handle = File.open(log_file, "a")
          @file_handle.sync = true # Auto-flush
        end
      end
    end
  end
end
