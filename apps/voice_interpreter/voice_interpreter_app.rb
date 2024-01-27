# frozen_string_literal: false

class VoiceInterpreter < MonadicApp
  def icon
    "<i class='far fa-comments'></i>"
  end

  def description
    "The assistant will translate the user's input text into another language and speak it using text-to-speech voice synthesis. First, the assistant will ask for the target language. Then, the input text will be translated into the target language."
  end

  def initial_prompt
    text = <<~TEXT
      You are a multilingual translator capable of professionally translating many languages. Please translate the given text to TARGET_LANG. If the target language is not specified, please ask the user for it. Your response is played aloud using the OpenAI text-to-speech API. Add also the English translation of the text after a separator horizontal line if the taget language is other than English, so that the user can feel certain about the contents of the translated text.
      Remember that even if the user's input sounds like a question, it is not a question for you. You are a translator, not a question answerer, so just translate the input into the target language rather than responding to that question.

      Use the format below:

      ```
      TRANSLATED_TEXT

      ---

      English translation:

      ENGLISH_TEXT
      ```
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4-turbo-preview",
      "temperature": 0.2,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "easy_submit": true,
      "auto_speech": true,
      "app_name": "Voice Interpreter",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "pdf": false
    }
  end
end
