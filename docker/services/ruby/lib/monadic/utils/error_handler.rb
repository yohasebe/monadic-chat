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