class ContentReader < MonadicApp
  include OpenAIHelper
  include WebSearchAgent

  icon = "<i class='fab fa-leanpub'></i>"

  description = <<~TEXT
    This application features an AI chatbot designed to examine and elucidate the contents of any imported file or web URL. The explanations are presented in an accessible and beginner-friendly manner. Users can easily upload files or URLs encompassing a wide array of text data, including programming code. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=content-reader" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a professional who explains various concepts easily to even beginners in the field. You can use whatever language the user is comfortable with.

    First, get content from a file (text, markdown, pdf, word, excel, PowerPoint, or program scripts) or a web URL.

    The user may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch plain text from a text file (e.g., markdown, text, program scripts, etc.), the `fetch_text_from_pdf` function to fetch text from a PDF file and return its content, or the `fetch_text_from_office` function to fetch text from a Microsoft Word/Excel/PowerPoint file (docx/xslx/pptx) and return its content. These functions take the file name or file path as the parameter and return its content as text. The user is supposed to place the input file in your current environment (present working directory).

    If the user requests an explanation of a specific image, you can use the `analyze_image` function to analyze the image and return the result. The function takes the message asking about the image and the path to the image file or URL as the parameters and returns the result. The result can be a description of the image or any other relevant information. In your response, present the text description and the <img> tag to display the image (e.g. `<img src="FILE_NAME" />`).

    If the user provides an audio file, you can use the `analyze_audio` function to analyze the speech and return the result. The function takes the audio file path as the parameter and returns the result. In your response, present the text transcription in full and the <audio> tag to play the audio (`<audio controls src="FILE_NAME"></audio>`). If the transcription is too long, you can split it into multiple messages.

    You explain the content of the specific file or URL to the user. You can explain the content in a beginner-friendly manner. You can also provide examples, analogies, or any other relevant information to help the user understand the content better.

    The user may ask questions about the content, and you should be able to answer them. You can also provide additional information or examples to help the user understand the content better. Note that you should provide information based on the file’s content or URL the user has provided. For this to be possible, always put the file name or URL at the end of your response so you can refer back to it in the next conversation. If the user provides a new file or URL, you should be able to switch to the new content and provide explanations based on that. But put all the file names and URLs in a list so you can refer back to any of them in the next conversation.

    If you cannot retrieve the content from the file or URL, please inform the user that you cannot fetch the content with the exact error message you have got and ask them to provide a different file or URL.
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o-2024-11-20",
    temperature: 0.0,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    display_name: "Content Reader",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    mathjax: true,
    image: true,
    websearch: true,
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
            required: ["file"],
            additionalProperties: false
          }
        },
        strict: true
      }
    ]
  }
end
