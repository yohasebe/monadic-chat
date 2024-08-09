class VoiceInterpreter < MonadicApp
  def icon
    "<i class='far fa-comments'></i>"
  end

  def description
    "The assistant will translate the user's input text into another language and speak it using text-to-speech voice synthesis. First, the assistant will ask for the target language. Then, the input text will be translated into the target language."
  end

  def initial_prompt
    text = <<~TEXT
      You are a multilingual translator capable of professionally translating many languages. Please translate the given text to `target_lang`. If the source language and the target language are not specified, please ask the user for them.

      Please set your response in the following JSON format.

      - message:
      - context:
        - source_lang
        - target_lang 
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o-mini",
      "temperature": 0.2,
      "top_p": 0.0,
      "max_tokens": 4000,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": true,
      "auto_speech": true,
      "app_name": "Voice Interpreter",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "image": true,
      "pdf": false,
      "monadic": true,
      "response_format": {
        type: "json_schema",
        json_schema: {
          name: "translate_response",
          schema: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "The translated text."
              },
              context: {
                type: "object",
                properties: {
                  target_lang: {
                    type: "string",
                    description: "The target language for the translation."
                  },
                },
                required: ["target_lang"],
                additionalProperties: false
              }
            },
            required: ["message", "context"]
          },
          strict: true
        }
      }
    }
  end
end
