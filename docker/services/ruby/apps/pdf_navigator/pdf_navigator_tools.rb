# PDF Navigator (OpenAI) is the primary consumer of the local PDF store. Each
# instance owns a Store scoped to "pdfnavigatoropenai" so its uploads do not
# leak into other apps that share the same Qdrant collections.

class PDFNavigatorOpenAI < MonadicApp
  APP_KEY = 'pdfnavigatoropenai'

  def initialize
    super
    @embeddings_db = Monadic::Pdf::Store.new(app_key: APP_KEY)
  end

  def find_closest_text(text:, top_n:)
    @embeddings_db.find_closest_text(text, top_n: top_n)
  rescue => e
    { error: "Error finding text: #{e.class.name} - #{e.message}" }
  end

  def find_closest_doc(text:, top_n:)
    @embeddings_db.find_closest_doc(text, top_n: top_n)
  rescue => e
    { error: "Error finding document: #{e.message}" }
  end

  def list_titles
    @embeddings_db.list_titles
  rescue => e
    { error: "Error listing titles: #{e.message}" }
  end

  def get_text_snippet(doc_id:, position:)
    @embeddings_db.get_text_snippet(doc_id, position)
  rescue => e
    { error: "Error getting snippet: #{e.message}" }
  end

  def get_text_snippets(doc_id:)
    @embeddings_db.get_text_snippets(doc_id)
  rescue => e
    { error: "Error getting snippets: #{e.message}" }
  end
end
