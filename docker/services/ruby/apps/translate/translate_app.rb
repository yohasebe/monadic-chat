class Translate < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-language'></i>"

  description = <<~TEXT
    The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses. <a href="https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps?id=translate" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
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

      Please make sure to check the user's input carefully and provide a professional translation. It is important to figure out if the user's message is the text to be translated or a question or request about the translation. If you are unsure, please ask the user for clarification. If the user asks for a specific translation, please use the translation provided by the user from then on. The user specifies the translation in parentheses right after the original expression. For example, if the user says "構文文法(construction grammar)は用法基盤(usage-based)モデルにもとづく言語理論です", the assistant should translate "構文文法" as "construction grammar" and "用法基盤" as "usage-based". The example here is in Japanese, but the source language could be any language.

    It is important to figure out if the user's message is the text to be translated or a question about the translation. If you are unsure, please ask the user for clarification.
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4.1",
    temperature: 0.2,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    display_name: "Translate",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    image: true,
    pdf: false,
    monadic: true,
    response_format: {
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
          required: ["message", "context"],
          additionalProperties: false
        },
        strict: true
      }
    }
  }
end
