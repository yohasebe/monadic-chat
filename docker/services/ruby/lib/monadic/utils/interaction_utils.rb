require 'json'
require 'base64'
require_relative 'ssl_configuration'
require_relative 'extra_logger'
require_relative 'tts_utils'
require_relative 'stt_utils'
require_relative 'tavily_utils'

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

module InteractionUtils
  API_ENDPOINT = "https://api.openai.com/v1"
  TEMP_AUDIO_FILE = "temp_audio_file"

  OPEN_TIMEOUT = 10 # Timeout for opening a connection (seconds)
  READ_TIMEOUT = 60 # Timeout for reading data (seconds)
  WRITE_TIMEOUT = 60 # Timeout for writing data (seconds)

  # Number of retries for API requests
  MAX_RETRIES = 10
  # Delay between retries (seconds)
  RETRY_DELAY = 2

  # Cache class for API key validation
  class ApiKeyCache
    def initialize
      @cache = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize { @cache[key] }
    end

    def set(key, value)
      @mutex.synchronize { @cache[key] = value }
    end

    def clear
      @mutex.synchronize { @cache.clear }
    end
  end

  # Initialize cache as a singleton
  def self.api_key_cache
    @api_key_cache ||= ApiKeyCache.new
  end

  # Format API error JSON for better readability
  # @param error_data [Hash] The error data (can be nested)
  # @param provider [String] The provider name (optional, for context)
  # @return [String] Formatted error message
  def format_api_error(error_data, provider = nil)
    return error_data.to_s unless error_data.is_a?(Hash)

    error_parts = []

    # Add provider context if available
    error_parts << "[#{provider.upcase}]" if provider

    # Extract main error message
    main_message = extract_error_message(error_data)
    if main_message && main_message != error_data.to_s
      error_parts << main_message

      # Add additional context for specific error types
      context = extract_error_context(error_data)
      error_parts << context if context && !context.empty?
    else
      # If we couldn't extract a meaningful message, include the full error data
      # but format it more readably
      formatted_full_error = format_full_error_data(error_data)
      error_parts << formatted_full_error
    end

    # In debug mode, also include the original error data
    if ENV['APP_DEBUG'] && main_message && main_message != error_data.to_s
      error_parts << "(Raw: #{error_data.to_s.slice(0, 200)}#{error_data.to_s.length > 200 ? '...' : ''})"
    end

    error_parts.join(" ")
  end

  private

  def extract_error_message(error_data)
    # Handle string input
    return error_data if error_data.is_a?(String)

    # Try various common error message paths
    return error_data["message"] if error_data["message"]
    return error_data.dig("error", "message") if error_data.is_a?(Hash) && error_data["error"].is_a?(Hash)
    return error_data["detail"] if error_data["detail"]
    return error_data["error"] if error_data["error"].is_a?(String)

    # For nested structures, try to find the most relevant message
    if error_data["error"].is_a?(Hash)
      nested_error = error_data["error"]
      return nested_error["message"] || nested_error["detail"] || nested_error["description"]
    end

    # Fallback to the entire error object
    error_data.to_s
  end

  def extract_error_context(error_data)
    # Handle string input
    return "" if error_data.is_a?(String)

    context_parts = []

    # Handle quota errors specifically
    if (error_data.is_a?(Hash) && error_data["error"].is_a?(Hash) && error_data.dig("error", "code") == 429) || error_data["code"] == 429
      context_parts << "Rate limit exceeded"

      # Extract quota information
      if error_data.dig("error", "details")
        details = error_data["error"]["details"]
        quota_failures = details.find { |detail| detail["@type"]&.include?("QuotaFailure") }
        if quota_failures && quota_failures["violations"]
          violations = quota_failures["violations"]
          violation_types = violations.map { |v| v["quotaMetric"]&.split("/")&.last }.compact.uniq
          context_parts << "Quotas: #{violation_types.join(", ")}" unless violation_types.empty?
        end
      end
    end

    # Handle other specific error codes
    error_code = if error_data.is_a?(Hash)
      (error_data["error"].is_a?(Hash) ? error_data.dig("error", "code") : nil) || error_data["code"]
    end

    case error_code
    when 401
      context_parts << "Authentication failed"
    when 403
      context_parts << "Access forbidden"
    when 404
      context_parts << "Resource not found"
    when 500, 502, 503
      context_parts << "Server error"
    end

    # Extract status information
    if error_data.is_a?(Hash) && error_data["error"].is_a?(Hash) && error_data.dig("error", "status") && error_data["error"]["status"] != "RESOURCE_EXHAUSTED"
      context_parts << "Status: #{error_data["error"]["status"]}"
    end

    context_parts.join(", ")
  end

  def format_full_error_data(error_data)
    # Try to format the full error data in a more readable way
    # while preserving all information
    case error_data
    when Hash
      # If it's a hash, try to extract key information
      key_info = []

      # Look for common error fields and present them clearly
      if error_data["error"]
        if error_data["error"].is_a?(Hash)
          key_info << "Error: #{format_nested_hash(error_data["error"])}"
        else
          key_info << "Error: #{error_data["error"]}"
        end
      end

      if error_data["message"]
        key_info << "Message: #{error_data["message"]}"
      end

      if error_data["details"]
        key_info << "Details: #{format_nested_hash(error_data["details"])}"
      end

      if error_data["code"]
        key_info << "Code: #{error_data["code"]}"
      end

      if error_data["status"]
        key_info << "Status: #{error_data["status"]}"
      end

      # If we found key information, use it. Otherwise, fall back to JSON.
      if key_info.any?
        key_info.join(", ")
      else
        # Format as readable JSON but limit depth to avoid huge output
        JSON.pretty_generate(error_data).lines.first(10).join.chomp
      end
    else
      error_data.to_s
    end
  rescue JSON::GeneratorError, StandardError
    # If JSON formatting fails, just convert to string
    error_data.to_s
  end

  def format_nested_hash(hash, max_depth = 2, current_depth = 0)
    return hash.to_s if current_depth >= max_depth || !hash.is_a?(Hash)

    parts = []
    hash.each do |key, value|
      if value.is_a?(Hash) && current_depth < max_depth - 1
        nested = format_nested_hash(value, max_depth, current_depth + 1)
        parts << "#{key}: {#{nested}}"
      elsif value.is_a?(Array)
        # For arrays, show first few elements
        array_preview = value.first(3).map(&:to_s).join(", ")
        array_preview += "..." if value.length > 3
        parts << "#{key}: [#{array_preview}]"
      else
        parts << "#{key}: #{value}"
      end
    end

    parts.join(", ")
  end

  public

  # Check if the API key is valid with caching mechanism
  # @param api_key [String] The API key to check
  # @return [Hash] A hash containing the result of the check
  def check_api_key(api_key)
    if api_key
      api_key = api_key.strip
      settings.api_key = api_key
    else
      return { "type" => "error", "content" => "ERROR: API key is empty" }
    end

    # Return cached result if available
    cached_result = InteractionUtils.api_key_cache.get(api_key)
    if cached_result
      Monadic::Utils::ExtraLogger.log { "check_api_key: Using cached result - #{cached_result['type']}" }
      return cached_result
    end

    Monadic::Utils::ExtraLogger.log { "check_api_key: Starting fresh API check" }

    target_uri = "#{API_ENDPOINT}/models"

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{settings.api_key}"
    }

    num_retrial = 0

    begin
      start_time = Time.now
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).get(target_uri)
      elapsed = Time.now - start_time
      res_body = JSON.parse(res.body)

      result = if res_body && res_body["data"]
                 { "type" => "models", "content" => "API token verified"}
               else
                 { "type" => "error", "content" => "ERROR: API token is not accepted" }
               end

      Monadic::Utils::ExtraLogger.log { "check_api_key: API check completed in #{elapsed.round(2)}s - result: #{result['type']}" }

      # Cache the result
      InteractionUtils.api_key_cache.set(api_key, result)
      result

    rescue HTTP::Error, HTTP::TimeoutError => e
      if num_retrial < MAX_RETRIES
        num_retrial += 1
        Monadic::Utils::ExtraLogger.log { "check_api_key: Retry #{num_retrial}/#{MAX_RETRIES} after error: #{e.class} - #{e.message}" }
        sleep RETRY_DELAY
        retry
      else
        error_message = "API request failed after #{MAX_RETRIES} retries: #{e.message}"
        Monadic::Utils::ExtraLogger.log { "check_api_key: FAILED after #{MAX_RETRIES} retries - #{e.class}: #{e.message}" }
        error_result = { "type" => "error", "content" => "ERROR: #{error_message}" }
        # Cache the error result as well
        InteractionUtils.api_key_cache.set(api_key, error_result)
        return error_result
      end
    end
  end

  # Check and notify if model was automatically switched
  # @param response_model [String] The model returned in the response
  # @param requested_model [String] The model that was requested
  # @param session [Hash] The session object
  # @param block [Proc] The block to call for notifications
  def check_model_switch(response_model, requested_model, session, &block)
    return unless response_model && requested_model && block
    return if response_model == requested_model
    return if session[:model_switch_notified]

    # Ignore version switches for the same base model (e.g., gpt-4.1 -> gpt-4.1-2025-04-14)
    # Extract base model name (everything before the date)
    response_base = response_model.split(/\d{4}-\d{2}-\d{2}/).first.chomp('-')
    requested_base = requested_model.split(/\d{4}-\d{2}-\d{2}/).first.chomp('-')
    return if response_base == requested_base

    session[:model_switch_notified] = true
    system_msg = {
      "type" => "system_info",
      "content" => "Model automatically switched from #{requested_model} to #{response_model}."
    }
    block.call system_msg
  end

  def send_verification_notification(session, &block)
    return unless session[:verification_wait_message]

    msg = session.delete(:verification_wait_message)
    block&.call({ "type" => "wait", "content" => msg })
  end
end
