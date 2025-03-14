module WebSearchAgent
  def websearch_agent(query: "")
    model = ENV["WEBSEARCH_MODEL"] || "gpt-4o-search-preview"
    messages = [
      {
        "role" => "user",
        "content" => query 
      },
    ]
    parameters = {
      messages: messages,
      model: model
    }

    send_query(parameters)
  end
end
