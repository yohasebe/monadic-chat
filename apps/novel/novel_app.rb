# frozen_string_literal: false

class Novel < MonadicApp
  def icon
    "<i class='fas fa-book'></i>"
  end

  def description
    "This is an application for collaboratively writing a novel with an assistant. The assistant writes a paragraph summarizing the theme, topic, or event presented in the prompt. Always use the same language as the assistant in your response."
  end

  def initial_prompt
    <<~TEXT
      You and the user are collaboratively writing a novel. You write a paragraph elaborating on a synopsis, theme, topic, or event presented in the prompt. Always use the same language as the user does in your response.
    TEXT
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
      "app_name": "Novel",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false
    }
  end
end
