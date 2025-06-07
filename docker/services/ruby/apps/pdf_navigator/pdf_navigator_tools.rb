class PDFNavigatorOpenAI < MonadicApp
  include OpenAIHelper
  
  def find_closest_text(text:, top_n:)
    @embeddings_db.find_closest_text(text, top_n: top_n)
  end

  def find_closest_doc(text:, top_n:)
    @embeddings_db.find_closest_doc(text, top_n: top_n)
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