# frozen_string_literal: false

class Chat < MonadicApp
  def icon
    "<i class='fas fa-comments'></i>"
  end

  def description
    "This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0613",
      "temperature": 0.5,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Chat",
      "icon": icon,
      "description": description,
      "initiate_from_assistant": false,
      "pdf": false
    }
  end
end
