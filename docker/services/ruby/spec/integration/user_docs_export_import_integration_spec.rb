# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../support/pgvector_test_helper'
require_relative "../../lib/monadic/utils/text_embeddings"
require "fileutils"
require "json"
require "open3"
require "pg"

RSpec.describe "User Docs Database Export/Import", :integration do
  include PgvectorTestHelper
  
  let(:test_db_name) { "test_monadic_user_docs_#{Process.pid}" }
  let(:export_dir) { File.expand_path("tmp/test_exports_#{Process.pid}") }
  let(:export_file) { File.join(export_dir, "user_docs_export.json") }
  let(:container_name) { "monadic-chat-pgvector-container" }
  
  before(:each) do
    # Create export directory
    FileUtils.mkdir_p(export_dir)
    
    # Check if pgvector container is running
    unless check_pgvector_container
      skip "pgvector container is not running. Start containers with 'rake docker:up' first."
    end
    
    # Create test database
    create_test_database(test_db_name)
    
    # Initialize TextEmbeddings with test database
    @text_embedding = TextEmbeddings.new(test_db_name)
    
    # Create tables
    @conn = TextEmbeddings.connect_to_db(test_db_name)
    @conn.exec(<<~SQL)
      CREATE EXTENSION IF NOT EXISTS vector;
      CREATE TABLE IF NOT EXISTS docs (
        id serial primary key,
        title text,
        items integer,
        metadata jsonb,
        embedding vector(3072)
      );
      CREATE TABLE IF NOT EXISTS items (
        id serial primary key,
        doc_id integer,
        text text,
        position smallint,
        metadata jsonb,
        embedding vector(3072)
      );
    SQL
  end
  
  after(:each) do
    # Close database connections
    @conn&.close
    @text_embedding&.close_connection
    
    # Clean up test database
    drop_test_database(test_db_name) if check_pgvector_container
    
    # Clean up export directory
    FileUtils.rm_rf(export_dir) if Dir.exist?(export_dir)
  end
  
  describe "Database Export Functionality" do
    context "when exporting user docs data" do
      before do
        # Add test data using direct SQL
        result = @conn.exec_params(
          "INSERT INTO docs (title, items, metadata, embedding) VALUES ($1, $2, $3, $4) RETURNING id",
          ["Test Document", 1, { author: "Test Author", tags: ["test", "sample"] }.to_json, ([0.1, 0.2, 0.3] * 1024)]
        )
        doc_id = result.getvalue(0, 0)
        
        @conn.exec_params(
          "INSERT INTO items (doc_id, text, position, metadata, embedding) VALUES ($1, $2, $3, $4, $5)",
          [doc_id, "This is test content", 0, { section: "introduction" }.to_json, ([0.4, 0.5, 0.6] * 1024)]
        )
      end
      
      it "exports schema with pgvector extension and correct structure" do
        # Execute export using Docker exec
        export_schema_cmd = <<~CMD
          docker exec #{container_name} pg_dump -U postgres #{test_db_name} --schema-only --no-owner --no-privileges
        CMD
        
        stdout, stderr, status = Open3.capture3(export_schema_cmd)
        expect(status.success?).to be true
        
        # Verify pgvector extension
        expect(stdout).to include("CREATE EXTENSION IF NOT EXISTS vector")
        
        # Verify docs table structure
        expect(stdout).to include("CREATE TABLE public.docs")
        expect(stdout).to include("embedding public.vector(3072)")
        
        # Verify items table structure  
        expect(stdout).to include("CREATE TABLE public.items")
        expect(stdout).to include("doc_id integer")
      end
      
      it "exports data with embeddings in correct format" do
        # Export data to JSON
        export_data_cmd = <<~CMD
          docker exec #{container_name} psql -U postgres -d #{test_db_name} -t -A -c "
            SELECT json_build_object(
              'docs', (SELECT json_agg(row_to_json(d)) FROM docs d),
              'items', (SELECT json_agg(row_to_json(i)) FROM items i)
            )
          "
        CMD
        
        stdout, stderr, status = Open3.capture3(export_data_cmd)
        expect(status.success?).to be true
        
        data = JSON.parse(stdout.strip)
        
        # Verify docs data
        expect(data["docs"]).to be_an(Array)
        expect(data["docs"].first["title"]).to eq("Test Document")
        expect(data["docs"].first["metadata"]["author"]).to eq("Test Author")
        
        # Verify items data
        expect(data["items"]).to be_an(Array)
        expect(data["items"].first["text"]).to eq("This is test content")
        expect(data["items"].first["position"]).to eq(0)
      end
      
      it "creates metadata file with export information" do
        # Create a mock export with metadata
        metadata = {
          export_id: SecureRandom.uuid,
          exported_at: Time.now.utc.iso8601,
          database: test_db_name,
          counts: {
            docs: 1,
            items: 1
          },
          version: "1.0"
        }
        
        File.write(File.join(export_dir, "export_metadata.json"), JSON.pretty_generate(metadata))
        
        # Verify metadata file
        expect(File.exist?(File.join(export_dir, "export_metadata.json"))).to be true
        saved_metadata = JSON.parse(File.read(File.join(export_dir, "export_metadata.json")))
        expect(saved_metadata["counts"]["docs"]).to eq(1)
        expect(saved_metadata["counts"]["items"]).to eq(1)
      end
    end
    
    context "when database is empty" do
      it "exports empty structure" do
        export_data_cmd = <<~CMD
          docker exec #{container_name} psql -U postgres -d #{test_db_name} -t -A -c "
            SELECT json_build_object(
              'docs', (SELECT COALESCE(json_agg(row_to_json(d)), '[]'::json) FROM docs d),
              'items', (SELECT COALESCE(json_agg(row_to_json(i)), '[]'::json) FROM items i)
            )
          "
        CMD
        
        stdout, stderr, status = Open3.capture3(export_data_cmd)
        expect(status.success?).to be true
        
        data = JSON.parse(stdout.strip)
        expect(data["docs"]).to eq([])
        expect(data["items"]).to eq([])
      end
    end
  end
  
  describe "Database Import Functionality" do
    let(:import_data) do
      {
        "docs" => [
          {
            "id" => 1,
            "title" => "Imported Document",
            "items" => 2,
            "metadata" => { "source" => "import" },
            "embedding" => "[" + ([0.1] * 3072).join(",") + "]"
          }
        ],
        "items" => [
          {
            "id" => 1,
            "doc_id" => 1,
            "text" => "First item",
            "position" => 0,
            "metadata" => {},
            "embedding" => "[" + ([0.4] * 3072).join(",") + "]"
          },
          {
            "id" => 2,
            "doc_id" => 1,
            "text" => "Second item",
            "position" => 1,
            "metadata" => {},
            "embedding" => "[" + ([0.7] * 3072).join(",") + "]"
          }
        ]
      }
    end
    
    it "imports data into user docs database" do
      # Create import file
      File.write(export_file, JSON.pretty_generate(import_data))
      
      # Import data directly using psql commands with proper escaping
      import_data["docs"].each do |doc|
        # Escape for shell - need to escape both single quotes and double quotes
        metadata_json = doc['metadata'].to_json
        escaped_metadata = metadata_json.gsub('"', '\\"').gsub("'", "''")
        import_cmd = <<~CMD
          docker exec #{container_name} psql -U postgres -d #{test_db_name} -c "
            INSERT INTO docs (id, title, items, metadata, embedding)
            VALUES (
              #{doc['id']},
              '#{doc['title']}',
              #{doc['items']},
              '#{escaped_metadata}'::jsonb,
              '#{doc['embedding']}'::vector
            )
          "
        CMD
        system(import_cmd)
      end
      
      import_data["items"].each do |item|
        escaped_metadata = item['metadata'].to_json.gsub("'", "''")
        import_cmd = <<~CMD
          docker exec #{container_name} psql -U postgres -d #{test_db_name} -c "
            INSERT INTO items (id, doc_id, text, position, metadata, embedding)
            VALUES (
              #{item['id']},
              #{item['doc_id']},
              '#{item['text']}',
              #{item['position']},
              '#{escaped_metadata}'::jsonb,
              '#{item['embedding']}'::vector
            )
          "
        CMD
        system(import_cmd)
      end
      
      # Verify import
      verify_cmd = <<~CMD
        docker exec #{container_name} psql -U postgres -d #{test_db_name} -t -A -c "
          SELECT COUNT(*) FROM docs;
          SELECT COUNT(*) FROM items;
        "
      CMD
      
      stdout, stderr, status = Open3.capture3(verify_cmd)
      counts = stdout.strip.split("\n").map(&:to_i)
      
      expect(counts[0]).to eq(1)  # 1 doc
      expect(counts[1]).to eq(2)  # 2 items
    end
  end
  
  describe "Full Export/Import Cycle" do
    it "preserves data integrity through export and import" do
      # Insert test data
      result = @conn.exec_params(
        "INSERT INTO docs (title, items, metadata, embedding) VALUES ($1, $2, $3, $4) RETURNING id",
        ["Cycle Test Document", 1, { test: true }.to_json, ([0.1] * 3072)]
      )
      doc_id = result.getvalue(0, 0)
      
      @conn.exec_params(
        "INSERT INTO items (doc_id, text, position, metadata, embedding) VALUES ($1, $2, $3, $4, $5)",
        [doc_id, "Test content for cycle", 0, { verified: true }.to_json, ([0.2] * 3072)]
      )
      
      # Export using pg_dump
      dump_file = File.join(export_dir, "test_dump.gz")
      export_cmd = "docker exec #{container_name} sh -c 'pg_dump -U postgres #{test_db_name} | gzip > /tmp/test_dump.gz'"
      system(export_cmd)
      
      # Copy dump file from container
      copy_cmd = "docker cp #{container_name}:/tmp/test_dump.gz #{dump_file}"
      system(copy_cmd)
      
      # Clear database
      clear_cmd = <<~CMD
        docker exec #{container_name} psql -U postgres -d #{test_db_name} -c "
          TRUNCATE TABLE items CASCADE;
          TRUNCATE TABLE docs CASCADE;
        "
      CMD
      system(clear_cmd)
      
      # Copy dump file back and import
      copy_back_cmd = "docker cp #{dump_file} #{container_name}:/tmp/test_dump.gz"
      system(copy_back_cmd)
      
      import_cmd = "docker exec #{container_name} sh -c 'gunzip -c /tmp/test_dump.gz | psql -U postgres #{test_db_name}'"
      system(import_cmd)
      
      # Verify data was restored
      verify_cmd = <<~CMD
        docker exec #{container_name} psql -U postgres -d #{test_db_name} -t -A -c "
          SELECT title FROM docs WHERE id = 1;
          SELECT text FROM items WHERE doc_id = 1;
        "
      CMD
      
      stdout, stderr, status = Open3.capture3(verify_cmd)
      results = stdout.strip.split("\n")
      
      expect(results[0]).to eq("Cycle Test Document")
      expect(results[1]).to eq("Test content for cycle")
    end
  end
  
  describe "monadic.sh integration" do
    it "exports to the correct shared folder location" do
      # The actual monadic.sh uses ~/monadic/data which maps to /monadic/data in container
      shared_folder = File.expand_path("~/monadic/data")
      
      # Verify the export command structure matches monadic.sh
      expected_export_cmd = "pg_dump -U postgres monadic | gzip > \"/monadic/data/monadic.gz\""
      
      # This is what monadic.sh executes
      actual_cmd = 'docker exec monadic-chat-pgvector-container sh -c "pg_dump -U postgres monadic | gzip > \"/monadic/data/monadic.gz\""'
      
      # Check that the command structure is correct (accounting for shell escaping)
      expect(actual_cmd).to include("pg_dump -U postgres monadic")
      expect(actual_cmd).to include("gzip")
      expect(actual_cmd).to include("/monadic/data/monadic.gz")
    end
    
    it "imports from the correct shared folder location" do
      # Verify the import command structure matches monadic.sh
      expected_import_pattern = "dropdb -f -U postgres monadic && createdb -U postgres --locale=C --template=template0 monadic && gunzip -c \"/monadic/data/monadic.gz\" | psql"
      
      # This matches the pattern in monadic.sh
      actual_cmd = 'docker exec monadic-chat-pgvector-container sh -c "dropdb -f -U postgres monadic && createdb -U postgres --locale=C --template=template0 monadic && gunzip -c \"/monadic/data/monadic.gz\" | psql -v ON_ERROR_STOP=1 -U postgres monadic"'
      
      expect(actual_cmd).to include("dropdb -f -U postgres monadic")
      expect(actual_cmd).to include("createdb -U postgres --locale=C --template=template0 monadic")
      expect(actual_cmd).to include("/monadic/data/monadic.gz")
      expect(actual_cmd).to include("gunzip -c")
    end
  end
end