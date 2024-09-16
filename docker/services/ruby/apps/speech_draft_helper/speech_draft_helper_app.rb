class SpeechDraftHelper < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-user-tie'></i>"

  description = <<~TEXT
    This app allows the user to submit a speech draft in the form of just a text string, a Word file, or a PDF file. The app will then analyze it and return a revised version. The app will also provide suggestions for improvement and tips on how to make the speech more engaging and effective if the user needs them. if the user needs them Besides, it can also provide an mp3 file of the speech.
  TEXT

  initial_prompt = <<~TEXT
    You are a speech draft helper assistant. You can help users with their speech drafts. Users can submit a speech draft in the form of a text string, a Word file, or a PDF file. You can analyze the speech and provide a revised version of the draft. You also provide feedback on its content, structure, and delivery if the user needs them. You can also provide suggestions for improvement and tips on how to make the speech more engaging and effective.

    If the user asks for it, you can provide an MP3 file of the speech according to their requirements: speed, voice, and language. The user can choose the voice from `alloy`, `echo`, `fable`, `onyx`, `nova`, or `shimmer`. The default voice is `alloy`. Let the user know about these options in your first message for the user.

    First, get a speech draft or idea from the user. The user may give you a text segment in their message, or they may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch text from a text file (e.g., markdown, text, program scripts, etc.), the `fetch_text_from_pdf` function to fetch text from a PDF file and return its content, or the `fetch_text_from_office` function to fetch text from a Microsoft Word/Excel/PowerPoint file (docx/xslx/pptx) and return its content. These functions take the file name or file path as the parameter and return its content as text. The user is supposed to place the input file in your current environment (present working directory).

    Alternatively, the user may give you a web URL. Then, please fetch the content of the web page using the `fetch_web_content` function. The function takes the web page URL as the parameter and saves its contents in a file. Read the file content and use it to answer the user's questions.

    If the user requests an explanation of a specific image, you can use the `analyze_image` function to analyze the image and return the result. The function takes the message asking about the image and the path to the image file or URL as the parameters and returns the result. The result can be a description of the image or any other relevant information. In your response, present the text description and the <img> tag to display the image (e.g. `<img src="FILE_NAME" />`).

    If the user provides an audio file, you can use the `analyze_audio` function to analyze the speech and return the result. The function takes the audio file path as the parameter and returns the result. The result can be a transcription of the speech with relevant information. In your response, present the text transcription and the <audio> tag to play the audio (`<audio controls src="FILE_NAME"></audio>`).

    Once you have received the speech draft, analyze it and provide a revised version of the draft. You can provide feedback on its content, structure, and delivery.

    If the user requests for it, provide an MP3 file of the speech. You can use the `text_to_speech` tool to provide an MP3 file of the speech. The tool takes the speech text and other parameters and returns the filename of the MP3 file of the speech. Here are the parameters you can use:

    - `text`: The speech text to convert to speech.
    - `speed`: Speed of the speech. The default is 1.0.
    - `voice`: Voice of the speech. For male voices, you can use 'alloy', 'echo', 'fable', or 'onyx'. For female voices, you can use 'nova' or 'shimmer'. The default is 'alloy'.
    - `language`: Language of the speech in the format "en", "es", “ja”, etc. The default is 'auto'.

    If you have generated an MP3, present it using the <audio> tag to play the audio (`<audio controls src="FILE_NAME"></audio>`).
  TEXT

  @settings = {
    model: "gpt-4o-2024-08-06",
    temperature: 0.0,
    top_p: 0.0,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Speech Draft Helper",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    image: true,
    tools: [
      {
        type: "function",
        function:
        {
          name: "fetch_text_from_office",
          description: "Fetch the text from the Microsoft Word/Excel/PowerPoint file and return it.",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "File name or file path of the Microsoft Word/Excel/PowerPoint file."
              }
            },
            required: ["file"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "fetch_text_from_pdf",
          description: "Fetch the text from the PDF file and return it.",
          parameters: {
            type: "object",
            properties: {
              pdf: {
                type: "string",
                description: "File name or file path of the PDF"
              }
            },
            required: ["pdf"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "fetch_web_content",
          description: "Fetch the content of the web page of the given URL and save it to a file.",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "URL of the web page."
              }
            },
            required: ["url"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "analyze_image",
          description: "Analyze the image and return the result.",
          parameters: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "Text prompt asking about the image (e.g. 'What is in the image?')."
              },
              image_path: {
                type: "string",
                description: "Path to the image file. It can be either a local file path or a URL."
              }
            },
            required: ["message", "image_path"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "analyze_audio",
          description: "Analyze the audio and return the transcript.",
          parameters: {
            type: "object",
            properties: {
              audio: {
                type: "string",
                description: "File path of the audio file"
              }
            },
            required: ["audio"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "fetch_text_from_file",
          description: "Fetch the text from a file and return its content.",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "File name or file path"
              }
            },
            required: ["file"]
          }
        }
      },
      {
        type: "function",
        function:
        {
          name: "text_to_speech",
          description: "Convert the text to speech to generate an MP3 file and retrun the filename.",
          parameters: {
            type: "object",
            properties: {
              text: {
                type: "string",
                description: "Text to convert to speech."
              },
              speed: {
                type: "string",
                description: "Speed of the speech. Default is 1.0."
              },
              voice: {
                type: "string",
                enum: ["alloy", "echo", "fable", "onyx", "nova", "shimmer"],
                description: "Voice of the speech. Default is 'alloy'."
              },
              language: {
                type: "string",
                description: "Language of the speech. Default is 'auto'."
              }
            },
            required: ["text"]
          }
        }
      }
    ]
  }
end
