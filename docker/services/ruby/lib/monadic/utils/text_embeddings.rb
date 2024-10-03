# frozen_string_literal: true

require "pg"
require "pgvector"
require "net/http"
require "json"
require "matrix"
require "dotenv/load"

EMBEDDINGS_MODEL = "text-embedding-3-small"

class TextEmbeddings
  attr_accessor :conn

  # Set up PostgreSQL connection
  def self.connect_to_db(db_name, recreate_db: false)
    conn = nil
    retries = 15
    retries.times do |i|
      begin
        conn = if IN_CONTAINER
                 PG.connect(dbname: "postgres", host: "pgvector_service", port: 5432, user: "postgres")
               else
                 PG.connect(dbname: "postgres")
               end
        break if conn
      rescue PG::Error => e
        puts "Error connecting to database: #{e.message}. Retrying in #{i + 1} seconds..."
        sleep(i + 1)
      end
    end

    if recreate_db
      # Drop the database if it exists
      conn.exec("DROP DATABASE IF EXISTS #{db_name}")

      # Create the database
      conn.exec("CREATE DATABASE #{db_name}")
    else
      # Check if the database exists
      result = conn.exec_params("SELECT 1 FROM pg_database WHERE datname = $1", [db_name])
      if result.ntuples.zero?
        # Create the database if it does not exist
        conn.exec("CREATE DATABASE #{db_name}")
      end
    end

    conn.close

    # Connect to the new database and set up the table and extension
    begin
      conn = if IN_CONTAINER
               PG.connect(dbname: db_name, host: "pgvector_service", port: 5432, user: "postgres")
             else
               PG.connect(dbname: db_name)
             end
    rescue PG::Error => e
      puts "Error connecting to database: #{e.message}"
    end

    conn.exec("SET client_min_messages TO warning")
    conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    conn.exec("CREATE TABLE IF NOT EXISTS docs (id serial primary key, title text, items integer, metadata jsonb, embedding vector(1536))")
    conn.exec("CREATE TABLE IF NOT EXISTS items (id serial primary key, doc_id integer, text text, position smallint, metadata jsonb, embedding vector(1536))")

    registry = PG::BasicTypeRegistry.new.define_default_types
    Pgvector::PG.register_vector(registry)
    conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn, registry: registry)

    conn
  end

  def initialize(db_name, recreate_db: false)
    @conn = TextEmbeddings.connect_to_db(db_name, recreate_db: recreate_db)
  end

  # Close the PostgreSQL connection
  def close_connection
    @conn&.close
  end

  # Combine embeddings of multiple text snippets
  def combine_embeddings(snippets_embeddings)
    num_snippets = snippets_embeddings.size
    combined_embedding = Vector.zero(snippets_embeddings.first.size)

    snippets_embeddings.each do |embedding|
      combined_embedding += embedding
    end

    combined_embedding /= num_snippets.to_f
    combined_embedding
  end

  # Get text embeddings using OpenAI API
  def get_embeddings(text, api_key: nil, retries: 3)
    raise ArgumentError, "text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/engines/#{EMBEDDINGS_MODEL}/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    api_key ||= if Object.const_defined?("API_KEY")
                  API_KEY
                else
                  ENV["OPENAI_API_KEY"]
                end

    request["Authorization"] = "Bearer #{api_key}"
    request.body = { input: text }.to_json

    response = nil
    retries.times do |i|
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.read_timeout = 900 # 15min
        http.open_timeout = 120 # 2min
        http.request(request)
      end
      break if response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      puts "Error: #{e.message}. Retrying in #{i + 1} seconds..."
      sleep(i + 1)
    end

    raise StandardError, "Failed to retrieve text embeddings after #{retries} retries" if response.nil?

    JSON.parse(response.body)["data"][0]["embedding"]
  end

  # Store embeddings in the database with metadata
  def store_embeddings(doc_data, items_data, api_key: nil)
    return false if doc_data.empty? || items_data.empty?

    # insert the document data and get the doc_id
    doc_id = @conn.exec_params(
      "INSERT INTO docs (title, items, metadata) VALUES ($1, $2, $3) RETURNING id",
      [doc_data[:title], items_data.size, doc_data[:metadata].to_json]
    ).getvalue(0, 0)

    embeddings = []
    items_data.each_with_index do |item, index|
      embedding = get_embeddings(item[:text], api_key: api_key)
      embeddings << Vector.elements(embedding)

      @conn.exec_params(
        "INSERT INTO items (doc_id, text, position, metadata, embedding) VALUES ($1, $2, $3, $4, $5)",
        [doc_id, item[:text], index + 1, item[:metadata].to_json, embedding]
      )
    end

    combined_embedding = combine_embeddings(embeddings)
    @conn.exec_params("UPDATE docs SET embedding = $1 WHERE id = $2", [combined_embedding.to_a, doc_id])

    { doc_id: doc_id, total_items: items_data.size }
  end

  # Find the closest text in the database
  def find_closest_text(text, top_n: 1)
    return false if text == ""

    embedding = get_embeddings(text)

    sql = <<~SQL
      SELECT docs.id, docs.title, items.text, items.position, docs.items, items.metadata, items.embedding
      FROM items JOIN docs ON items.doc_id = docs.id ORDER BY items.embedding <-> $1 LIMIT $2
    SQL

    # Find the closest text in the database joining the "items" table with the "docs" table
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

  # Find the closest doc in the database
  def find_closest_doc(text, top_n: 1)
    return false if text == ""

    embedding = get_embeddings(text)

    sql = <<~SQL
      SELECT id, title FROM docs ORDER BY embedding <-> $1 LIMIT $2
    SQL

    results = @conn.exec_params(sql, [embedding, top_n])
    results.map do |result|
      { id: result["id"].to_i, title: result["title"] }
    end
  end

  # Retrieve the text snippet from the database
  def get_text_snippet(doc_id, position)
    result = @conn.exec_params("SELECT text FROM items WHERE doc_id = $1 AND position = $2", [doc_id, position]).first
    result["text"] if result
  end

  # Search metadata in the database
  def search_metadata(search_key, search_value)
    results = @conn.exec_params("SELECT metadata FROM items WHERE metadata->>$1 = $2", [search_key, search_value])
    results.map { |result| result["metadata"] }
  end

  # List arrays of the doc id, title, and num of items value from the docs table
  def list_titles
    result = @conn.exec("SELECT id, title, items FROM docs")
    result.map do |row|
      { id: row["id"].to_i, title: row["title"], items: row["items"].to_i }
    end
  end

  # Retrieve all the text snippets of a document from the database
  def get_text_snippets(doc_id)
    results = @conn.exec_params("SELECT text FROM items WHERE doc_id = $1 ORDER BY position", [doc_id])
    results.map { |result| result["text"] }
  end

  # delete the row having the given "title" value from the docs table
  # dlete the rows having the doc_id from the items table
  # return true if successful or false if not
  def delete_by_title(title)
    # get the doc id and delete the row from the docs table
    doc_id = @conn.exec_params("SELECT id FROM docs WHERE title = $1", [title]).first["id"]
    return false if doc_id.nil?

    @conn.exec_params("DELETE FROM docs WHERE id = $1", [doc_id])

    # delete the rows from the items table
    @conn.exec_params("DELETE FROM items WHERE doc_id = $1", [doc_id])
    true
  rescue PG::Error => e
    puts "Error deleting rows: #{e.message}"
    false
  end
end

# execute the following only if the file is directly run
if $PROGRAM_NAME == __FILE__

  if ARGV.length < 2
    puts "Usage: ruby text_embeddings.rb <command> <arguments>"
    exit
  end

  command = ARGV.shift
  db_name = ARGV.shift

  case command
  when "create_db"
    connect_to_db(db_name, recreate_db: true)
    puts "Database '#{db_name}' created."
  else
    text_embeddings = TextEmbeddings.new(db_name)

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
  end
end
