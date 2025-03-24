# OpenAI apps need to include the WebSearchAgent module
# if defined in MDSL format
# Other model proviers may not need to include the WebSearchAgent module
# since they use Tavily API, if api key is provided
class ChatOpenAI < MonadicApp
  include WebSearchAgent
end
