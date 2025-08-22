# frozen_string_literal: true

module Monadic
  module Utils
    # Unified error formatting for all providers
    class ErrorFormatter
      # Error categories
      API_KEY_ERROR = "Configuration Error"
      API_ERROR = "API Error"
      NETWORK_ERROR = "Network Error"
      TIMEOUT_ERROR = "Timeout Error"
      PARSING_ERROR = "Parsing Error"
      VALIDATION_ERROR = "Validation Error"
      TOOL_ERROR = "Tool Execution Error"
      UNKNOWN_ERROR = "Unknown Error"

      class << self
        # Format error with consistent structure
        # @param category [String] Error category (use constants above)
        # @param message [String] Error message
        # @param details [Hash] Optional details (provider, code, suggestion)
        # @return [String] Formatted error message
        def format(category:, message:, details: {})
          provider = details[:provider] || "System"
          code = details[:code]
          suggestion = details[:suggestion]
          
          error_parts = ["[#{provider}] #{category}: #{message}"]
          error_parts << "Suggestion: #{suggestion}" if suggestion
          error_parts << "(Code: #{code})" if code
          
          error_parts.join(" ")
        end

        # Format API key missing error
        def api_key_error(provider:, env_var:)
          format(
            category: API_KEY_ERROR,
            message: "#{env_var} not found",
            details: {
              provider: provider,
              suggestion: "Please set #{env_var} in ~/monadic/config/env file"
            }
          )
        end

        # Format API response error
        def api_error(provider:, message:, code: nil)
          format(
            category: API_ERROR,
            message: message,
            details: {
              provider: provider,
              code: code
            }
          )
        end

        # Format network/timeout error
        def network_error(provider:, message:, timeout: false)
          category = timeout ? TIMEOUT_ERROR : NETWORK_ERROR
          format(
            category: category,
            message: message,
            details: {
              provider: provider,
              suggestion: timeout ? "Try increasing timeout or retry" : "Check network connection"
            }
          )
        end

        # Format parsing error
        def parsing_error(provider:, message:)
          format(
            category: PARSING_ERROR,
            message: message,
            details: {
              provider: provider,
              suggestion: "Check API response format"
            }
          )
        end

        # Format tool execution error
        def tool_error(provider:, tool_name:, message:)
          format(
            category: TOOL_ERROR,
            message: "#{tool_name}: #{message}",
            details: {
              provider: provider
            }
          )
        end

        # Format validation error
        def validation_error(provider:, message:)
          format(
            category: VALIDATION_ERROR,
            message: message,
            details: {
              provider: provider
            }
          )
        end

        # Format unknown/unexpected error
        def unknown_error(provider:, message:, include_backtrace: false, exception: nil)
          details = { provider: provider }
          
          if include_backtrace && exception
            message = "#{message}\n#{exception.class}: #{exception.message}\n#{exception.backtrace.first(3).join("\n")}"
          end
          
          format(
            category: UNKNOWN_ERROR,
            message: message,
            details: details
          )
        end
      end
    end
  end
end