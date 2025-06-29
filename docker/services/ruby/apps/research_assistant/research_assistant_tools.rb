# Facade methods for Research Assistant apps
# Provides clear interfaces for WebSearchAgent functionality

class ResearchAssistantOpenAI < MonadicApp
  include OpenAIHelper
  include WebSearchAgent
  
  # Performs web search using native OpenAI search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantClaude < MonadicApp
  include ClaudeHelper
  include WebSearchAgent
  
  # Performs web search using native Claude search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantGemini < MonadicApp
  include GeminiHelper
  include WebSearchAgent
  
  # Performs web search using native Google search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantGrok < MonadicApp
  include GrokHelper
  include WebSearchAgent
  
  # Performs web search using native Grok Live Search
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
end

class ResearchAssistantCohere < MonadicApp
  include CohereHelper
  include WebSearchAgent
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @param n [Integer] Number of results
  # @return [Hash] Search results from Tavily
  def tavily_search(query:, n: 3)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query, n: n)
  rescue StandardError => e
    { error: "Web search failed: #{e.message}" }
  end
end

class ResearchAssistantMistral < MonadicApp
  include MistralHelper
  include WebSearchAgent
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
  
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @param n [Integer] Number of results
  # @return [Hash] Search results from Tavily
  def tavily_search(query:, n: 3)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query, n: n)
  rescue StandardError => e
    { error: "Web search failed: #{e.message}" }
  end
end

class ResearchAssistantDeepSeek < MonadicApp
  include DeepSeekHelper
  include WebSearchAgent
  # Performs web search using Tavily API
  # @param query [String] The search query
  # @param n [Integer] Number of results
  # @return [Hash] Search results from Tavily
  def tavily_search(query:, n: 3)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query, n: n)
  rescue StandardError => e
    { error: "Web search failed: #{e.message}" }
  end
end

class ResearchAssistantPerplexity < MonadicApp
  include PerplexityHelper
  include WebSearchAgent
  # Perplexity has built-in web search, no need for Tavily
end

# Ollama doesn't support web search, so no Research Assistant for Ollama