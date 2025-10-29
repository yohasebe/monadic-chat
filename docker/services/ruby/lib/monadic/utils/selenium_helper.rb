# frozen_string_literal: true

module Monadic
  module Utils
    module SeleniumHelper
      # Check if Selenium container is available with retries
      # @param retries [Integer] Number of retry attempts (default: 3)
      # @param delay [Integer] Delay in seconds between retries (default: 2)
      # @return [Boolean] true if Selenium is available, false otherwise
      def ensure_selenium_available?(retries: 3, delay: 2)
        retries.times do |attempt|
          return true if selenium_available?

          if CONFIG && CONFIG["EXTRA_LOGGING"]
            puts "[SeleniumHelper] Selenium check failed (attempt #{attempt + 1}/#{retries}), retrying in #{delay}s"
          end
          sleep delay
        end
        false
      end

      # Check if Selenium container is currently running
      # @return [Boolean] true if both Selenium and Python containers are running
      def selenium_available?
        containers = `docker ps --format "{{.Names}}"`
        selenium_available = containers.include?("monadic-chat-selenium-container") || containers.include?("monadic_selenium")
        python_available = containers.include?("monadic-chat-python-container") || containers.include?("monadic_python")

        if CONFIG && CONFIG["EXTRA_LOGGING"]
          puts "[SeleniumHelper] Container check - Selenium: #{selenium_available}, Python: #{python_available}"
        end

        selenium_available && python_available
      end

      # Get a user-friendly error message when Selenium is unavailable
      # @return [Hash] Error response hash with message
      def selenium_unavailable_error
        {
          success: false,
          error: "Selenium container is not running. Web automation features require the Selenium service to be active.",
          suggestion: "Please start the Selenium container from the Actions menu (Actions → Start Selenium Container) and try again."
        }
      end

      # Check Selenium availability and return error if not available
      # @return [Hash, nil] Error hash if unavailable, nil if available
      def check_selenium_or_error
        return nil if ensure_selenium_available?

        selenium_unavailable_error
      end
    end
  end
end
