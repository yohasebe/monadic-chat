require_relative '../../lib/monadic/utils/text_embeddings'

class PDFNavigatorOpenAI < MonadicApp
  def initialize
    super
    # Ensure embeddings_db is properly initialized for PDF Navigator
    # Try multiple ways to get the embeddings database
    @embeddings_db ||= if defined?(EMBEDDINGS_DB)
      EMBEDDINGS_DB
    elsif defined?(TextEmbeddings)
      TextEmbeddings.new("monadic_user_docs", recreate_db: false)
    else
      nil
    end
  end

  def find_closest_text(text:, top_n:)
    # Lazy initialization if not already set
    if @embeddings_db.nil? && defined?(TextEmbeddings)
      @embeddings_db = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
    end
    
    return { error: "Database not initialized" } unless @embeddings_db
    
    # Ensure API key is available
    api_key = @api_key || CONFIG["OPENAI_API_KEY"]
    return { error: "OpenAI API key not configured" } if api_key.nil? || api_key.empty?
    
    # Pass API key to embeddings method
    result = @embeddings_db.find_closest_text(text, top_n: top_n, api_key: api_key)
    return { error: "Failed to find text" } unless result
    result
  rescue => e
    # Include more detailed error information
    { error: "Error finding text: #{e.class.name} - #{e.message}" }
  end

  def find_closest_doc(text:, top_n:)
    # Lazy initialization if not already set
    if @embeddings_db.nil? && defined?(TextEmbeddings)
      @embeddings_db = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
    end
    
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
    # Lazy initialization if not already set
    if @embeddings_db.nil? && defined?(TextEmbeddings)
      @embeddings_db = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
    end
    
    return { error: "Database not initialized" } unless @embeddings_db
    @embeddings_db.list_titles
  end

  def get_text_snippet(doc_id:, position:)
    # Lazy initialization if not already set
    if @embeddings_db.nil? && defined?(TextEmbeddings)
      @embeddings_db = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
    end
    
    return { error: "Database not initialized" } unless @embeddings_db
    @embeddings_db.get_text_snippet(doc_id, position)
  end

  def get_text_snippets(doc_id:)
    # Lazy initialization if not already set
    if @embeddings_db.nil? && defined?(TextEmbeddings)
      @embeddings_db = TextEmbeddings.new("monadic_user_docs", recreate_db: false)
    end
    
    return { error: "Database not initialized" } unless @embeddings_db
    @embeddings_db.get_text_snippets(doc_id)
  end
end