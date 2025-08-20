module WebSearchAgent
  def websearch_agent(query: "")
    DebugHelper.debug("websearch_agent called with query: #{query}", category: :web_search, level: :debug)
    
    provider = self.class.name.downcase
    
    # For providers with native websearch support, this method should not be called
    # as they handle search internally through their own mechanisms
    if provider.include?("openai")
      DebugHelper.debug("WebSearchAgent: OpenAI native websearch should handle this internally", category: :web_search, level: :warning)
      
      # Check if Tavily is available as fallback
      if CONFIG["TAVILY_API_KEY"]
        DebugHelper.debug("WebSearchAgent: Falling back to Tavily for OpenAI", category: :web_search, level: :info)
        return tavily_search(query: query, n: 5)
      else
        # Return a message indicating that native search should have handled this
        return "Web search results are being processed by the AI model's native capabilities. Please continue with your response based on the search query: #{query}"
      end
    elsif provider.include?("gemini")
      DebugHelper.debug("WebSearchAgent: Gemini uses URL Context for web search", category: :web_search, level: :info)
      # Gemini uses URL Context feature instead of Tavily
      return "Web search is handled through Gemini's native URL Context feature. Processing query: #{query}"
    end
    
    # For providers that use Tavily (Mistral, Cohere, DeepSeek, Ollama)
    if CONFIG["TAVILY_API_KEY"]
      DebugHelper.debug("WebSearchAgent: Using Tavily for #{provider} provider", category: :web_search, level: :info)
      return tavily_search(query: query, n: 5)
    else
      return "Web search is not available. Please ensure TAVILY_API_KEY is configured."
    end
  end
end
