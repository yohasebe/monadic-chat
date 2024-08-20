require_relative "basic_agent"

module MonadicAgent
  extend BasicAgent

  def command_output_agent(prompt, content)
    num_retrial = 0

    api_key = ENV["OPENAI_API_KEY"]

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    model = ENV["AI_USER_MODEL"] || "gpt-4o-mini"

    body = {
      "model" => model,
      "temperature" => 0.0,
      "top_p" => 0.0,
      "n" => 1,
      "stream" => false,
      "response_format" => {
        type: "json_schema",
        json_schema: {
          name: "examine_response",
          schema: {
            type: "object",
            properties: {
              result: {
                type: "string",
                enum: ["success", "error"]
              },
              content: {
                type: "string"
              }
            },
            required: ["result", "content"],
            additionalProperties: false
          },
          strict: true
        }
      }
    }

    body["messages"] = [
      { "role" => "system", "content" => prompt },
      { "role" => "user", "content" => content }
    ]

    target_uri = "https://api.openai.com/v1/chat/completions"

    http = HTTP.headers(headers)

    res = http.post(target_uri, json: body)
    unless res.status.success?
      return "ERROR: #{JSON.parse(res.body)}"
    end

    structured_res = JSON.parse(res.body).dig("choices", 0, "message", "content")
    JSON.parse(structured_res)
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      error_message = "The request has timed out."
      puts "ERROR: #{error_message}"
      exit
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    puts "ERROR: #{e.message}"
    exit
  end
end
