require_relative "../../lib/monadic/adapters/wikipedia_helper"

class WikipediaOpenAI < MonadicApp
  include OpenAIHelper
  include WikipediaHelper
end
