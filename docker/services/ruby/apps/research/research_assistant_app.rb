class ResearchAssistant < MonadicApp
  include OpenAIHelper

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

    As a general guideline, at least one (possibly 3, 5, or more) useful and informative web search result should be included in your response. Use your built-in web search capabilities to search for relevant information based on the user's query.

    At the beginning of the chat, it's your turn to start the conversation. Engage the user with a question to understand their research needs and provide relevant assistance. Use English as the primary language for communication with the user, unless specified otherwise.
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"] || !CONFIG["TAVILY_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o-2024-11-20",
    websearch: true,
    temperature: 0.2,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Research Assistant",
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
          description: "fetch the text from the microsoft word/excel/powerpoint file and return it.",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "file name or file path of the microsoft word/excel/powerpoint file."
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
          description: "fetch the text from the pdf file and return it.",
          parameters: {
            type: "object",
            properties: {
              pdf: {
                type: "string",
                description: "file name or file path of the pdf"
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
          description: "analyze the image and return the result.",
          parameters: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "text prompt asking about the image (e.g. 'what is in the image?')."
              },
              image_path: {
                type: "string",
                description: "path to the image file. it can be either a local file path or a url."
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
          description: "analyze the audio and return the transcript.",
          parameters: {
            type: "object",
            properties: {
              audio: {
                type: "string",
                description: "file path of the audio file"
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
          description: "fetch the text from a file and return its content.",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "file name or file path"
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
