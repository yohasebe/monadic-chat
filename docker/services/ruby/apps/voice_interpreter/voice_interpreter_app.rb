class VoiceInterpreter < MonadicApp
  include OpenAIHelper

  icon = "<i class='far fa-comments'></i>"

  description = <<~TEXT
    The assistant will translate the user's voice input into another language and speak it using text-to-speech voice synthesis. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. The assistant will respond with the translated text and the target language. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=voice-interpreter" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a multilingual translator capable of professionally translating many languages. Please translate the given text to the target language. 
    
    Always use English when asking the user questions about setup. If the source language and the target language are not specified, please ask the user for them in English. After translation setup is complete, your translations should be accurate to the target language.

    VERY IMPORTANT: 
    1. Provide ONLY the direct translation without any explanatory text, preamble, or phrases like "I'll translate this..." or "Here's the translation..."
    2. When source_lang and target_lang have been established, keep using them for subsequent translations unless the user explicitly asks to change them
    3. Your message should contain ONLY the translated text, nothing else

    Please set your response in the following JSON format.

    - message: [DIRECT TRANSLATION ONLY, NO PREAMBLE]
    - context:
      - source_lang
      - target_lang
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4.1",
    temperature: 0.0,
    initial_prompt: initial_prompt,
    easy_submit: true,
    auto_speech: true,
    display_name: "Voice Interpreter",
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
              description: "ONLY the translated text with NO preamble, explanation, or meta-commentary."
            },
            context: {
              type: "object",
              properties: {
                source_lang: {
                  type: "string",
                  description: "The source language of the original text. Once established, maintain this for the entire conversation unless explicitly changed."
                },
                target_lang: {
                  type: "string",
                  description: "The target language for the translation. Once established, maintain this for the entire conversation unless explicitly changed."
                }
              },
              required: ["source_lang", "target_lang"],
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
