#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"
require "open3"
require "securerandom"
require "pg"
require_relative "../../lib/monadic/utils/environment"

# Configuration
EXPORT_DIR = File.expand_path("../../../../../docker/services/pgvector/help_data", __dir__)
CONTAINER = "monadic-chat-pgvector-container"

class HelpDatabaseExporter
  def initialize
    # Ensure export directory exists
    FileUtils.mkdir_p(EXPORT_DIR)
  end
  
  def export_all
    puts "Exporting help database..."
    
    # Check if container is running
    unless container_running?
      puts "Error: pgvector container is not running"
      return false
    end
    
    # Check if database exists
    unless database_exists?
      puts "Help database does not exist. Creating empty export files."
      create_empty_export()
      return true
    end
    
    # Export schema
    export_schema
    
    # Export data
    export_data
    
    # Generate export metadata
    generate_metadata
    
    puts "Export completed successfully!"
    true
  rescue => e
    puts "Error during export: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    false
  end
  
  private
  
  def container_running?
    system("docker ps --format '{{.Names}}' | grep -q '#{CONTAINER}'", out: File::NULL, err: File::NULL)
  end
  
  def database_exists?
    begin
      # Check if database exists
      conn = PG.connect(Monadic::Utils::Environment.postgres_params)
      result = conn.exec("SELECT 1 FROM pg_database WHERE datname = 'monadic_help'")
      conn.close
      return false if result.ntuples == 0
      
      # Check if help_docs table exists
      conn = PG.connect(Monadic::Utils::Environment.postgres_params(database: "monadic_help"))
      result = conn.exec("SELECT 1 FROM information_schema.tables WHERE table_name = 'help_docs'")
      exists = result.ntuples > 0
      conn.close
      exists
    rescue PG::Error => e
      puts "Database connection error: #{e.message}"
      false
    end
  end
  
  def export_schema
    schema_file = File.join(EXPORT_DIR, "schema.sql")
    
    # Get the schema by dumping from the container
    schema_sql = <<~SQL
      -- Create help database if not exists
      SELECT 'CREATE DATABASE monadic_help;' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'monadic_help');
      
      \\c monadic_help;
      
      -- Create pgvector extension
      CREATE EXTENSION IF NOT EXISTS vector;
      
      -- Create help_docs table
      CREATE TABLE IF NOT EXISTS help_docs (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL,
        section TEXT NOT NULL,
        language VARCHAR(10) NOT NULL,
        items INTEGER NOT NULL,
        is_internal BOOLEAN DEFAULT FALSE,
        metadata JSONB NOT NULL,
        embedding vector(3072),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(file_path, language)
      );

      -- Create help_items table
      CREATE TABLE IF NOT EXISTS help_items (
        id SERIAL PRIMARY KEY,
        doc_id INTEGER REFERENCES help_docs(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        position INTEGER NOT NULL,
        heading TEXT,
        is_internal BOOLEAN DEFAULT FALSE,
        metadata JSONB NOT NULL,
        embedding vector(3072),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      -- Create indexes for better performance
      -- Note: ivfflat indexes removed due to 2000 dimension limit with text-embedding-3-large (3072 dims)
      -- Consider using HNSW index or no vector index for now
      CREATE INDEX IF NOT EXISTS idx_help_items_doc_id ON help_items(doc_id);
      CREATE INDEX IF NOT EXISTS idx_help_docs_language ON help_docs(language);
      CREATE INDEX IF NOT EXISTS idx_help_docs_file_path ON help_docs(file_path);
      CREATE INDEX IF NOT EXISTS idx_help_docs_is_internal ON help_docs(is_internal);
      CREATE INDEX IF NOT EXISTS idx_help_items_is_internal ON help_items(is_internal);
    SQL
    
    File.write(schema_file, schema_sql)
    puts "Schema exported to #{schema_file}"
  end
  
  def export_data
    # Export help_docs
    docs_file = File.join(EXPORT_DIR, "help_docs.json")
    
    begin
      # Connect directly to PostgreSQL
      conn = PG.connect(Monadic::Utils::Environment.postgres_params(database: "monadic_help"))
      
      # Export help_docs (external documentation only)
      result = conn.exec("SELECT * FROM help_docs WHERE is_internal = FALSE ORDER BY id")
      docs = []
      result.each do |row|
        doc = {
          "id" => row["id"].to_i,
          "title" => row["title"],
          "file_path" => row["file_path"],
          "section" => row["section"],
          "language" => row["language"],
          "items" => row["items"].to_i,
          "metadata" => JSON.parse(row["metadata"]),
          "created_at" => row["created_at"],
          "updated_at" => row["updated_at"]
        }
        
        # Convert embedding if present
        if row["embedding"]
          doc["embedding"] = decode_vector(row["embedding"])
        end
        
        docs << doc
      end
      
      File.write(docs_file, JSON.pretty_generate(docs))
      puts "Exported #{docs.length} documents to #{docs_file}"
      
      conn.close
    rescue PG::Error => e
      puts "Error exporting documents: #{e.message}"
      return false
    end
    
    # Export help_items
    items_file = File.join(EXPORT_DIR, "help_items.json")
    
    begin
      # Reuse or create new connection
      conn = PG.connect(Monadic::Utils::Environment.postgres_params(database: "monadic_help"))
      
      # Export help_items (external documentation only - join with help_docs to filter)
      result = conn.exec("SELECT hi.* FROM help_items hi JOIN help_docs hd ON hi.doc_id = hd.id WHERE hd.is_internal = FALSE ORDER BY hi.id")
      items = []
      result.each do |row|
        item = {
          "id" => row["id"].to_i,
          "doc_id" => row["doc_id"].to_i,
          "text" => row["text"],
          "position" => row["position"].to_i,
          "heading" => row["heading"],
          "metadata" => JSON.parse(row["metadata"]),
          "created_at" => row["created_at"]
        }
        
        # Convert embedding if present
        if row["embedding"]
          item["embedding"] = decode_vector(row["embedding"])
        end
        
        items << item
      end
      
      File.write(items_file, JSON.pretty_generate(items))
      puts "Exported #{items.length} items to #{items_file}"
      
      conn.close
    rescue PG::Error => e
      puts "Error exporting items: #{e.message}"
      return false
    end
  end
  
  def decode_vector(vector_string)
    # PostgreSQL vector type returns string like "[0.1,0.2,...]"
    vector_string[1..-2].split(",").map(&:to_f)
  end
  
  def generate_metadata
    begin
      # Connect directly to get counts
      conn = PG.connect(Monadic::Utils::Environment.postgres_params(database: "monadic_help"))
      
      docs_result = conn.exec("SELECT COUNT(*) FROM help_docs")
      docs_count = docs_result[0]["count"].to_i
      
      items_result = conn.exec("SELECT COUNT(*) FROM help_items")
      items_count = items_result[0]["count"].to_i
      
      conn.close
    rescue PG::Error => e
      puts "Error getting counts: #{e.message}"
      docs_count = 0
      items_count = 0
    end
    
    metadata = {
      export_date: Time.now.to_s,
      export_id: SecureRandom.hex(16),
      docs_count: docs_count,
      items_count: items_count
    }
    
    metadata_file = File.join(EXPORT_DIR, "metadata.json")
    File.write(metadata_file, JSON.pretty_generate(metadata))
    
    # Also create a simple ID file for MD5 checking
    id_file = File.join(EXPORT_DIR, "export_id.txt")
    File.write(id_file, metadata[:export_id])
    
    puts "Export ID: #{metadata[:export_id]}"
    puts "Metadata saved to #{metadata_file}"
  end
  
  def create_empty_export
    # Create schema file
    export_schema
    
    # Create empty JSON files
    docs_file = File.join(EXPORT_DIR, "help_docs.json")
    items_file = File.join(EXPORT_DIR, "help_items.json")
    
    File.write(docs_file, "[]")
    File.write(items_file, "[]")
    
    # Create metadata
    metadata = {
      export_date: Time.now.to_s,
      export_id: SecureRandom.hex(16),
      docs_count: 0,
      items_count: 0
    }
    
    metadata_file = File.join(EXPORT_DIR, "metadata.json")
    File.write(metadata_file, JSON.pretty_generate(metadata))
    
    # Create ID file
    id_file = File.join(EXPORT_DIR, "export_id.txt")
    File.write(id_file, metadata[:export_id])
    
    puts "Created empty export files"
  end
end

# Run export if called directly
if __FILE__ == $0
  exporter = HelpDatabaseExporter.new
  exporter.export_all
end