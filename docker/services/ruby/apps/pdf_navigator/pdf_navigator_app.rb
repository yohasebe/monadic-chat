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

      Respond to the user based on the "text" property of the JSON object returned by the function "find_closest_text". The function takes a single parameter "text" and the text is converted to a text embedding to find the closest text snippet in the database. The function returns the following JSON object:

        {
          text: text snippet from the document
          doc_id: document id
          doc_title: document title
          position: positional order of the text snippet within the document
          total_items: total number of text snippets of the same document id
          metadata: {
            tokens: number of tokens in the text snippet
          }
        }

      Present your response in the following format:

        YOUR_RESPONSE

        ---

        Doc ID: doc_id
        Doc Title: doc_title
        Snippet tokens: tokens
        Snippet position: position/total_items

      If the user requests a text snippet in a specific position, you can use the function "get_text_snippet" with the parameters "doc_id" and "position" to retrieve the text snippet.

      Please make sure that if your response does not have a particular reference to a text snippet, you should not include every property in the JSON object. Only include the properties that are relevant to the response.
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
        },
        {
          "type": "function",
          "function": {
            "name": "get_text_snippet",
            "description": "Retrieve the text snippet from the database",
            "parameters": {
              "type": "object",
              "properties": {
                "doc_id": {
                  "type": "integer",
                  "description": "The document id"
                },
                "position": {
                  "type": "integer",
                  "description": "The position of the text snippet within the document"
                }
              },
              "required": ["doc_id", "position"]
            }
          },
          "strict": true
        }
      ]
    }
  end
end
