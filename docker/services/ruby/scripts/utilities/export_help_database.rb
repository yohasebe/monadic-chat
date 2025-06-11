#!/usr/bin/env ruby
# frozen_string_literal: true

require "pg"
require "json"
require "fileutils"
require "digest"

# Define IN_CONTAINER constant
IN_CONTAINER = File.file?("/.dockerenv")

# Configuration
DB_HOST = IN_CONTAINER ? "pgvector_service" : "localhost"
DB_NAME = "monadic_help"
EXPORT_DIR = File.expand_path("../../../../../docker/services/pgvector/help_data", __dir__)

class HelpDatabaseExporter
  def initialize
    # First connect to postgres database to check if help database exists
    @conn = PG.connect(
      dbname: "postgres",
      host: DB_HOST,
      port: 5432,
      user: "postgres"
    )
    
    # Ensure export directory exists
    FileUtils.mkdir_p(EXPORT_DIR)
  end
  
  def export_all
    puts "Exporting help database..."
    
    # Check if database exists
    unless database_exists?
      puts "Help database does not exist. Nothing to export."
      return false
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
    false
  ensure
    @conn&.close
  end
  
  private
  
  def database_exists?
    result = @conn.exec("SELECT 1 FROM pg_database WHERE datname = '#{DB_NAME}'")
    result.ntuples > 0
  end
  
  def export_schema
    schema_file = File.join(EXPORT_DIR, "schema.sql")
    
    # Get the schema for help_docs and help_items tables
    schema_sql = <<~SQL
      -- Create help database if not exists
      CREATE DATABASE monadic_help;
      
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
        metadata JSONB NOT NULL,
        embedding vector(1536),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(file_path, language)
      );
      
      -- Create help_items table
      CREATE TABLE IF NOT EXISTS help_items (
        id SERIAL PRIMARY KEY,
        doc_id INTEGER REFERENCES help_docs(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        position INTEGER NOT NULL,
        heading TEXT,
        metadata JSONB NOT NULL,
        embedding vector(1536),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      -- Create indexes for better performance
      CREATE INDEX IF NOT EXISTS idx_help_docs_embedding ON help_docs USING ivfflat (embedding vector_cosine_ops);
      CREATE INDEX IF NOT EXISTS idx_help_items_embedding ON help_items USING ivfflat (embedding vector_cosine_ops);
      CREATE INDEX IF NOT EXISTS idx_help_items_doc_id ON help_items(doc_id);
      CREATE INDEX IF NOT EXISTS idx_help_docs_language ON help_docs(language);
    SQL
    
    File.write(schema_file, schema_sql)
    puts "Schema exported to #{schema_file}"
  end
  
  def export_data
    # Switch to help database
    @conn.close
    @conn = PG.connect(
      dbname: DB_NAME,
      host: DB_HOST,
      port: 5432,
      user: "postgres"
    )
    
    # Export help_docs
    docs_file = File.join(EXPORT_DIR, "help_docs.json")
    docs = []
    
    result = @conn.exec("SELECT * FROM help_docs ORDER BY id")
    result.each do |row|
      doc = {
        id: row["id"].to_i,
        title: row["title"],
        file_path: row["file_path"],
        section: row["section"],
        language: row["language"],
        items: row["items"].to_i,
        metadata: JSON.parse(row["metadata"]),
        embedding: row["embedding"] ? decode_vector(row["embedding"]) : nil,
        created_at: row["created_at"]
      }
      docs << doc
    end
    
    File.write(docs_file, JSON.pretty_generate(docs))
    puts "Exported #{docs.length} documents to #{docs_file}"
    
    # Export help_items
    items_file = File.join(EXPORT_DIR, "help_items.json")
    items = []
    
    result = @conn.exec("SELECT * FROM help_items ORDER BY id")
    result.each do |row|
      item = {
        id: row["id"].to_i,
        doc_id: row["doc_id"].to_i,
        text: row["text"],
        position: row["position"].to_i,
        heading: row["heading"],
        metadata: JSON.parse(row["metadata"]),
        embedding: row["embedding"] ? decode_vector(row["embedding"]) : nil,
        created_at: row["created_at"]
      }
      items << item
    end
    
    File.write(items_file, JSON.pretty_generate(items))
    puts "Exported #{items.length} items to #{items_file}"
  end
  
  def decode_vector(vector_string)
    # PostgreSQL vector type returns string like "[0.1,0.2,...]"
    vector_string[1..-2].split(",").map(&:to_f)
  end
  
  def generate_metadata
    metadata = {
      export_date: Time.now.to_s,
      export_id: SecureRandom.hex(16),
      docs_count: @conn.exec("SELECT COUNT(*) FROM help_docs").first["count"].to_i,
      items_count: @conn.exec("SELECT COUNT(*) FROM help_items").first["count"].to_i
    }
    
    metadata_file = File.join(EXPORT_DIR, "metadata.json")
    File.write(metadata_file, JSON.pretty_generate(metadata))
    
    # Also create a simple ID file for MD5 checking
    id_file = File.join(EXPORT_DIR, "export_id.txt")
    File.write(id_file, metadata[:export_id])
    
    puts "Export ID: #{metadata[:export_id]}"
    puts "Metadata saved to #{metadata_file}"
  end
end

# Run export if called directly
if __FILE__ == $0
  exporter = HelpDatabaseExporter.new
  exporter.export_all
end