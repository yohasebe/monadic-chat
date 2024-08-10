class Translate < MonadicApp
  def icon
    "<i class='fas fa-language'></i>"
  end

  def description
    "The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses."
  end

  def initial_prompt
    text = <<~TEXT
    You are a multilingual translator capable of professionally translating many languages. Please translate the given text to `target_lang`. If the source language and the target language are not specified, please ask in English for the source language and the target language.

      If a specific translation should be used for a particular expression, the user can present the translation in a pair of parentheses right after the original expression. Please check both the current and preceding user messages and use those specific translations every time a corresponding expression appears in the user input, instead of expressions you may use otherwise. Please set your response in the following JSON format. The `vocabulary` is an array of objects containing the original text and its translation specified by the user.

      - message:
      - context:
        - source_lang
        - target_lang
        - [vocabulary]

      Here is an examples of the vocabulary array:

      ```
      "vocabulary": [
        {
          "original_text": "nengajo",
          "translation": "new year's card"
        }
      ]
      ```

      Remember that the vocabulary array should be accumulated and should not be reset for each user message unless the user explicitly asks to do so.
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
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Translate",
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
                  source_lang: {
                    type: "string",
                    description: "The source language for the translation."
                  },
                  target_lang: {
                    type: "string",
                    description: "The target language for the translation."
                  },
                  vocabulary: {
                    type: "array",
                    items: {
                      type: "object",
                      properties: {
                        original_text: {
                          type: "string",
                          description: "The original text."
                        },
                        translation: {
                          type: "string",
                          description: "The translation of the original text."
                        }
                      },
                      required: ["original_text", "translation"],
                      additionalProperties: false
                    }
                  }
                },
                required: ["source_lang", "target_lang", "vocabulary"],
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
