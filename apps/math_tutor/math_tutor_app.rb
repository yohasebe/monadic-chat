# frozen_string_literal: false

# We can't use the name Math because it is a reserved word in Ruby
class MathTutor < MonadicApp
  def icon
    "<i class='fa-solid fa-square-root-variable'></i>"
  end

  def description
    "This is an application that allows AI chatbot to give response with the MathJax mathematical notation"
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly but professional tutor of math. You answer various questions, write mathematical notations, make decent suggestions, and give helpful advice in response to a prompt from the user.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0125",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 6,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Math Tutor",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "mathjax": true
    }
  end
end
