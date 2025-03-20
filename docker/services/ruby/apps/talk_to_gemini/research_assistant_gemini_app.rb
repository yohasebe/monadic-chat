class ResearchAssistantGemini < MonadicApp
  include GeminiHelper
  include WebSearchAgent

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
    group: "Google",
    disabled: !CONFIG["GEMINI_API_KEY"] || !CONFIG["TAVILY_API_KEY"],
    models: GeminiHelper.list_models,
    model: "gemini-2.0-flash-exp",
    websearch: true,
    temperature: 0.0,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Research Assistant (Gemini)",
    description: description,
    icon: icon,
    mathjax: true,
    image: true,
    tools: {
      function_declarations: [
        {
          name: "run_script",
          description: "Run program code and return the output.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Code execution command (e.g., 'python')"
              },
              code: {
                type: "string",
                description: "Code to be executed."
              },
              extension: {
                type: "string",
                description: "File extension of the code (e.g., 'py')"
              }
            },
            required: ["command", "code", "extension"]
          }
        },
        {
          name: "run_bash_command",
          description: "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Bash command to be executed."
              }
            },
            required: ["command"]
          }
        },
        {
          name: "lib_installer",
          description: "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed.",
          parameters: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "Library name to be installed."
              },
              packager: {
                type: "string",
                description: "Package manager to be used for installation. It can be either `pip` or `apt`."
              }
            },
            required: ["command", "packager"]
          }
        },
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
        },
        {
          name: "fetch_web_content",
          description: "Fetch the content of the web page of the given URL and return it.",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "URL of the web page."
              }
            },
            required: ["url"]
          }
        },
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
            required: ["file"]
          }
        },
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
            required: ["pdf"]
          }
        },
        {
          name: "check_environment",
          description: "Get the contents of the Dockerfile and the shell script used in the Python container.",
          parameters: {
            type: "object",
            properties: {
              dummy: {
                type: "string",
                description: "This parameter is not used and can be omitted."
              }
            },
            required: []
          }
        }
      ]
    }
  }
end
