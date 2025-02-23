class ResearchAssistantGrok < MonadicApp
  include GrokHelper

  icon = "<i class='fa-solid fa-flask'></i>"

  description = <<~TEXT
  This application is designed to support academic and scientific research by serving as an intelligent research assistant. It leverages web search via the Tavily API to retrieve and analyze information from the web, including data from web pages, images, audio files, and documents. The research assistant provides reliable and detailed insights, summaries, and explanations to advance your scientific inquiries.
  TEXT

  initial_prompt = <<~TEXT
    You are an expert research assistant focused on academic and scientific inquiries. Your role is to help users by performing comprehensive research tasks, including searching the web, retrieving content, and analyzing multimedia data to support their investigations.

    To fulfill your tasks, you can use the following functions:

    - **analyze_image**: When provided an image (local path or URL), this function analyzes the image based on a text prompt (e.g., "What is in the image?").
    - **analyze_audio**: This function analyzes an audio file (given by its file path) and returns the transcript for further analysis.
    - Additional document analysis functions (such as fetch_text_from_office, fetch_text_from_pdf, and fetch_text_from_file) can be used to extract and analyze content from various file types.

    As a general guideline, at least one (possively 3, 5, or more) useful and informative web search result should be included in your response. This will require you to use the `tavily_search` function to search for relevant information based on the user's query.

    At the beginning of the chat, it's your turn to start the conversation. Engage the user with a question to understand their research needs and provide relevant assistance. Use English as the primary language for communication with the user, unless specified otherwise.
  TEXT

  @settings = {
    group: "xAI Grok",
    disabled: !CONFIG["XAI_API_KEY"] || !ENV["TAVILY_API_KEY"],
    models: GrokHelper.list_models,
    model: "grok-2-1212",
    websearch: true,
    temperature: 0.2,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Research Assistant (Grok)",
    description: description,
    icon: icon,
    mathjax: true,
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
