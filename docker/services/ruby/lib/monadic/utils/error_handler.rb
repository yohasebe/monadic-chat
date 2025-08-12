# frozen_string_literal: true

require 'net/http'
require 'json'

# Mock HTTP module for error types if not already loaded
module HTTP
  class Error < StandardError; end
  class TimeoutError < Error; end
  class ConnectionError < Error; end
end unless defined?(HTTP)

# Centralized error handling module for Monadic Chat
module ErrorHandler
  # Unified error formatter for consistent error messages
  class UnifiedError
    attr_reader :category, :message, :code, :suggestion, :details

    CATEGORIES = {
      api: "API Error",
      validation: "Invalid Input", 
      configuration: "Configuration Error",
      execution: "Execution Error",
      network: "Network Error",
      authentication: "Authentication Error",
      rate_limit: "Rate Limit",
      timeout: "Timeout",
      file: "File Error",
      tool: "Tool Error"
    }.freeze

    def initialize(category:, message:, code: nil, suggestion: nil, details: nil)
      @category = CATEGORIES[category] || category.to_s
      @message = message
      @code = code
      @suggestion = suggestion
      @details = details
    end

    # Format error for user display
    def to_s
      msg = "Error: [#{@category}] - #{@message}"
      msg += ". #{@suggestion}" if @suggestion
      msg += " (Code: #{@code})" if @code
      msg
    end

    # Format error as JSON
    def to_json(*args)
      {
        category: @category,
        message: @message,
        code: @code,
        suggestion: @suggestion,
        details: @details
      }.to_json(*args)
    end
  end

  # Create standardized error messages
  def self.format_error(category:, message:, **options)
    UnifiedError.new(
      category: category,
      message: message,
      code: options[:code],
      suggestion: options[:suggestion],
      details: options[:details]
    ).to_s
  end

  # Provider-specific error formatting
  def self.format_provider_error(provider:, error:, context: nil)
    category, suggestion = categorize_provider_error(error)
    
    message = case error
              when String
                clean_error_message(error)
              when Exception
                clean_error_message(error.message)
              else
                error.to_s
              end

    format_error(
      category: category,
      message: "#{provider} - #{message}",
      suggestion: suggestion,
      details: context
    )
  end

  # Tool execution error formatting
  def self.format_tool_error(tool:, error:, params: nil)
    format_error(
      category: :tool,
      message: "Tool '#{tool}' failed - #{clean_error_message(error)}",
      suggestion: "Check tool parameters and try again",
      details: params
    )
  end

  # Validation error formatting
  def self.format_validation_error(field:, requirement:, value: nil)
    message = value.nil? || value.to_s.empty? ? 
              "#{field} is required" : 
              "#{field} has invalid value"
    
    format_error(
      category: :validation,
      message: message,
      suggestion: requirement
    )
  end

  private

  def self.categorize_provider_error(error)
    error_str = error.to_s.downcase
    
    case error_str
    when /rate.?limit|too.?many.?requests/
      [:rate_limit, "Please wait before retrying"]
    when /unauthorized|authentication|api.?key/
      [:authentication, "Check your API key configuration"]
    when /timeout|timed.?out/
      [:timeout, "Try again with a simpler request"]
    when /network|connection/
      [:network, "Check your internet connection"]
    when /not.?found|404/
      [:api, "Verify the resource exists"]
    else
      [:api, nil]
    end
  end

  def self.clean_error_message(message)
    return "" unless message
    
    # Remove common error prefixes
    cleaned = message.gsub(/^(Error:|Exception:|RuntimeError:)\s*/i, "")
    
    # Remove file paths and line numbers
    cleaned = cleaned.gsub(/\s+\(.*?:\d+\)/, "")
    
    # Capitalize first letter
    cleaned[0] = cleaned[0].upcase if cleaned.length > 0
    
    cleaned
  end
end

# Keep backward compatibility with existing module
module ErrorHandler
  # Common exception categories
  module NetworkErrors
    HTTP_ERRORS = [
      HTTP::Error,
      HTTP::TimeoutError,
      HTTP::ConnectionError,
      Net::HTTPError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::ENETUNREACH
    ].freeze
  end

  module FileSystemErrors
    FILE_ERRORS = [
      Errno::ENOENT,      # File not found
      Errno::EACCES,      # Permission denied
      Errno::EISDIR,      # Is a directory
      Errno::ENOSPC,      # No space left
      IOError,
      SystemCallError
    ].freeze
  end

  module DataErrors
    PARSE_ERRORS = [
      JSON::ParserError,
      ArgumentError,
      TypeError,
      NoMethodError
    ].freeze
  end

  # Log error with appropriate level and context
  def log_error(error, context = {})
    error_info = {
      class: error.class.name,
      message: error.message,
      context: context,
      backtrace: error.backtrace&.first(5)
    }

    case error
    when *NetworkErrors::HTTP_ERRORS
      DebugHelper.debug("Network error: #{error_info.to_json}", "api", level: :error)
    when *FileSystemErrors::FILE_ERRORS
      DebugHelper.debug("File system error: #{error_info.to_json}", "app", level: :error)
    when *DataErrors::PARSE_ERRORS
      DebugHelper.debug("Data parsing error: #{error_info.to_json}", "app", level: :warning)
    else
      DebugHelper.debug("Unexpected error: #{error_info.to_json}", "app", level: :error)
    end
  end

  # Handle errors with appropriate recovery strategy
  def handle_error(error, context = {})
    log_error(error, context)

    case error
    when *NetworkErrors::HTTP_ERRORS
      handle_network_error(error, context)
    when *FileSystemErrors::FILE_ERRORS
      handle_file_error(error, context)
    when *DataErrors::PARSE_ERRORS
      handle_data_error(error, context)
    else
      handle_unexpected_error(error, context)
    end
  end

  private

  def handle_network_error(error, context)
    case error
    when Net::OpenTimeout, Net::ReadTimeout, HTTP::TimeoutError
      { error: "Request timed out. Please try again.", retry: true }
    when Errno::ECONNREFUSED
      { error: "Connection refused. Please check if the service is running.", retry: false }
    else
      { error: "Network error occurred: #{error.message}", retry: true }
    end
  end

  def handle_file_error(error, context)
    case error
    when Errno::ENOENT
      { error: "File not found: #{context[:file_path]}", retry: false }
    when Errno::EACCES
      { error: "Permission denied accessing: #{context[:file_path]}", retry: false }
    else
      { error: "File system error: #{error.message}", retry: false }
    end
  end

  def handle_data_error(error, context)
    case error
    when JSON::ParserError
      { error: "Invalid JSON format", retry: false, suggestion: "Check the data format" }
    else
      { error: "Data processing error: #{error.message}", retry: false }
    end
  end

  def handle_unexpected_error(error, context)
    { error: "An unexpected error occurred: #{error.message}", retry: false }
  end
end