# frozen_string_literal: true

require "pg"
require "pgvector"
require "net/http"
require "json"
require "matrix"
require "dotenv/load"

EMBEDDINGS_MODEL = "text-embedding-3-large"

class TextEmbeddings
  attr_accessor :conn

  class DatabaseError < StandardError; end

  # Retry configuration
  RETRY_CONFIG = {
    max_attempts: 3,
    base_delay: 0.5,    # Base delay in seconds
    max_delay: 5.0,     # Maximum delay in seconds
    multiplier: 1.5     # Exponential backoff multiplier
  }.freeze

  # Implements exponential backoff with jitter
  def self.exponential_backoff(attempt)
    delay = [
      RETRY_CONFIG[:base_delay] * (RETRY_CONFIG[:multiplier] ** attempt) * (1.0 + rand * 0.1),
      RETRY_CONFIG[:max_delay]
    ].min
    sleep(delay)
  end

  # Wrapper for database operations with retry logic
  def self.with_retry(operation_name)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue PG::Error => e
      if attempts < RETRY_CONFIG[:max_attempts]
        puts "#{operation_name} failed (attempt #{attempts}/#{RETRY_CONFIG[:max_attempts]}): #{e.message}" if ENV['EMBEDDINGS_DEBUG']
        exponential_backoff(attempts)
        retry
      else
        raise DatabaseError, "#{operation_name} failed after #{attempts} attempts: #{e.message}"
      end
    end
  end

  # Set up PostgreSQL connection
  def self.connect_to_db(db_name, recreate_db: false)
    conn = nil
    
    # Initial connection to PostgreSQL
    with_retry("Database connection") do
      conn = if IN_CONTAINER
               PG.connect(dbname: "postgres", host: "pgvector_service", port: 5432, user: "postgres")
             else
               # For local development, connect to Docker container's PostgreSQL
               host = ENV['POSTGRES_HOST'] || "localhost"
               port = (ENV['POSTGRES_PORT'] || 5432).to_i
               PG.connect(dbname: "postgres", host: host, port: port, user: "postgres")
             end
    end

    if recreate_db
      with_retry("Database recreation") do
        conn.exec("DROP DATABASE IF EXISTS #{db_name}")
        conn.exec("CREATE DATABASE #{db_name}")
      end
    else
      # Check if the database exists
      result = nil
      with_retry("Database existence check") do
        result = conn.exec_params("SELECT 1 FROM pg_database WHERE datname = $1", [db_name])
      end

      if result.ntuples.zero?
        with_retry("Database creation") do
          conn.exec("CREATE DATABASE #{db_name}")
        end
      end
    end

    conn.close

    # Connect to the new database
    new_conn = nil
    with_retry("New database connection") do
      new_conn = if IN_CONTAINER
                   PG.connect(dbname: db_name, host: "pgvector_service", port: 5432, user: "postgres")
                 else
                   # For local development, connect to Docker container's PostgreSQL
                   host = ENV['POSTGRES_HOST'] || "localhost"
                   port = (ENV['POSTGRES_PORT'] || 5432).to_i
                   PG.connect(dbname: db_name, host: host, port: port, user: "postgres")
                 end
    end

    # Initialize database
    with_retry("Database initialization") do
      new_conn.exec("SET client_min_messages TO warning")
      new_conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
      new_conn.exec("CREATE TABLE IF NOT EXISTS docs (id serial primary key, title text, items integer, metadata jsonb, embedding vector(3072))")
      new_conn.exec("CREATE TABLE IF NOT EXISTS items (id serial primary key, doc_id integer, text text, position smallint, metadata jsonb, embedding vector(3072))")
    end

    registry = PG::BasicTypeRegistry.new.define_default_types
    Pgvector::PG.register_vector(registry)
    new_conn.type_map_for_results = PG::BasicTypeMapForResults.new(new_conn, registry: registry)

    new_conn
  end

  def initialize(db_name, recreate_db: false)
    @conn = TextEmbeddings.connect_to_db(db_name, recreate_db: recreate_db)
  end

  # Close the PostgreSQL connection
  def close_connection
    @conn&.close
  end

  # Database operation wrapper with retry logic
  def with_retry(operation_name, &block)
    self.class.with_retry(operation_name, &block)
  end

  # Rest of the methods with retry logic added...
  def store_embeddings(doc_data, items_data, api_key: nil)
    return false if doc_data.empty? || items_data.empty?

    doc_id = nil
    with_retry("Document insertion") do
      result = @conn.exec_params(
        "INSERT INTO docs (title, items, metadata) VALUES ($1, $2, $3) RETURNING id",
        [doc_data[:title], items_data.size, doc_data[:metadata].to_json]
      )
      doc_id = result.getvalue(0, 0)
    end

    embeddings = []
    items_data.each_with_index do |item, index|
      embedding = get_embeddings(item[:text], api_key: api_key)
      embeddings << Vector.elements(embedding)

      with_retry("Item insertion") do
        @conn.exec_params(
          "INSERT INTO items (doc_id, text, position, metadata, embedding) VALUES ($1, $2, $3, $4, $5)",
          [doc_id, item[:text], index + 1, item[:metadata].to_json, embedding]
        )
      end
    end

    combined_embedding = combine_embeddings(embeddings)
    with_retry("Document embedding update") do
      @conn.exec_params("UPDATE docs SET embedding = $1 WHERE id = $2", [combined_embedding.to_a, doc_id])
    end

    { doc_id: doc_id, total_items: items_data.size }
  end

  def find_closest_text(text, top_n: 1)
    return false if text == ""

    embedding = get_embeddings(text)
    
    with_retry("Closest text search") do
      sql = <<~SQL
        SELECT docs.id, docs.title, items.text, items.position, docs.items, items.metadata, items.embedding
        FROM items JOIN docs ON items.doc_id = docs.id ORDER BY items.embedding <-> $1 LIMIT $2
      SQL

      results = @conn.exec_params(sql, [embedding, top_n])
      results.map do |result|
        {
          text: result["text"],
          doc_id: result["id"].to_i,
          doc_title: result["title"],
          position: result["position"].to_i,
          total_items: result["items"].to_i,
          metadata: result["metadata"]
        }
      end
    end
  end

  def find_closest_doc(text, top_n: 1)
    return false if text == ""

    embedding = get_embeddings(text)

    with_retry("Closest document search") do
      sql = <<~SQL
        SELECT id, title FROM docs ORDER BY embedding <-> $1 LIMIT $2
      SQL

      results = @conn.exec_params(sql, [embedding, top_n])
      results.map do |result|
        { id: result["id"].to_i, title: result["title"] }
      end
    end
  end

  def get_text_snippet(doc_id, position)
    with_retry("Text snippet retrieval") do
      result = @conn.exec_params(
        "SELECT text FROM items WHERE doc_id = $1 AND position = $2",
        [doc_id, position]
      ).first
      result["text"] if result
    end
  end

  def search_metadata(search_key, search_value)
    with_retry("Metadata search") do
      results = @conn.exec_params(
        "SELECT metadata FROM items WHERE metadata->>$1 = $2",
        [search_key, search_value]
      )
      results.map { |result| result["metadata"] }
    end
  end

  def list_titles
    with_retry("Title listing") do
      result = @conn.exec("SELECT id, title, items FROM docs")
      result.map do |row|
        { id: row["id"].to_i, title: row["title"], items: row["items"].to_i }
      end
    end
  end

  def get_text_snippets(doc_id)
    with_retry("Text snippets retrieval") do
      results = @conn.exec_params(
        "SELECT text FROM items WHERE doc_id = $1 ORDER BY position",
        [doc_id]
      )
      results.map { |result| result["text"] }
    end
  end

  def delete_by_title(title)
    doc_id = nil
    
    with_retry("Document ID retrieval") do
      result = @conn.exec_params("SELECT id FROM docs WHERE title = $1", [title]).first
      return false unless result
      doc_id = result["id"]
    end

    with_retry("Document deletion") do
      @conn.exec_params("DELETE FROM docs WHERE id = $1", [doc_id])
    end

    with_retry("Items deletion") do
      @conn.exec_params("DELETE FROM items WHERE doc_id = $1", [doc_id])
    end

    true
  rescue DatabaseError => e
    puts "Error during deletion process: #{e.message}" if ENV['EMBEDDINGS_DEBUG']
    false
  end
  
  def combine_embeddings(snippets_embeddings)
    return Vector.zero(3072) if snippets_embeddings.empty?

    num_snippets = snippets_embeddings.size
    combined_embedding = Vector.zero(snippets_embeddings.first.size)

    snippets_embeddings.each do |embedding|
      combined_embedding += embedding
    end

    combined_embedding /= num_snippets.to_f
    combined_embedding
  end

  # Instance method for exponential backoff
  def exponential_backoff(attempt)
    # Using the class's configuration for backoff
    self.class.exponential_backoff(attempt)
  end

  def get_embeddings(text, api_key: nil, retries: 3)
    raise ArgumentError, "Text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    api_key ||= if Object.const_defined?("API_KEY")
                  API_KEY
                else
                  CONFIG["OPENAI_API_KEY"] || ENV["OPENAI_API_KEY"]
                end

    request["Authorization"] = "Bearer #{api_key}"
    request.body = { input: text, model: EMBEDDINGS_MODEL }.to_json

    retries.times do |i|
      begin
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.read_timeout = 900 # 15min
          http.open_timeout = 120 # 2min
          http.request(request)
        end

        if response.is_a?(Net::HTTPSuccess)
          begin
            parsed_response = JSON.parse(response.body)
            if parsed_response["data"] && parsed_response["data"][0] && parsed_response["data"][0]["embedding"]
              return parsed_response["data"][0]["embedding"]
            else
              raise StandardError, "Invalid response format: missing embedding data"
            end
          rescue JSON::ParserError => e
            raise StandardError, "Failed to parse API response: #{e.message}"
          end
        else
          # Handle non-success responses
          error_body = response.body
          error_msg = if error_body && !error_body.empty?
                        begin
                          JSON.parse(error_body)["error"]["message"] rescue error_body
                        rescue
                          error_body
                        end
                      else
                        "HTTP #{response.code} #{response.message}"
                      end
          
          if i == retries - 1
            raise StandardError, "API request failed: #{error_msg}"
          else
            exponential_backoff(i)
          end
        end
      rescue StandardError => e
        last_attempt = (i == retries - 1)
        if last_attempt
          raise StandardError, "Failed to retrieve embeddings: #{e.message}"
        else
          exponential_backoff(i)
        end
      end
    end

    raise StandardError, "Failed to retrieve embeddings after #{retries} attempts"
  end

  # Batch processing method for multiple texts
  def get_embeddings_batch(texts, api_key: nil, batch_size: nil, retries: 3)
    return [] if texts.empty?
    
    # Get batch size from environment or use default
    batch_size ||= (CONFIG['EMBEDDINGS_BATCH_SIZE'] || ENV['EMBEDDINGS_BATCH_SIZE'] || '50').to_i
    batch_size = [batch_size, 2048].min # OpenAI max is 2048 inputs per request
    
    api_key ||= if Object.const_defined?("API_KEY")
                  API_KEY
                else
                  CONFIG["OPENAI_API_KEY"] || ENV["OPENAI_API_KEY"]
                end
    
    all_embeddings = []
    
    # Process texts in batches
    texts.each_slice(batch_size) do |batch|
      puts "Processing batch of #{batch.size} texts..." if ENV['EMBEDDINGS_DEBUG']
      
      uri = URI("https://api.openai.com/v1/embeddings")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = { input: batch, model: EMBEDDINGS_MODEL }.to_json
      
      retries.times do |i|
        begin
          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
            http.read_timeout = 900 # 15min
            http.open_timeout = 120 # 2min
            http.request(request)
          end

          if response.is_a?(Net::HTTPSuccess)
            begin
              parsed_response = JSON.parse(response.body)
              if parsed_response["data"]
                # Extract embeddings in the correct order
                batch_embeddings = parsed_response["data"]
                                   .sort_by { |item| item["index"] }
                                   .map { |item| item["embedding"] }
                all_embeddings.concat(batch_embeddings)
                break # Success, move to next batch
              else
                raise StandardError, "Invalid response format: missing embedding data"
              end
            rescue JSON::ParserError => e
              raise StandardError, "Failed to parse API response: #{e.message}"
            end
          else
            # Handle non-success responses
            error_body = response.body
            error_msg = if error_body && !error_body.empty?
                          begin
                            JSON.parse(error_body)["error"]["message"] rescue error_body
                          rescue
                            error_body
                          end
                        else
                          "HTTP #{response.code} #{response.message}"
                        end
            
            if i == retries - 1
              raise StandardError, "API request failed for batch: #{error_msg}"
            else
              exponential_backoff(i)
            end
          end
        rescue StandardError => e
          last_attempt = (i == retries - 1)
          if last_attempt
            raise StandardError, "Failed to retrieve embeddings for batch: #{e.message}"
          else
            exponential_backoff(i)
          end
        end
      end
    end
    
    all_embeddings
  end
end

# Execute the following only if the file is directly run
if $PROGRAM_NAME == __FILE__
  if ARGV.length < 2
    puts "Usage: ruby text_embeddings.rb <command> <arguments>"
    exit
  end

  command = ARGV.shift
  db_name = ARGV.shift

  begin
    case command
    when "create_db"
      TextEmbeddings.connect_to_db(db_name, recreate_db: true)
      puts "Database '#{db_name}' created successfully."
    else
      text_embeddings = TextEmbeddings.new(db_name)
      begin
        case command
        when "list_titles"
          puts text_embeddings.list_titles
        when "find_closest_text"
          text = ARGV.shift
          puts text_embeddings.find_closest_text(text)
        when "search_metadata"
          search_key = ARGV.shift
          search_value = ARGV.shift
          puts text_embeddings.search_metadata(search_key, search_value)
        else
          puts "Unknown command '#{command}'"
        end
      ensure
        text_embeddings.close_connection
      end
    end
  rescue DatabaseError => e
    puts "Database operation failed: #{e.message}"
    exit 1
  rescue StandardError => e
    puts "An error occurred: #{e.message}"
    exit 1
  end
end
