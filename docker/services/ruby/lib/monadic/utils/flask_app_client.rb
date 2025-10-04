require "net/http"
require "uri"
require "json"
require_relative "environment"
require_relative "ssl_configuration"

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

class FlaskAppClient
  # Default port for Python service
  PYTHON_PORT = (defined?(CONFIG) && CONFIG["PYTHON_PORT"]) || "5070"
  
  # Determine base URL based on environment
  BASE_URL = if Monadic::Utils::Environment.in_container?
               # Inside Docker container, use service name and configured port
               "http://python_service:#{PYTHON_PORT}"
             else
               # Local development: connect to loopback, not 0.0.0.0 (listen addr)
               # 0.0.0.0 is for server binding, not appropriate as client connection destination
               host = (defined?(CONFIG) && CONFIG["PYTHON_HOST"]) || "127.0.0.1"
               "http://#{host}:#{PYTHON_PORT}"
             end

  def initialize(model_name = "gpt-3.5-turbo")
    @model_name = model_name
    # Attempt to warm up the encodings on initialization
    warmup_encodings
  end
  
  # Warm up the tokenizer encodings to avoid first-request latency
  def warmup_encodings
    Thread.new do
      begin
        uri = URI.parse("#{BASE_URL}/warmup")
        http = Net::HTTP.new(uri.host, uri.port)
        
        # Set shorter timeout for warmup
        http.open_timeout = 10
        http.read_timeout = 10
        
        response = http.get(uri.request_uri)
        if response.is_a?(Net::HTTPSuccess)
          puts "[FlaskAppClient] Tokenizer encodings warmed up successfully"
        end
      rescue StandardError => e
        # Log warmup failure but don't block application startup
        puts "[FlaskAppClient] Tokenizer warmup failed: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      end
    end
  end
  
  # Check if the Python service is available
  def service_available?
    uri = URI.parse("#{BASE_URL}/health")
    http = Net::HTTP.new(uri.host, uri.port)
    
    # Set shorter timeout for health check
    http.open_timeout = 5
    http.read_timeout = 5
    
    begin
      response = http.get(uri.request_uri)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      puts "[FlaskAppClient] Health check failed: #{e.message}"
      false
    end
  end

  def get_encoding_name(model = nil)
    model_name = model || @model_name
    body = { model_name: model_name }
    response = post_request("get_encoding_name", body)
    if response["error"]
      nil
    else
      response["encoding_name"]
    end
  end

  # Token count cache to reduce duplicate calls for the same text
  @@token_count_cache = {}
  @@cache_mutex = Mutex.new
  @@MAX_CACHE_SIZE = 1000  # Maximum number of items to cache
  
  def count_tokens(text, encoding_name = "o200k_base")
    # Create cache key that includes both text and encoding_name
    cache_key = "#{encoding_name}:#{text.hash}"
    
    # Check cache first (thread-safe read)
    @@cache_mutex.synchronize do
      return @@token_count_cache[cache_key] if @@token_count_cache.key?(cache_key)
    end
    
    # If not in cache, make the API call
    body = { text: text, encoding_name: encoding_name }
    response = post_request("count_tokens", body)
    result = response ? response["number_of_tokens"].to_i : nil
    
    # Only cache successful results
    if result
      @@cache_mutex.synchronize do
        # Implement LRU-like behavior by removing oldest entries if cache is too large
        if @@token_count_cache.size >= @@MAX_CACHE_SIZE
          @@token_count_cache.shift  # Remove oldest entry
        end
        
        @@token_count_cache[cache_key] = result
      end
    end
    
    result
  end

  def get_tokens_sequence(text)
    body = { text: text, model_name: @model_name }
    response = post_request("get_tokens_sequence", body)
    response ? response["tokens_sequence"].split(",").map(&:to_i) : nil
  end

  def decode_tokens(tokens)
    body = { tokens: tokens.join(","), model_name: @model_name }
    response = post_request("decode_tokens", body)
    response ? response["original_text"] : nil
  end

  private

  def post_request(endpoint, body)
    uri = URI.parse("#{BASE_URL}/#{endpoint}")
    header = { "Content-Type": "application/json" }
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.request_uri, header)

    # Set appropriate timeouts for the request
    http.open_timeout = 5     # Connection open timeout
    http.read_timeout = 600   # Response read timeout
    
    begin
      request.body = body.to_json
      response = http.request(request)
      
      # Handle successful response
      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        puts "[FlaskAppClient] Error: HTTP #{response.code} - #{response.message}" if response && response.respond_to?(:code)
        nil
      end
    rescue Net::OpenTimeout
      puts "[FlaskAppClient] Error: Connection to Python service timed out (#{uri})"
      nil
    rescue Net::ReadTimeout
      puts "[FlaskAppClient] Error: Reading from Python service timed out (#{uri})"
      nil
    rescue StandardError => e
      puts "[FlaskAppClient] Error connecting to Python service: #{e.message} (#{uri})"
      nil
    end
  end
end
