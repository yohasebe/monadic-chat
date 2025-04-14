require "net/http"
require "uri"
require "json"

class FlaskAppClient
  # Default port for Python service
  PYTHON_PORT = ENV["PYTHON_PORT"] || "5070"
  
  # Determine base URL based on environment
  BASE_URL = if File.file?("/.dockerenv")
               # Inside Docker container, use service name
               "http://python_service:5070"
             else
               # Local development, use localhost
               "http://0.0.0.0:5070"
             end

  def initialize(model_name = "gpt-3.5-turbo")
    @model_name = model_name
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

  def count_tokens(text, encoding_name = "o200k_base")
    body = { text: text, encoding_name: encoding_name }
    response = post_request("count_tokens", body)
    response ? response["number_of_tokens"].to_i : nil
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
