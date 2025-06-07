# Facade methods for Language Practice Plus app
# Provides clear interface for WebSearchAgent functionality

class LanguagePracticePlusOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include WebSearchAgent if defined?(WebSearchAgent)
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @param n [Integer] Number of results to return
  # @return [Hash] Search results from Tavily
  def tavily_search(query:, n: 3)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from TavilyHelper
    super(query: query, n: n)
  rescue StandardError => e
    { error: "Web search failed: #{e.message}" }
  end
  
  # Alias for compatibility - some apps may use websearch_agent instead
  alias websearch_agent tavily_search
end