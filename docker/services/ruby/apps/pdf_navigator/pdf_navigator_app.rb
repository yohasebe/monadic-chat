class PDFNavigator < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-file-pdf'></i>"

  description = <<~TEXT
  This is an application that reads PDF files, and the assistant answers the user's questions based on their contents. Click on the "Upload PDF" button and specify the file. <a href='https://yohasebe.github.io/monadic-chat/#/basic-apps?id=pdf-navigator' target='_blank'><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are an agent to assist users in navigating PDF documents contained in the database. According to the user's input, you provide information based on the contents of the text snippets in the database.

    Respond to the user based on the "text" property of the JSON object returned by the function "find_closest_text". The function takes parameter "text" and "top_n" (number of closest text snippets to return). The input text is used to find the closest text snippet in the database. The text is converted to a text embedding to find the closest text snippet in the database. The function returns an array of JSON objects in the following format. The recommended value of "top_n" is 2.

      [{
        text: text snippet from the document
        doc_id: document id
        doc_title: document title
        position: positional order of the text snippet within the document
        total_items: total number of text snippets of the same document id
        metadata: {
          tokens: number of tokens in the text snippet
        }
      }]

    Present your response in the following format:

      YOUR_RESPONSE

      ---

      Doc ID: doc_id
      Doc Title: doc_title
      Snippet tokens: tokens
      Snippet position: position/total_items

    If the user requests a text snippet in a specific position, you can use the function "get_text_snippet" with the parameters "doc_id" and "position" to retrieve the text snippet.

    Please make sure that if your response does not have a particular reference to a text snippet, you shouldn't include every property in the JSON object. Only include the properties that are relevant to the response.
  TEXT

  @settings = {
    model: "gpt-4o-2024-11-20",
    temperature: 0.0,
    top_p: 0.0,
    max_tokens: 4000,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "PDF Navigator",
    description: description,
    icon: icon,
    initiate_from_assistant: false,
    pdf: true,
    image: true,
    mathjax: true,
    tools: [
      {
        type: "function",
        function: {
          name: "find_closest_text",
          description: "Find the closest text in the database based on the input text",
          parameters: {
            type: "object",
            properties: {
              text: {
                type: "string",
                description: "The input text"
              },
              top_n: {
                type: "integer",
                description: "The number of closest text snippets to return"
              }
            },
            required: ["text", "top_n"]
          }
        },
        strict: true
      },
      {
        type: "function",
        function: {
          name: "get_text_snippet",
          description: "Retrieve the text snippet from the database",
          parameters: {
            type: "object",
            properties: {
              doc_id: {
                type: "integer",
                description: "The document id"
              },
              position: {
                type: "integer",
                description: "The position of the text snippet within the document"
              }
            },
            required: ["doc_id", "position"]
          }
        },
        strict: true
      },
      {
        type: "function",
        function: {
          name: "list_titles",
          description: "List objects of the doc id and the title value from the docs table",
          parameters: {},
          required: []
        },
        strict: true
      },
      {
        type: "function",
        function: {
          name: "find_closest_doc",
          description: "Get the embedding of the input text and find the closest doc in the database",
          parameters: {
            type: "object",
            properties: {
              text: {
                type: "string",
                description: "The input text"
              },
              top_n: {
                type: "integer",
                description: "The number of closest documents to return"
              }
            },
            required: ["text", "top_n"]
          }
        },
        strict: true
      },
      {
        type: "function",
        function: {
          name: "get_text_snippets",
          description: "Retrieve all the text snippets of a document from the database",
          parameters: {
            type: "object",
            properties: {
              doc_id: {
                type: "integer",
                description: "The document id"
              }
            },
            required: ["doc_id"]
          }
        },
        strict: true
      }
    ]
  }
end
