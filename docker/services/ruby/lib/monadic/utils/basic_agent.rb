module BasicAgent
  API_ENDPOINT = "https://api.openai.com/v1"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60

  MAX_FUNC_CALLS = 10
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  module_function

  def send_query(options)
    api_key = ENV["OPENAI_API_KEY"]

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model" => "gpt-4o-mini",
      "n" => 1,
      "stream" => false,
      "stop" => nil,
      "messages" => []
    }

    body.merge!(options)

    target_uri = API_ENDPOINT + "/chat/completions"

    http = HTTP.headers(headers)
    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)
    unless res.status.success?
      pp JSON.parse(res.body)["error"]
      "ERROR: #{JSON.parse(res.body)["error"]}"
    end

    JSON.parse(res.body).dig("choices", 0, "message", "content")
  rescue StandardError
    "Error: The request could not be completed."
  end
end
