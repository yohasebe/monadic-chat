module WebSearchAgent
  def websearch_agent(query: "")
    # Check if Tavily is available as fallback
    use_tavily_fallback = CONFIG["TAVILY_API_KEY"] && 
                         CONFIG["OPENAI_NATIVE_WEBSEARCH_FALLBACK"] != "false"
    
    # First try with search-capable model
    model = ENV["WEBSEARCH_MODEL"] || "gpt-4o-search-preview"
    
    # Make sure we're using a search model
    unless model.include?("search")
      model = "gpt-4o-search-preview"
    end
    
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
      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "WebSearchAgent: Using model #{model} for websearch query"
      end
      
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
        if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
          puts "WebSearchAgent: Falling back to Tavily API due to error: #{e.message}"
        end
        
        # Use Tavily search as fallback
        return tavily_search(query: query, n: 3)
      else
        # Re-raise the error if no fallback is available
        raise e
      end
    end
  end
end
