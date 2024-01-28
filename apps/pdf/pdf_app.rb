# frozen_string_literal: false

class PDF < MonadicApp
  def icon
    "<i class='fas fa-file-pdf'></i>"
  end

  def description
    <<~TEXT
      This is an application that reads a PDF file, and the assistant answers the user's questions based on its content. First, click on the "Upload PDF" button and specify the file. The content of the file will be divided into segments of approximately max_tokens length, and the text embedding will be calculated for each segment. When input is received from the user, the text segment that is closest to the text embedding value of the input text is given to GPT along with the user's input value, and an answer is generated based on that content.
    TEXT
  end

  def initial_prompt
    text = <<~TEXT
      Respond to the user based on the "text" property of the JSON object attached to the user input. The "text" value is an excerpt of a PDF uploaded by the user and may be accompanied by other properties containing metadata. In addition to your response based on the "text" property of the JSON, display the metadata contained in other properties such as "title" and "tokens" using this format: "(PDF Title: TITLE, Tokens of Snippet: TOKENS)".
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-1106",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 2,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "PDF Navigator",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": true
    }
  end
end
