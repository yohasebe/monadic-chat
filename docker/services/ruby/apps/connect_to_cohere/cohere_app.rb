# frozen_string_literal: true

class Cohere < MonadicApp
  def icon
    "<i class='fa-solid fa-a'></i>"
  end

  def description
    "This app accesses the Cohere API to answer questions about a wide range of topics."
  end

  def initial_prompt
    text = <<~TEXT
      You have access to the Cohere API to answer questions about a wide range of topics through the function `cohere_query(message, model)`, which is available in your environment.

      First, run `check_settings` to verify the settings of the Cohere API. The function will return the response in the following format:

      { API_KEY: true, MODEL: MODEL_NAME}

      If the API key is not set, tell the user to set the API key to the `.env` file. And if the model is not set, ask the user which Cohere model they would like to use. The user can choose from the following models:

      - `command`
      - `command-light`
      - `command-r`
      - `command-r-plus`

      Of course, if `check_settings` returns a model name, use that model to answer the user's questions. If the model is not set, use the default model `command-r`.

      If the API is set and the model is decided, ask the user to provide the question they would like to ask. The subsequent questions and requests from the user should be answered using the Cohere API.

      If the user provides you with a question or request, run the function `cohere_query(message, model)` to ask the user's question to the Cohere API. The function requires two arguments: the message to be sent to the API and the model to be used.

      You can modify the user's message so that it is optimized for the API. You can also add additional context to the message if you think it will help the API provide a better response. Use the language that the user used in their question in modiying the prompt you send to the API.

      The `cohere_query` function will return the response from the API in the following format:

      {"type"=>"text", "text"=>"The response from the API"}

      Please show the response to the user in the following format:

      """
      RESPONSE_FROM_API

      ---

      Above is the response from **Cohere** API (model: `MODEL_NAME`).
      """

      If errors occur during the process, handle them gracefully and inform the user of the issue showing the exact error message.

      Only if the user ask you for a response from a GPT model, you can directly answer the question without using the Cohere API. Otherwise, use the Cohere API to answer the user's questions. If you respond to the user without using the Cohere API, make sure to mention that in your response.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Connect to Cohere API",
      "model": "gpt-4-0125-preview",
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
            "name": "cohere_query",
            "description": "A function to query the Cohere API, requiring two arguments representing the message to be sent to the API and the model to be used.",
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
            "description": "A function to check the settings of the Cohere API."
          }
        }
      ]
    }
  end

  def check_settings
    command = <<~CMD
      bash -c 'simple_cohere_query.rb --check'
    CMD
    send_command(command: command, container: "ruby")
  end

  def cohere_query(message: "", model: "claude-3-haiku-20240307")
    message = message.gsub('"', '\"')
    command = <<~CMD
      bash -c 'simple_cohere_query.rb "#{message}" "#{model}"'
    CMD
    send_command(command: command, container: "ruby")
  end
end
