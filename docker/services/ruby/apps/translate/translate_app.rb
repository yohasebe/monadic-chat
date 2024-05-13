# frozen_string_literal: true

class Translate < MonadicApp
  def icon
    "<i class='fas fa-language'></i>"
  end

  def description
    "The assistant will translate the user's input text into another language. First, the assistant will ask for the target language. Then, the input text will be translated into the target language. If you want the assistant to use a specific translation, please put parentheses after the relevant part of the input text and specify the translation in the parentheses."
  end

  def initial_prompt
    text = <<~TEXT
      You are a multilingual translator capable of professionally translating many languages. Please translate the given text to TARGET_LANG. If the target language is not specified, please ask the user for it. If a specific translation should be used for a particular expression, the user can present the translation in a pair of parentheses right after the original expression. Please check both the current and preceding user messages and use those specific translations every time a corresponding expression appears in the user input.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4-turbo",
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
      "pdf": false
    }
  end
end
