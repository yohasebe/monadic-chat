require_relative "basic_agent"

module MonadicAgent
  extend BasicAgent

  def response_verifier_agent(user_query: "", agent_response: "")
    model = ENV["AI_USER_MODEL"] || "gpt-4o-mini"

    prompt = <<~TEXT
      Your are an agent that verify and make comments about given pairs of query and response. If the response is correct, you should say 'The response is correct'. But you are rather critical and meticulous, considering many factors, so it is more likely that you will find possible caveats in the response.

      You should point out the errors or possible caveats in the response and suggest corrections where necessary. Your response should be formatted as follows with the validity of the original response out of 10 and the model used for the evaluation which is specified in the text below:

      ### COMMENTS
      YOUR_COMMENTS

      ### VALIDITY
      VALIDITY_OF_ORIGINAL_RESPONSE/10

      ### Evaluation Model
      #{model}
    TEXT

    messages = [
      {
        "role" => "system",
        "content" => prompt
      },
      {
        "role" => "user",
        "content" => <<~TEXT
          ### Query
          #{user_query}

          ### Response
          #{agent_response}
        TEXT
      }
    ]
    body = {
      messages: messages,
      model: model
    }

    BasicAgent.send_query(body)
  end
end
