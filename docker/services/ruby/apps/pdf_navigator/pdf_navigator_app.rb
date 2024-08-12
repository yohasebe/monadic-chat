class PDFNavigator < MonadicApp
  def icon
    "<i class='fas fa-file-pdf'></i>"
  end

  def description
    <<~TEXT
      This is an application that reads a PDF file, and the assistant answers the user's questions based on its content. First, click on the "Upload PDF" button and specify the file. The content of the file will be divided into segments of approximately max_tokens length, and the text embedding will be calculated for each segment. When input is received from the user, the text segment closest to the text embedding value of the input text is given to GPT along with the user's input value, and an answer is generated based on that content.
    TEXT
  end

  def initial_prompt
    text = <<~TEXT
      You are an agent to assist users in navigating PDF documents contained in the database. According to the user's input, you provide information based on the content of the text snippets in the database.

      Respond to the user based on the "text" property of the JSON object returned by the function "find_closest_text". The function takes a single parameter "text" and returns a JSON object of the following structure:

        {
          doc_id: document id
          text: text snippet from the document
          metadata: {
            total_entries: total number of text snippets of the same document id
            title: title of the document
            position: positional order of the text snippet within the document
            tokens: number of tokens in the text snippet
          }
        }

      containing "text" which is a snippet from a PDF in the database highly relevant to the input text, the "title" of the PDF that the snippet is part of, and "tokens" representing the number of tokens that the text snippet contains.

      Present your response in the following format:

        YOUR_RESPONSE

        Title: TITLE (Snippet tokens: TOKENS, Snippet position: POSITION/TOTAL_ENTRIES)
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o-2024-08-06",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 4000,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "PDF Navigator",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": true,
      "image": true,
      "mathjax": true,
      "tools": [
        {
          "type": "function",
          "function": {
            "name": "find_closest_text",
            "description": "Find the closest text in the database based on the input text",
            "parameters": {
              "type": "object",
              "properties": {
                "text": {
                  "type": "string",
                  "description": "The input text"
                }
              },
              "required": ["text"]
            }
          },
          "strict": true
        }
      ]
    }
  end
end
