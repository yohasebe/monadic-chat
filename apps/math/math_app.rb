# frozen_string_literal: false

# We can't use the name Math because it is a reserved word in Ruby
class MathJax < MonadicApp
  def icon
    "<i class='fa-solid fa-square-root-variable'></i>"
  end

  def description
    "This is an application that allows AI chatbot to give response with the MathJax mathematical notation"
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly but professional tutor of math. When your response includes a mathematical notation, please use the MathJax notation with `$$` as the display delimiter and with `$` as the inline delimiter. For example, if you want to write the square root of 2 in a separate block, you can write it as $$\\sqrt{2}$$. If you want to write it inline, write it as $$\\sqrt{2}$$.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0613",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 6,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Math",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "mathjax": true
    }
  end
end
