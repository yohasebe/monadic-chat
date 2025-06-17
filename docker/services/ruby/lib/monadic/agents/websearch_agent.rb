module WebSearchAgent
  def websearch_agent(query: "")
    DebugHelper.debug("websearch_agent called with query: #{query}", category: :web_search, level: :debug)
    
    # For providers with built-in websearch (Mistral), use tavily_search directly
    provider = self.class.name.downcase
    if provider.include?("mistral")
      DebugHelper.debug("WebSearchAgent: Using Tavily for Mistral provider", category: :web_search, level: :info)
      return tavily_search(query: query, n: 3)
    end
    
    # Check if Tavily is available as fallback
    use_tavily_fallback = CONFIG["TAVILY_API_KEY"] && 
                         CONFIG["OPENAI_NATIVE_WEBSEARCH_FALLBACK"] != "false"
    
    # Use the configured WEBSEARCH_MODEL (defaults to gpt-4.1-mini)
    model = CONFIG["WEBSEARCH_MODEL"] || ENV["WEBSEARCH_MODEL"] || "gpt-4.1-mini"
    
    begin
      messages = [
        {
          "role" => "user",
          "content" => query 
        }
      ]
      
      # Explicitly set model parameter to ensure it's used
      parameters = {
        "messages" => messages,
        "model" => model
      }
      
      # Debug logging
      DebugHelper.debug("WebSearchAgent: Using model #{model} for websearch query", category: :web_search, level: :info)
      
      # Use the standard send_query method with the correct model
      result = send_query(parameters)
      
      # If result indicates failure and we have Tavily as fallback
      if result.to_s.include?("ERROR") && use_tavily_fallback
        raise "Native search failed, trying Tavily fallback"
      end
      
      return result
    rescue => e
      # If native search fails and Tavily is available, use Tavily
      if use_tavily_fallback
        DebugHelper.debug("WebSearchAgent: Falling back to Tavily API due to error: #{e.message}", category: :web_search, level: :warning)
        
        # Use Tavily search as fallback
        return tavily_search(query: query, n: 3)
      else
        # Re-raise the error if no fallback is available
        raise e
      end
    end
  end
end
