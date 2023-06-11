# frozen_string_literal: true

require "pg"
require "pgvector"
require "net/http"
require "json"
require "dotenv/load"

# return true if we are inside a docker container
def in_container?
  File.file?("/.dockerenv")
end

class TextEmbeddings
  attr_accessor :conn

  # Set up PostgreSQL connection
  def self.connect_to_db(db_name, recreate_db: false)
    conn = if in_container?
             PG.connect(dbname: "postgres", host: "db", port: 5432, user: "postgres")
           else
             PG.connect(dbname: "postgres")
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
      conn = if in_container?
               PG.connect(dbname: db_name, host: "db", port: 5432, user: "postgres")
             else
               PG.connect(dbname: db_name)
             end
    rescue PG::Error => e
      puts "Error connecting to database: #{e.message}"
    end

    conn.exec("SET client_min_messages TO warning")
    conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    conn.exec("CREATE TABLE IF NOT EXISTS items (id serial primary key, metadata jsonb, embedding vector(1536))")

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

  # Get text embeddings using OpenAI API
  def get_embeddings(text, api_key: nil, retries: 3)
    raise ArgumentError, "text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/engines/text-embedding-ada-002/embeddings")
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
  def store_embeddings(text, metadata, api_key: nil)
    return false if text == ""

    metadata = metadata.merge({ "text" => text })
    embedding = get_embeddings(text, api_key: api_key)
    @conn.exec_params("INSERT INTO items (metadata, embedding) VALUES ($1, $2)", [metadata.to_json, embedding])
  end

  # Find the closest text in the database
  def find_closest_text(text)
    return false if text == ""

    embedding = get_embeddings(text)
    result = @conn.exec_params("SELECT metadata FROM items ORDER BY embedding <-> $1 LIMIT 1", [embedding]).first
    result ? result["metadata"] : {}
  end

  # Search metadata in the database
  def search_metadata(search_key, search_value)
    results = @conn.exec_params("SELECT metadata FROM items WHERE metadata->>$1 = $2", [search_key, search_value])
    results.map { |result| result["metadata"] }
  end

  # List all the "title" values in the metadata JSON for each row in the "items" table
  def list_titles
    # Select the distinct "title" value from the metadata JSON for each row in the "items" table
    result = @conn.exec("SELECT DISTINCT metadata->>'title' FROM items")

    # Map the resulting rows to an array of unique "title" values
    result.map { |row| row["?column?"] }
  end

  # list all the metadata other than "text"
  def list_metadata
    result = @conn.exec("SELECT metadata FROM items")
    result = result.map { |row| row["metadata"].except("text") }
    # group the result by "title" and sum the "tokens" values for each group
    result.group_by { |row| row["title"] }.map { |title, rows| { title: title, tokens_sum: rows.sum { |row| row["tokens"] } } }
  end

  # delete all rows having the given "title" value
  # return true if successful or false if not
  def delete_by_title(title)
    @conn.exec_params("DELETE FROM items WHERE metadata->>'title' = $1", [title])
    true
  rescue PG::Error => e
    puts "Error deleting rows: #{e.message}"
    false
  end
end

# execute the following only if the file is directly run
# Main program
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
    when "list_metadata"
      puts text_embeddings.list_metadata
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
