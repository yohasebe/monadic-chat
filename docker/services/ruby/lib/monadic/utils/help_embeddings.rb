# frozen_string_literal: true

require_relative "text_embeddings"
require "digest"

# HelpEmbeddings extends TextEmbeddings specifically for the Monadic Chat help system
# It manages a separate database for documentation embeddings
class HelpEmbeddings < TextEmbeddings
  HELP_DB_NAME = "monadic_help"
  
  def initialize(recreate_db: false)
    @conn = self.class.connect_to_db(HELP_DB_NAME, recreate_db: recreate_db)
    # Create help-specific tables with additional metadata
    create_help_tables
  end

  # Override parent methods to use help-specific tables
  def insert_doc(doc)
    self.class.with_retry("Inserting help document") do
      result = @conn.exec_params(
        "INSERT INTO help_docs (title, file_path, section, language, items, metadata, embedding) VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7) ON CONFLICT (file_path, language) DO UPDATE SET title = $1, section = $3, items = $5, metadata = $6::jsonb, embedding = $7, updated_at = CURRENT_TIMESTAMP RETURNING id",
        [doc[:title], doc[:file_path], doc[:section], doc[:language] || 'en', doc[:items], doc[:metadata].to_json, doc[:embedding]]
      )
      result[0]["id"]
    end
  end

  def insert_item(item)
    self.class.with_retry("Inserting help item") do
      @conn.exec_params(
        "INSERT INTO help_items (doc_id, text, position, heading, metadata, embedding) VALUES ($1, $2, $3, $4, $5::jsonb, $6)",
        [item[:doc_id], item[:text], item[:position], item[:heading], item[:metadata].to_json, item[:embedding]]
      )
    end
  end

  def find_closest_text(text, top_n: 10)
    # get_embeddings returns an array, so we need the first element
    embeddings = get_embeddings([text])
    embedding = embeddings.first
    result = []
    
    self.class.with_retry("Finding closest help text") do
      res = @conn.exec_params(<<~SQL, [embedding, top_n])
        SELECT 
          hi.text,
          hi.doc_id,
          hi.position,
          hi.heading,
          hi.metadata,
          hd.title,
          hd.file_path,
          hd.section,
          hd.language,
          1 - (hi.embedding <=> $1::vector) AS similarity
        FROM help_items hi
        JOIN help_docs hd ON hi.doc_id = hd.id
        ORDER BY hi.embedding <=> $1::vector
        LIMIT $2
      SQL
      
      res.each do |row|
        result << {
          text: row["text"],
          doc_id: row["doc_id"].to_i,
          position: row["position"].to_i,
          heading: row["heading"],
          metadata: row["metadata"].is_a?(String) ? JSON.parse(row["metadata"]) : row["metadata"],
          title: row["title"],
          file_path: row["file_path"],
          section: row["section"],
          language: row["language"],
          similarity: row["similarity"].to_f
        }
      end
    end
    
    result
  end

  def find_closest_doc(text, top_n: 5, language: nil)
    # get_embeddings returns an array, so we need the first element
    embeddings = get_embeddings([text])
    embedding = embeddings.first
    result = []
    
    self.class.with_retry("Finding closest help document") do
      sql = <<~SQL
        SELECT 
          id,
          title,
          file_path,
          section,
          language,
          items,
          metadata,
          1 - (embedding <=> $1::vector) AS similarity
        FROM help_docs
      SQL
      
      params = [embedding]
      
      if language
        sql += " WHERE language = $3"
        params << language
      end
      
      sql += " ORDER BY embedding <=> $1::vector LIMIT $2"
      params.insert(1, top_n)
      
      res = @conn.exec_params(sql, params)
      
      res.each do |row|
        result << {
          doc_id: row["id"].to_i,
          title: row["title"],
          file_path: row["file_path"],
          section: row["section"],
          language: row["language"],
          items: row["items"].to_i,
          metadata: row["metadata"].is_a?(String) ? JSON.parse(row["metadata"]) : row["metadata"],
          similarity: row["similarity"].to_f
        }
      end
    end
    
    result
  end

  def list_titles(language: nil)
    result = []
    
    self.class.with_retry("Listing help titles") do
      sql = "SELECT id, title, file_path, section, language FROM help_docs"
      params = []
      
      if language
        sql += " WHERE language = $1"
        params << language
      end
      
      sql += " ORDER BY file_path, section"
      
      res = if params.empty?
              @conn.exec(sql)
            else
              @conn.exec_params(sql, params)
            end
      
      res.each do |row|
        result << {
          doc_id: row["id"].to_i,
          title: row["title"],
          file_path: row["file_path"],
          section: row["section"],
          language: row["language"]
        }
      end
    end
    
    result
  end

  def get_text_snippets(doc_id)
    result = []
    
    self.class.with_retry("Getting help snippets") do
      res = @conn.exec_params(
        "SELECT text, position, heading, metadata FROM help_items WHERE doc_id = $1 ORDER BY position",
        [doc_id]
      )
      
      res.each do |row|
        result << {
          text: row["text"],
          position: row["position"].to_i,
          heading: row["heading"],
          metadata: JSON.parse(row["metadata"])
        }
      end
    end
    
    result
  end

  # Help-specific method to clear all data
  def clear_all_help_data
    self.class.with_retry("Clearing help data") do
      @conn.exec("TRUNCATE TABLE help_items, help_docs RESTART IDENTITY CASCADE")
    end
  end

  # Get statistics about the help database
  def get_stats
    stats = {}
    
    self.class.with_retry("Getting help database stats") do
      # Document counts by language
      res = @conn.exec("SELECT language, COUNT(*) as count FROM help_docs GROUP BY language")
      stats[:documents_by_language] = {}
      res.each { |row| stats[:documents_by_language][row["language"]] = row["count"].to_i }
      
      # Total items
      res = @conn.exec("SELECT COUNT(*) as count FROM help_items")
      stats[:total_items] = res[0]["count"].to_i
      
      # Average items per document
      res = @conn.exec("SELECT AVG(items) as avg FROM help_docs")
      stats[:avg_items_per_doc] = res[0]["avg"].to_f.round(2)
    end
    
    stats
  end

  # Make the parent method public for the processing script
  # texts is an array of text strings
  def get_embeddings(texts)
    # Use batch processing method if available
    batch_size = (CONFIG['HELP_EMBEDDINGS_BATCH_SIZE'] || ENV['HELP_EMBEDDINGS_BATCH_SIZE'] || '50').to_i
    get_embeddings_batch(texts, batch_size: batch_size)
  end
  
  # Check if a document needs updating based on MD5 hash
  def document_needs_update?(file_path, content_hash, language = 'en')
    result = nil
    
    self.class.with_retry("Checking document hash") do
      res = @conn.exec_params(
        "SELECT metadata->>'content_hash' as hash FROM help_docs WHERE file_path = $1 AND language = $2",
        [file_path, language]
      )
      result = res.first
    end
    
    # Document needs update if not found or hash differs
    return true if result.nil?
    result['hash'] != content_hash
  end
  
  # Get multiple chunks for better context
  def find_closest_text_multi(text, chunks_per_result: 3, top_n: 5)
    # Get more results initially to ensure we have enough unique documents
    initial_results = find_closest_text(text, top_n: top_n * chunks_per_result)
    
    # Group by document and take top chunks from each
    grouped_results = {}
    initial_results.each do |result|
      doc_id = result[:doc_id]
      grouped_results[doc_id] ||= []
      grouped_results[doc_id] << result if grouped_results[doc_id].length < chunks_per_result
    end
    
    # Flatten and limit to requested number of document groups
    final_results = []
    grouped_results.values.take(top_n).each do |doc_chunks|
      final_results.concat(doc_chunks)
    end
    
    final_results
  end

  private

  def create_help_tables
    self.class.with_retry("Creating help tables") do
      # Docs table with additional help-specific metadata
      @conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS help_docs (
          id serial primary key,
          title text NOT NULL,
          file_path text NOT NULL,
          section text,
          language text DEFAULT 'en',
          items integer DEFAULT 0,
          metadata jsonb DEFAULT '{}',
          embedding vector(3072),
          created_at timestamp DEFAULT CURRENT_TIMESTAMP,
          updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(file_path, language)
        )
      SQL

      # Items table with help-specific fields
      @conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS help_items (
          id serial primary key,
          doc_id integer REFERENCES help_docs(id) ON DELETE CASCADE,
          text text NOT NULL,
          position smallint NOT NULL,
          heading text,
          metadata jsonb DEFAULT '{}',
          embedding vector(3072),
          created_at timestamp DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      # Create indexes for better performance
      @conn.exec("CREATE INDEX IF NOT EXISTS idx_help_docs_language ON help_docs(language)")
      @conn.exec("CREATE INDEX IF NOT EXISTS idx_help_docs_file_path ON help_docs(file_path)")
      # Note: ivfflat indexes removed due to 2000 dimension limit with text-embedding-3-large (3072 dims)
      # Consider using HNSW or no index for now
      @conn.exec("CREATE INDEX IF NOT EXISTS idx_help_items_doc_id ON help_items(doc_id)")
    end
  end
end