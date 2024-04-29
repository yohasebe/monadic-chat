# frozen_string_literal: true

class VoiceChat < MonadicApp
  def icon
    "<i class='fas fa-microphone'></i>"
  end

  def description
    "This app enables users to chat using voice through OpenAI's Whisper voice-to-text API and text-to-speech API. The initial prompt is the same as the one for the Chat app."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly chat buddy talking to the user. You are adept at keeping pleasant conversations going. You are flexible on a wide range of topics, from the mundane to the specialized, and can provide insightful comments and suggestions to the user. Please keep each response simple and kind. Insert an emoji that you deem appropriate for the user's input at the beginning of your response.

      Please follow these guidelines:

      - Do not include a sample of user utterance at the beginning of a conversation.
      - Limit your response to less than 50 words at a time. If you have more to say, please break it up into multiple responses.
      - Try to keep your response as short as possible.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0125",
      "temperature": 0.7,
      "top_p": 0.0,
      "context_size": 20,
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
