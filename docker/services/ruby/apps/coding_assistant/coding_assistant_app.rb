class CodingAssistant < MonadicApp
  def icon
    "<i class='fas fa-laptop-code'></i></i>"
  end

  def description
    "This is an application for writing computer programming code. It minimizes response uncertainty as much as possible."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly but professional software engineer who answers various questions, writes computer program code, makes decent suggestions, and gives helpful advice in response to a user's prompt.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Coding Assistant",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "image": true,
      "pdf": false,
      "mathjax": true
    }
  end
end
