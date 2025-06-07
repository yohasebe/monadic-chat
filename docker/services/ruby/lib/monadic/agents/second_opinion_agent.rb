module SecondOpinionAgent
  def second_opinion_agent(user_query: "", agent_response: "")
    model = ENV["AI_USER_MODEL"] || "gpt-4.1"

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
    
    # Use explicit string keys consistently
    parameters = {
      "messages" => messages,
      "model" => model
    }
    
    # Debug logging
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "SecondOpinionAgent: Using model #{model} for second opinion"
    end

    response = send_query(parameters, model: model)
    
    # Parse the response to extract comments, validity, and model
    if response.is_a?(String)
      comments = ""
      validity = "unknown"
      
      # Extract comments
      if response =~ /### COMMENTS\s*\n(.*?)(?=\n### VALIDITY|\z)/m
        comments = $1.strip
      end
      
      # Extract validity
      if response =~ /### VALIDITY\s*\n(\d+)\/10/
        validity = "#{$1}/10"
      end
      
      {
        comments: comments,
        validity: validity,
        model: model
      }
    else
      {
        comments: "Failed to get second opinion",
        validity: "error",
        model: model
      }
    end
  end
end
