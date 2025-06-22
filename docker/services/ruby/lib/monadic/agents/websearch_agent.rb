module WebSearchAgent
  def websearch_agent(query: "")
    DebugHelper.debug("websearch_agent called with query: #{query}", category: :web_search, level: :debug)
    
    provider = self.class.name.downcase
    
    # For OpenAI with native websearch support (gpt-4.1, gpt-4.1-mini),
    # this method should never be called because OpenAI handles the search internally.
    # If it is called, it means the native search feature might not be working properly.
    # In this case, fall back to Tavily if available.
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
    end
    
    # For providers that explicitly use Tavily (Mistral, Gemini, Cohere, etc.)
    if CONFIG["TAVILY_API_KEY"]
      DebugHelper.debug("WebSearchAgent: Using Tavily for #{provider} provider", category: :web_search, level: :info)
      return tavily_search(query: query, n: 5)
    else
      return "Web search is not available. Please ensure TAVILY_API_KEY is configured."
    end
  end
end
