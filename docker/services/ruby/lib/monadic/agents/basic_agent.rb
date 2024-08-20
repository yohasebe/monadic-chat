module BasicAgent
  def self.simple_chat_agent(messages, model: "gpt-4o-mini")
    # num_retrial = 0
    api_key = ENV["OPENAI_API_KEY"]

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model" => model,
      "n" => 1,
      "stream" => false,
      "stop" => nil,
      "messages" => messages
    }

    target_uri = "https://api.openai.com/v1/chat/completions"

    http = HTTP.headers(headers)
    res = http.timeout(connect: 5, write: 60, read: 60).post(target_uri, json: body)

    unless res.status.success?
      pp JSON.parse(res.body)["error"]
      "ERROR: #{JSON.parse(res.body)["error"]}"
    end

    JSON.parse(res.body).dig("choices", 0, "message", "content")
  rescue StandardError
    "Error: The request could not be completed."
  end
end
