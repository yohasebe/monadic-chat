class PDFNavigatorOpenAI < MonadicApp
  def find_closest_text(text:, top_n:)
    return { error: "Database not initialized" } unless @embeddings_db
    
    # Ensure API key is available
    api_key = @api_key || CONFIG["OPENAI_API_KEY"]
    return { error: "OpenAI API key not configured" } if api_key.nil? || api_key.empty?
    
    # Pass API key to embeddings method
    result = @embeddings_db.find_closest_text(text, top_n: top_n, api_key: api_key)
    return { error: "Failed to find text" } unless result
    result
  rescue => e
    { error: "Error finding text: #{e.message}" }
  end

  def find_closest_doc(text:, top_n:)
    return { error: "Database not initialized" } unless @embeddings_db
    
    # Ensure API key is available
    api_key = @api_key || CONFIG["OPENAI_API_KEY"]
    return { error: "OpenAI API key not configured" } if api_key.nil? || api_key.empty?
    
    result = @embeddings_db.find_closest_doc(text, top_n: top_n, api_key: api_key)
    return { error: "Failed to find document" } unless result
    result
  rescue => e
    { error: "Error finding document: #{e.message}" }
  end

  def list_titles
    @embeddings_db.list_titles
  end

  def get_text_snippet(doc_id:, position:)
    @embeddings_db.get_text_snippet(doc_id, position)
  end

  def get_text_snippets(doc_id:)
    @embeddings_db.get_text_snippets(doc_id)
  end
end