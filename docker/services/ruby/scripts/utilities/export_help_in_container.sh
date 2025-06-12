#!/bin/bash
# This script runs the help database export from inside the Ruby container

docker exec monadic-chat-ruby-container bash -c '
  cd /monadic
  
  # Create a temporary Ruby script to export the help database
  cat > /tmp/export_help.rb << "EOF"
#!/usr/bin/env ruby
# frozen_string_literal: true

# Define IN_CONTAINER constant
IN_CONTAINER = true

$LOAD_PATH.unshift("/monadic/lib")
require "monadic/utils/help_embeddings"
require "json"
require "fileutils"
require "securerandom"

# Configuration
EXPORT_DIR = "/monadic/help_data_export"

class HelpDatabaseExporter
  def initialize
    @help_db = HelpEmbeddings.new
    FileUtils.mkdir_p(EXPORT_DIR)
  end
  
  def export_all
    puts "Exporting help database from inside container..."
    
    # Export schema
    export_schema
    
    # Export data
    export_data
    
    # Generate metadata
    generate_metadata
    
    puts "Export completed successfully!"
    true
  rescue => e
    puts "Error during export: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    false
  end
  
  private
  
  def export_schema
    schema_file = File.join(EXPORT_DIR, "schema.sql")
    
    schema_sql = <<~SQL
      -- Create help database if not exists
      CREATE DATABASE IF NOT EXISTS monadic_help;
      
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
        metadata JSONB NOT NULL,
        embedding vector(3072),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      -- Create indexes for better performance
      -- Note: ivfflat indexes removed due to 2000 dimension limit with text-embedding-3-large (3072 dims)
      -- Consider using HNSW index or no vector index for now
      CREATE INDEX IF NOT EXISTS idx_help_items_doc_id ON help_items(doc_id);
      CREATE INDEX IF NOT EXISTS idx_help_docs_language ON help_docs(language);
    SQL
    
    File.write(schema_file, schema_sql)
    puts "Schema exported to #{schema_file}"
  end
  
  def export_data
    # Export help_docs
    docs_file = File.join(EXPORT_DIR, "help_docs.json")
    docs = @help_db.list_help_sections
    
    # Add full document data including embeddings
    full_docs = []
    docs.each do |doc|
      # Get the full document with embedding from database
      result = @help_db.conn.exec_params(
        "SELECT * FROM help_docs WHERE id = $1",
        [doc[:doc_id]]
      )
      
      if result.ntuples > 0
        row = result.first
        full_doc = {
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
        full_docs << full_doc
      end
    end
    
    File.write(docs_file, JSON.pretty_generate(full_docs))
    puts "Exported #{full_docs.length} documents to #{docs_file}"
    
    # Export help_items
    items_file = File.join(EXPORT_DIR, "help_items.json")
    items = []
    
    # Get all items
    result = @help_db.conn.exec("SELECT * FROM help_items ORDER BY id")
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
    stats = @help_db.get_stats
    
    metadata = {
      export_date: Time.now.to_s,
      export_id: SecureRandom.hex(16),
      docs_count: stats[:documents_by_language].values.sum,
      items_count: stats[:total_items]
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

# Run export
exporter = HelpDatabaseExporter.new
exporter.export_all
EOF
  
  # Run the export script
  ruby /tmp/export_help.rb
'

# Copy exported files from container to host
docker cp monadic-chat-ruby-container:/monadic/help_data_export/. /Users/yohasebe/code/monadic-chat/docker/services/pgvector/help_data/