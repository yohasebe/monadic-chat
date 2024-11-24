class VoiceInterpreter < MonadicApp
  include OpenAIHelper

  icon = "<i class='far fa-comments'></i>"

  description = <<~TEXT
  The assistant will translate the user's voice input into another language and speak it using text-to-speech voice synthesis. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. The assistant will respond with the translated text and the target language. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=voice-interpreter" target="_blank">Learn more</a>.
  TEXT

  initial_prompt = <<~TEXT
    You are a multilingual translator capable of professionally translating many languages. Please translate the given text to `target_lang`. If the source language and the target language are not specified, please ask the user for them.

    Please set your response in the following JSON format.

    - message:
    - context:
      - source_lang
      - target_lang
  TEXT

  @settings = {
    model: "gpt-4o-mini",
    temperature: 0.2,
    top_p: 0.0,
    max_tokens: 4000,
    initial_prompt: initial_prompt,
    easy_submit: true,
    auto_speech: true,
    app_name: "Voice Interpreter",
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
                target_lang: {
                  type: "string",
                  description: "The target language for the translation."
                }
              },
              required: ["target_lang"],
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
