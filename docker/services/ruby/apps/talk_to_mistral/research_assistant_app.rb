class ResearchAssistantMistral < MonadicApp
  include MistralHelper
  include TavilyHelper

  icon = "<i class='fa-solid fa-flask'></i>"

  description = <<~TEXT
  This application is designed to support academic and scientific research by serving as an intelligent research assistant. It leverages web search via the Tavily API to retrieve and analyze information from the web, including data from web pages, images, audio files, and documents. The research assistant provides reliable and detailed insights, summaries, and explanations to advance your scientific inquiries.
  TEXT

  initial_prompt = <<~TEXT
  You are an expert research assistant focused on academic and scientific inquiries. Your role is to help users by performing comprehensive research tasks, including searching the web, retrieving content, and analyzing multimedia data to support their investigations.

  To fulfill your tasks, you can use the following functions:

  1. **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.
  
  2. **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.
  
  3. **analyze_image**: When provided an image (local path or URL), this function analyzes the image based on a text prompt (e.g., "What is in the image?").
  
  4. **analyze_audio**: This function analyzes an audio file (given by its file path) and returns the transcript for further analysis.
  
  5. Additional document analysis functions (such as fetch_text_from_office, fetch_text_from_pdf, and fetch_text_from_file) can be used to extract and analyze content from various file types.

  Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses.

  Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

  As ageneral guideline, at least one (possively 3, 5, or more) useful and informative web search result should be included in your response. This will require you to use the `tavily_search` function to search for relevant information based on the user's query.
  
  At the beginning of the chat, it's your turn to start the conversation. Engage the user with a question to understand their research needs and provide relevant assistance. Use English as the primary language for communication with the user, unless specified otherwise.

      Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">>Example</a>`

  When mentioning specific facts, statistics, references, proper names, or other data, ensure that your information is accurate and up-to-date. Use `tavily_search` to verify the information and provide the user with the most reliable and recent data available.
  TEXT

  @settings = {
    group: "Mistral",
    disabled: !CONFIG["MISTRAL_API_KEY"] || !ENV["TAVILY_API_KEY"],
    models: MistralHelper.list_models,
    model: "mistral-large-latest",
    websearch: true,
    temperature: 0.0,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Research Assistant (Mistral AI)",
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
            required: ["file"]
          }
        }
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
            required: ["pdf"]
          }
        }
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
            required: ["message", "image_path"]
          }
        }
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
            required: ["audio"]
          }
        }
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
          name: "tavily_fetch",
          description: "Fetch the content of the web page of the given URL and return its content.",
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
        }
      },
      {
        type: "function",
        function:
        {
          name: "tavily_search",
          description: "Search the web for the given query and return the result. The result contains the answer to the query, the source URL, and the content of the web page.",
          parameters: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Query to search for."
              },
              n: {
                type: "integer",
                description: "Number of results to return (default: 3)."
              }
            },
            required: ["query", "n"]
          }
        }
      }
    ]
  }
end
