require "net/http"
require "uri"
require "json"

class FlaskAppClient
  BASE_URL = if File.file?("/.dockerenv")
               "http://python_service:5070"
             else
               "http://0.0.0.0:5070"
             end

  def initialize(model_name = "gpt-3.5-turbo")
    @model_name = model_name
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

  def count_tokens(text, model = nil)
    model_name = model || @model_name
    body = { text: text, model_name: model_name }
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
    request.body = body.to_json
    # make a request with the timeout set to 20 seconds
    http.read_timeout = 20
    response = http.request(request)
    response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
  end
end
