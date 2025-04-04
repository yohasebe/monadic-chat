# OpenAI apps need to include the WebSearchAgent module
# if defined in MDSL format
# For web search functionality to work, the application needs to have websearch: true
# feature and a valid API key needs to be configured
class ChatOpenAI < MonadicApp
  include WebSearchAgent
end
