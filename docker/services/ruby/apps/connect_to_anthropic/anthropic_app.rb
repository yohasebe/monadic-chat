# frozen_string_literal: true

class Anthropic < MonadicApp
  def icon
    "<i class='fa-solid fa-a'></i>"
  end

  def description
    "This app accesses the Anthropic API to answer questions about a wide range of topics."
  end

  def initial_prompt
    text = <<~TEXT
      You have access to the Anthropic API to answer questions about a wide range of topics through the function `anthropic_query(message, model)`, which is available in your environment.

      First, run `check_settings` to verify the settings of the Anthropic API. The function will return the response in the following format:

      { API_KEY: true, MODEL: MODEL_NAME}

      If the API key is not set, tell the user to set the API key to the `.env` file. And if the model is not set, ask the user which Anthropic model they would like to use. The user can choose from the following models:

      - Claude 3 Opus: `claude-3-opus-20240229`
      - Claude 3 Sonnet: `claude-3-sonnet-20240229`
      - Claude 3 Haiku: `claude-3-haiku-20240307`

      Of course, if `check_settings` returns a model name, use that model to answer the user's questions. If the model is not set, use the default model `claude-3-haiku-20240307`.

      If the API is set and the model is decided, ask the user to provide the question they would like to ask. The subsequent questions and requests from the user should be answered using the Anthropic API.

      If the user provides you with a question or request, run the function `anthropic_query(message, model)` to ask the user's question to the Anthropic API. The function requires two arguments: the message to be sent to the API and the model to be used. The model name should start with `claude-3-`.

      The `anthropic_query` function will return the response from the API in the following format:

      {"type"=>"text", "text"=>"The response from the API"}

      If errors occur during the process, handle them gracefully and inform the user of the issue showing the exact error message.

      Only if the user ask you for a response from a GPT model, you can directly answer the question without using the Anthropic API. Otherwise, use the Anthropic API to answer the user's questions. If you respond to the user without using the Anthropic API, make sure to mention that in your response.

      Use the following format to present the response from the API:

      """

      RESPONSE FROM API HERE

      ---

      Above is the response from **Anthropic** API (model: `MODEL_NAME`).

      """

      Do not add the delimiter """ or ``` in the response from the API. The delimiter is only used to show the format of the response.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Connect to Anthropic",
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
            "name": "anthropic_query",
            "description": "A function to query the Anthropic API, requiring two arguments representing the message to be sent to the API and the model to be used.",
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
            "description": "A function to check the settings of the Anthropic API."
          }
        }
      ]
    }
  end

  def check_settings
    command = <<~CMD
      bash -c 'simple_anthropic_query.rb --check'
    CMD
    send_command(command: command, container: "ruby")
  end

  def anthropic_query(message: "", model: "claude-3-haiku-20240307")
    message = message.gsub('"', '\"')
    command = <<~CMD
      bash -c 'simple_anthropic_query.rb "#{message}" "#{model}"'
    CMD
    send_command(command: command, container: "ruby")
  end
end
