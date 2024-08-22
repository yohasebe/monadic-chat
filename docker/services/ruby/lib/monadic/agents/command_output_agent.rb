require_relative "basic_agent"

module MonadicAgent
  extend BasicAgent

  def second_opinion_agent(prompt, content)
    model = ENV["AI_USER_MODEL"] || "gpt-4o-mini"

    body = {
      model: model,
      temperature: 0.0,
      top_p: 0.0,
      n: 1,
      stream: false,
      response_format: {
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

    body[:messages] = [
      { role: "system", content: prompt },
      { role: "user", content: content }
    ]

    json = BasicAgent.send_query(body)
    begin
      JSON.parse(json)
    rescue JSON::ParserError
      { "result" => "error", "content" => "Error parsing JSON response." }
    end
  end
end
