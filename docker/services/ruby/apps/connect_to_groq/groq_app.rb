# frozen_string_literal: true

class Groq < MonadicApp
  def icon
    "<i class='fa-solid fa-g'></i>"
  end

  def description
    "This app accesses the Groq API to answer questions about a wide range of topics."
  end

  def initial_prompt
    text = <<~TEXT
      You have access to the Groq API to answer questions about a wide range of topics through the function `groq_query(message, model)`, which is available in your environment.

      First, run `check_settings` to verify the settings of the Groq API. The function will return the response in the following format:

      { API_KEY: true, MODEL: MODEL_NAME}

      If the API key is not set, tell the user to set the API key to the `.env` file. And if the model is not set, ask the user which Groq model they would like to use. The user can choose from the following models:

      - `llama2-70b-4096`
      - `mixtral-8x7b-32768`
      - `gemma-7b-it`

      Of course, if `check_settings` returns a model name, use that model to answer the user's questions. If the model is not set, use the default model `llama2-70b-4096`.

      If the API is set and the model is decided, ask the user to provide the question they would like to ask. The subsequent questions and requests from the user should be answered using the Groq API.

      If the user provides you with a question or request, run the function `groq_query(message, model)` to ask the user's question to the Groq API. The function requires two arguments: the message to be sent to the API and the model to be used. The model name should start with `claude-3-`.

      The `groq_query` function will return the response from the API in the following format:

      {"type"=>"text", "text"=>"The response from the API"}

      If errors occur during the process, handle them gracefully and inform the user of the issue showing the exact error message.

      Only if the user ask you for a response from a GPT model, you can directly answer the question without using the Groq API. Otherwise, use the Groq API to answer the user's questions. If you respond to the user without using the Groq API, make sure to mention that in your response.

      Use the following format to present the response from the API:

      ```

      RESPONSE FROM API HERE

      ---

      Above is the response from **Anthropic** API (model: `MODEL_NAME`).

      ```

      Do not include the delimiter \`\`\` in the response from the API. The delimiter is only used to show the format of the response.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Connect to Groq",
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
            "name": "groq_query",
            "description": "A function to query the Groq API, requiring two arguments representing the message to be sent to the API and the model to be used.",
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
            "description": "A function to check the settings of the Groq API."
          }
        }
      ]
    }
  end

  def check_settings
    command = <<~CMD
      bash -c 'simple_groq_query.rb --check'
    CMD
    send_command(command: command, container: "ruby")
  end

  def groq_query(message: "", model: "llama2-70b-4096")
    message = message.gsub('"', '\"')
    command = <<~CMD
      bash -c 'simple_groq_query.rb "#{message}" "#{model}"'
    CMD
    send_command(command: command, container: "ruby")
  end
end
