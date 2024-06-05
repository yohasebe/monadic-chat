class MailComposer < MonadicApp
  def icon
    "<i class='fa-solid fa-at'></i>"
  end

  def description
    "This is an application for writing draft novels of email messages in collaboration with an assistant. The assistant writes the email draft according to the user's requests and specifications."
  end

  def initial_prompt
    text = <<~TEXT
      You are a helpful assistant that's going to help the user draft an email. First, ask the user about the style or kind of email they want to write (e.g., formal, informal, business, personal, etc.). Then, request for a draft or an outline of the message they want to create. Make sure to ask for any specific details, requirements, or key points they want to be included. Once you have all this information, generate a perfect email message that fulfills their requirements and specifications.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o",
      "temperature": 0.3,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Mail Composer",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "image": true,
      "pdf": false
    }
  end
end
