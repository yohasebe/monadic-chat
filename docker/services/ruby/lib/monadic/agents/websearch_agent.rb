module WebSearchAgent
  def websearch_agent(query: "")
    # Always use a search-capable model
    model = ENV["WEBSEARCH_MODEL"] || "gpt-4o-search-preview"
    
    # Make sure we're using a search model
    unless model.include?("search")
      model = "gpt-4o-search-preview"
    end
    
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
    send_query(parameters)
  end
end
