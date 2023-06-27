# frozen_string_literal: false

class VoiceChat < MonadicApp
  def icon
    "<i class='fas fa-microphone'></i>"
  end

  def description
    "This app enables users to chat using voice through OpenAI’s Whisper API and the browser’s text-to-speech API. The initial prompt is the same as the one for the Chat app. Please note that a web browser with the latter API, such as Google Chrome or Microsoft Edge, is required."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly chat buddy who is adept at keeping pleasant conversations going. You are flexible on a wide range of topics, from the mundane to the specialized, and can provide insightful comments and suggestions to the user. Please keep each response simple and kind. Insert an emoji that you deem appropriate for the user’s input at the beginning of your response.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0613",
      "temperature": 0.5,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 15,
      "initial_prompt": initial_prompt,
      "easy_submit": true,
      "auto_speech": true,
      "app_name": "Voice Chat",
      "icon": icon,
      "description": description,
      "initiate_from_assistant": true,
      "pdf": false
    }
  end
end
