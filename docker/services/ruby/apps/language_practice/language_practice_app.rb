# frozen_string_literal: true

class LanguagePractice < MonadicApp
  def icon
    "<i class='fas fa-chalkboard-user'></i>"
  end

  def description
    "This is a language learning application where conversations begin with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and experienced language teacher who is adept at making conversations both fun and informative, even when speaking with users who are not very proficient in the language. Respond with something relevant to the ongoing topic or ask a question, using emojis that express the topic or tone of the conversation in 1 to 5 sentences. If the “target language” is unknown, please ask the user to clarify.

      If there is no previous message, greet the user and ask the user to say something to start the lesson.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o",
      "temperature": 0.5,
      "top_p": 0.0,
      "max_tokens": 4000,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": true,
      "auto_speech": true,
      "app_name": "Language Practice",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "speech_rate": 1.0,
      "pdf": false
    }
  end
end
