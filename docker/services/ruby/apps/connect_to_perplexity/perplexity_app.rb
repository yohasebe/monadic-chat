# frozen_string_literal: true

class Perplexity < MonadicApp
  def icon
    "<i class='fa-solid fa-p'></i>"
  end

  def description
    "This app accesses the Perplexity API to answer questions about a wide range of topics."
  end

  def initial_prompt
    text = <<~TEXT
      You have access to the Perplexity API to answer questions about a wide range of topics through the function `perplexity_query(message, model)`, which is available in your environment.

      First, run `check_settings` to verify the settings of the Perplexity API. The function will return the response in the following format:

      { API_KEY: true, MODEL: MODEL_NAME}

      If the API key is not set, tell the user to set the API key to the `.env` file. And if the model is not set, ask the user which Perplexity model they would like to use. The user can choose from the following models:

      - `sonar-small-chat`
      - `sonar-small-online`
      - `sonar-medium-chat`
      - `sonar-medium-online`
      - `mistral-7b-instruct`
      - `mixtral-8x7b-instruct`

      Of course, if `check_settings` returns a model name, use that model to answer the user's questions. If the model is not set, use the default model `sonar-medium-online`.

      If the API is set and the model is decided, ask the user to provide the question they would like to ask. The subsequent questions and requests from the user should be answered using the Perplexity API.

      If the user provides you with a question or request, run the function `perplexity_query(message, model)` to ask the user's question to the Perplexity API. The function requires two arguments: the message to be sent to the API and the model to be used.

      The `perplexity_query` function will return the response from the API in the following format:

      {"type"=>"text", "text"=>"The response from the API"}

      If errors occur during the process, handle them gracefully and inform the user of the issue showing the exact error message.

      Only if the user ask you for a response from a GPT model, you can directly answer the question without using the Perplexity API. Otherwise, use the Perplexity API to answer the user's questions. If you respond to the user without using the Perplexity API, make sure to mention that in your response. Also, if you have modified or translated the Perplexity API response, make sure to mention that in your response.

      Use the following format to present the response from the API:

      """

      response from `perplexity_query` here

      ---

      This is the response from **Anthropic** API (model: `MODEL_NAME`).

      """

      Do not enclose your response with """, ```, or <pre> tags.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Connect to Perplexity",
      "model": "gpt-3.5-turbo-0125",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": true,
      "tools": [
        { "type": "function",
          "function": {
            "name": "perplexity_query",
            "description": "A function to query the Perplexity API, requiring two arguments representing the message to be sent to the API and the model to be used.",
            "parameters": {
              "type": "object",
              "properties": {
                "message": {
                  "type": "string",
                  "description": "message to be sent to the API"
                },
                "model": {
                  "type": "string",
                  "description": "model to be used"
                }
              },
              "required": ["message", "model"]
            }
          }
        }, {
          "type": "function",
          "function": {
            "name": "check_settings",
            "description": "A function to check the settings of the Perplexity API."
          }
        }
      ]
    }
  end

  # def api_request(role, obj: nil, call_depth: 0, &block)
  # end

  def check_settings
    command = <<~CMD
      bash -c 'simple_perplexity_query.rb --check'
    CMD
    send_command(command: command, container: "ruby")
  end

  def perplexity_query(message: "", model: "sonar-medium-online")
    message = message.gsub('"', '\"')
    command = <<~CMD
      bash -c 'simple_perplexity_query.rb "#{message}" "#{model}"'
    CMD
    send_command(command: command, container: "ruby")
  end
end
