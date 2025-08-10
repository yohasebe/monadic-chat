# frozen_string_literal: true

require_relative "debug_helper"

# Common network error handling for API requests
module NetworkErrorHandler
  # Standard timeout configuration
  DEFAULT_TIMEOUTS = {
    open: 10,    # Connection timeout
    read: 120,   # Read timeout  
    write: 120   # Write timeout
  }.freeze

  # Provider-specific timeout overrides
  PROVIDER_TIMEOUTS = {
    claude: { open: 10, read: 300, write: 300 },
    perplexity: { open: 5, read: 600, write: 600 },
    deepseek: { open: 15, read: 180, write: 180 }  # DeepSeek needs longer timeout for cold starts
  }.freeze

  # Retry configuration
  DEFAULT_MAX_RETRIES = 5
  DEFAULT_RETRY_BASE_DELAY = 1

  # Network error types
  RETRYABLE_ERRORS = [
    HTTP::TimeoutError,
    HTTP::ConnectionError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    Errno::ETIMEDOUT,
    Errno::ENETUNREACH,
    OpenSSL::SSL::SSLError
  ].freeze

  # Execute HTTP request with retry logic
  def with_network_retry(provider: nil, max_retries: DEFAULT_MAX_RETRIES, &block)
    retries = 0
    last_error = nil

    while retries <= max_retries
      begin
        # Execute the HTTP request
        result = yield
        
        # If we get here, request was successful
        return result
        
      rescue *RETRYABLE_ERRORS => e
        last_error = e
        retries += 1
        
        if retries <= max_retries
          delay = calculate_retry_delay(retries)
          log_retry_attempt(e, retries, max_retries, delay)
          sleep(delay)
        else
          log_retry_exhausted(e, max_retries)
          raise RuntimeError.new(format_network_error(e, provider))
        end
        
      rescue JSON::ParserError => e
        # JSON errors are not retryable
        log_json_error(e)
        raise
        
      rescue StandardError => e
        # Other errors are not retryable
        log_unexpected_error(e)
        raise
      end
    end
  end

  # Get timeout configuration for a provider
  def timeout_config_for(provider)
    base = DEFAULT_TIMEOUTS.dup
    overrides = PROVIDER_TIMEOUTS[provider&.to_sym] || {}
    base.merge(overrides)
  end

  private

  # Calculate exponential backoff delay
  def calculate_retry_delay(attempt)
    # Exponential backoff with jitter
    base_delay = DEFAULT_RETRY_BASE_DELAY
    max_delay = base_delay * (2 ** (attempt - 1))
    jitter = rand(0.0..0.3) * max_delay
    [max_delay + jitter, 30].min # Cap at 30 seconds
  end

  # Format network error for user display
  def format_network_error(error, provider)
    case error
    when HTTP::TimeoutError, Net::ReadTimeout
      "Request to #{provider || 'API'} timed out. Please try again."
    when HTTP::ConnectionError, Errno::ECONNREFUSED
      "Unable to connect to #{provider || 'API'}. Please check your internet connection."
    when OpenSSL::SSL::SSLError
      "SSL connection error with #{provider || 'API'}. Please try again."
    else
      "Network error occurred: #{error.message}"
    end
  end

  # Logging methods
  def log_retry_attempt(error, attempt, max_retries, delay)
    DebugHelper.debug(
      "Network error (attempt #{attempt}/#{max_retries}): #{error.class} - #{error.message}. Retrying in #{delay.round(2)}s",
      category: "api",
      level: :warning
    )
  end

  def log_retry_exhausted(error, max_retries)
    DebugHelper.debug(
      "Network error after #{max_retries} retries: #{error.class} - #{error.message}",
      category: "api", 
      level: :error
    )
  end

  def log_json_error(error)
    DebugHelper.debug(
      "JSON parse error (not retryable): #{error.message}",
      category: "api",
      level: :error
    )
  end

  def log_unexpected_error(error)
    DebugHelper.debug(
      "Unexpected error (not retryable): #{error.class} - #{error.message}",
      category: "api",
      level: :error
    )
  end
end