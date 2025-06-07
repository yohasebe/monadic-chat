# Facade methods for Research Assistant apps
# Provides clear interfaces for WebSearchAgent functionality

class ResearchAssistantOpenAI < MonadicApp
  # Performs web search using native OpenAI search or Tavily API fallback
  # @param query [String] The search query
  # @return [String] Search results
  def websearch_agent(query:)
    raise ArgumentError, "Query cannot be empty" if query.to_s.strip.empty?
    
    # Call the method from WebSearchAgent module
    super(query: query)
  rescue StandardError => e
    "Web search failed: #{e.message}"
  end
  
  # Legacy method for backward compatibility with Tavily search
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

class ResearchAssistantClaude < MonadicApp
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

class ResearchAssistantGemini < MonadicApp
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

class ResearchAssistantGrok < MonadicApp
  # Performs web search using native Grok search
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

class ResearchAssistantCohere < MonadicApp
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