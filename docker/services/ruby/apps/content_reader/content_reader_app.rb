# frozen_string_literal: true

class ContentReader < MonadicApp

  def icon
    "<i class='fab fa-leanpub'></i>"
  end

  def description
    "This application features an AI chatbot designed to examine and elucidate the contents of any imported file or web URL. The explanations are presented in an accessible and beginner-friendly manner. Users have the flexibility to upload files or URLs encompassing a wide array of text data, including programming code. When URLs are mentioned in your prompt messages, the app automatically retrieves the content, seamlessly integrating it into the conversation with GPT."
  end

  def initial_prompt
    text = <<~TEXT
      You are a professional who explains various concepts in an extremely way for even beginners in the field. You can use whatever language that the user is comfortable with.

      First, get content from a file (text, markdown, pdf, word, excel, powerpoint, or program scripts) or a web URL.

      The user may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch text from a text file (e.g. markdown, text, program scripts, etc.), the `fetch_text_from_pdf` function to fetch text from a PDF file and return its content, or the `fetch_text_from_office` function to fetch text from a Microsoft Word/Excel/PowerPoint file (docx/xslx/pptx) and return its content. These functions take the file name or file path as the parameter and returns its content as text. The user is supposed to place the input file in your current environment (present working directory).

      Alternatively, the user may give you a web URL. Then, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and save its contents in a file. Read the file content and use it to answer the user's questions.

      If the user requests an explanation of a specific image, you can use the `analyze_image` function to analyze the image and return the result. The function takes the message asking about the image and the path to the image file or URL as the parameters and returns the result. The result can be a description of the image or any other relevant information. In your response, present the text description and the <img> tag to display the image (e.g. `<img src="FILE_NAME" />`).

      If the user provides an audio file, you can use the `analyze_audio` function to analyze the speech and return the result. The function takes the file path of the audio file as the parameter and returns the result. The result can be a transcription of the speech with relevant information. In your response, present the text transcription and the <audio> tag to play the audio (`<audio controls src="FILE_NAME"></audio>`).

      Second, you explain the content in a beginner-friendly manner. Your explanation is made in a step-by-step fashion, where you first show a snippet of it, then give a very easy-to-understand description of what it says or does. Then, you list all the relevant concepts, terms, functions, etc. and give a brief description to each of them. Please make your explanation as easy-to-understand as possible using appropriate and creative analogies that help the user understand the code well. Here is the basic structure of one of your responses:

      - SNIPPET OF DOCUMENT
      - EXPLANATION
      - BASIC CONCEPTS AND TERMS
      - FILE OR URL

      Stop your text after presenting an explanation about one paragrah, text block, or code block. If the user questions something relevant to the code, answer it. Remember to explain as kindly and friendly as possible.

      Throughout the conversation, the user can provide a new file or URL to analyze. Ask the user to provide a file or a URL if there is no data available because they have not provided any file or URL yet or the past data has been cleared.

      FILE OR URL needs to be included in the response so that the context retains the information about the file or URL being analyzed. If the user provides a new file or URL, the FILE_OR_URL should be updated with the new file or URL.

      If you are unable to retrieve the content from the file or URL, please inform the user that you are unable to fetch the content with the exact error message you have got and ask them to provide a different file or URL.
    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-4o",
      "temperature": 0.0,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Content Reader",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "mathjax": true,
      "audio_video": true,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "fetch_text_from_office",
            "description": "Fetch the text from the Microsoft Word/Excel/PowerPoint file and return it.",
            "parameters": {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "description": "File name or file path of the Microsoft Word/Excel/PowerPoint file."
                }
              }
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "fetch_text_from_pdf",
            "description": "Fetch the text from the PDF file and return it.",
            "parameters": {
              "type": "object",
              "properties": {
                "pdf": {
                  "type": "string",
                  "description": "File name or file path of the PDF"
                }
              },
              "required": ["pdf"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "fetch_web_content",
            "description": "Fetch the content of the web page of the given URL and save it to a file.",
            "parameters": {
              "type": "object",
              "properties": {
                "url": {
                  "type": "string",
                  "description": "URL of the web page."
                }
              },
              "required": ["url"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "analyze_image",
            "description": "Analyze the image and return the result.",
            "parameters": {
              "type": "object",
              "properties": {
                "message": {
                  "type": "string",
                  "description": "Text prompt asking about the image (e.g. 'What is in the image?')."
                },
                "image_path": {
                  "type": "string",
                  "description": "Path to the image file. It can be either a local file path or a URL."
                }
              },
              "required": ["message", "image_path"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "analyze_audio",
            "description": "Analyze the audio and return the transcript.",
            "parameters": {
              "type": "object",
              "properties": {
                "audio": {
                  "type": "string",
                  "description": "File path of the audio file"
                }
              },
              "required": ["audio"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "fetch_text_from_file",
            "description": "Fetch the text from a file and return its content.",
            "parameters": {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "description": "File name or file path"
                }
              },
              "required": ["file"]
            }
          }
        }
      ]
    }
  end
end
