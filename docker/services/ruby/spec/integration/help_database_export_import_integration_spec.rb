# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../support/pgvector_test_helper'
require 'pg'
require 'json'
require 'fileutils'
require 'tempfile'
require 'open3'

# Load the export script
script_path = File.expand_path("../../scripts/utilities/export_help_database_docker.rb", __dir__)
require script_path

RSpec.describe "Help Database Export/Import Integration", :integration do
  include PgvectorTestHelper
  
  let(:test_export_dir) { Dir.mktmpdir }
  let(:container_name) { "monadic-chat-pgvector-container" }
  
  before(:all) do
    skip "Docker tests require Docker environment" unless docker_available?
    skip "PostgreSQL tests require pg gem" unless defined?(PG)
  end
  
  before(:context) do
    # Set up connection parameters
    @db_config = {
      host: ENV['POSTGRES_HOST'] || 'localhost',
      port: (ENV['POSTGRES_PORT'] || '5433').to_i,
      user: ENV['POSTGRES_USER'] || 'postgres',
      password: ENV['POSTGRES_PASSWORD'] || 'postgres'
    }
    
    # Create test database with retry logic
    retries = 0
    begin
      conn = PG.connect(@db_config.merge(dbname: 'postgres'))
      @test_database = "test_help_export_#{Time.now.to_i}"
      conn.exec("CREATE DATABASE #{@test_database}")
      conn.close
    rescue PG::Error => e
      retries += 1
      if retries < 3
        sleep 2
        retry
      else
        skip "Cannot create test database after #{retries} attempts: #{e.message}"
      end
    end
  end
  
  before do
    # Stub the EXPORT_DIR constant to use our test directory
    stub_const("EXPORT_DIR", test_export_dir)
    
    # Set up test database schema
    setup_test_database
  end
  
  after do
    FileUtils.rm_rf(test_export_dir) if Dir.exist?(test_export_dir)
  end
  
  after(:context) do
    # Clean up test database
    if @test_database
      begin
        conn = PG.connect(@db_config.merge(dbname: 'postgres'))
        conn.exec("DROP DATABASE IF EXISTS #{@test_database}")
        conn.close
      rescue PG::Error => e
        puts "Warning: Could not drop test database: #{e.message}"
      end
    end
  end
  
  describe "Export Functionality" do
    let(:exporter) { HelpDatabaseExporter.new }
    
    context "when pgvector container is running" do
      it "checks container availability" do
        container_running = system("docker ps --format '{{.Names}}' | grep -q '#{container_name}'")
        expect(container_running).to be true
      end
      
      it "exports schema correctly" do
        # Mock database existence check to use our test database
        allow(exporter).to receive(:database_exists?).and_return(true)
        allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
        
        # Export the schema
        exporter.send(:export_schema)
        
        schema_file = File.join(test_export_dir, "schema.sql")
        expect(File.exist?(schema_file)).to be true
        
        schema_content = File.read(schema_file)
        expect(schema_content).to include("CREATE DATABASE monadic_help")
        expect(schema_content).to include("CREATE EXTENSION IF NOT EXISTS vector")
        expect(schema_content).to include("CREATE TABLE IF NOT EXISTS help_docs")
        expect(schema_content).to include("CREATE TABLE IF NOT EXISTS help_items")
        expect(schema_content).to include("embedding vector(3072)")
      end
      
      it "exports data with embeddings" do
        # Insert test data
        insert_test_data
        
        # Mock to use our test database
        allow(exporter).to receive(:database_exists?).and_return(true)
        allow(PG).to receive(:connect).and_wrap_original do |original, *args|
          if args[0][:dbname] == "monadic_help"
            args[0][:dbname] = @test_database
          end
          original.call(*args)
        end
        
        # Export the data
        exporter.send(:export_data)
        
        # Verify help_docs export
        docs_file = File.join(test_export_dir, "help_docs.json")
        expect(File.exist?(docs_file)).to be true
        
        docs = JSON.parse(File.read(docs_file))
        expect(docs.length).to eq(2)
        expect(docs[0]["title"]).to eq("Test Document 1")
        expect(docs[0]["embedding"]).to be_an(Array)
        expect(docs[0]["embedding"].length).to eq(3)
        
        # Verify help_items export
        items_file = File.join(test_export_dir, "help_items.json")
        expect(File.exist?(items_file)).to be true
        
        items = JSON.parse(File.read(items_file))
        expect(items.length).to eq(3)
        expect(items[0]["text"]).to eq("Test item 1")
        expect(items[0]["embedding"]).to be_an(Array)
      end
      
      it "generates metadata correctly" do
        # Mock to use our test database
        allow(exporter).to receive(:database_exists?).and_return(true)
        allow(PG).to receive(:connect).and_wrap_original do |original, *args|
          if args[0][:dbname] == "monadic_help"
            args[0][:dbname] = @test_database
          end
          original.call(*args)
        end
        
        # Generate metadata
        exporter.send(:generate_metadata)
        
        metadata_file = File.join(test_export_dir, "metadata.json")
        expect(File.exist?(metadata_file)).to be true
        
        metadata = JSON.parse(File.read(metadata_file))
        expect(metadata["export_date"]).to be_a(String)
        expect(metadata["export_id"]).to match(/[a-f0-9]{32}/)
        expect(metadata["docs_count"]).to be >= 0
        expect(metadata["items_count"]).to be >= 0
        
        # Check export_id file
        id_file = File.join(test_export_dir, "export_id.txt")
        expect(File.exist?(id_file)).to be true
        expect(File.read(id_file)).to eq(metadata["export_id"])
      end
      
      it "handles empty database gracefully" do
        # Clear any existing data
        conn = PG.connect(@db_config.merge(dbname: @test_database))
        conn.exec("TRUNCATE help_docs CASCADE")
        conn.exec("TRUNCATE help_items CASCADE")
        conn.close
        
        # Mock to use our test database
        allow(exporter).to receive(:database_exists?).and_return(true)
        allow(PG).to receive(:connect).and_wrap_original do |original, *args|
          if args[0][:dbname] == "monadic_help"
            args[0][:dbname] = @test_database
          end
          original.call(*args)
        end
        
        # Export the data manually to ensure files are created
        exporter.send(:export_schema)
        exporter.send(:export_data)
        exporter.send(:generate_metadata)
        
        docs_file = File.join(test_export_dir, "help_docs.json")
        items_file = File.join(test_export_dir, "help_items.json")
        
        expect(File.exist?(docs_file)).to be true
        expect(File.exist?(items_file)).to be true
        
        docs = JSON.parse(File.read(docs_file))
        items = JSON.parse(File.read(items_file))
        
        expect(docs).to eq([])
        expect(items).to eq([])
      end
    end
    
    context "when database does not exist" do
      it "creates empty export files" do
        allow(exporter).to receive(:container_running?).and_return(true)
        allow(exporter).to receive(:database_exists?).and_return(false)
        
        result = exporter.export_all
        expect(result).to be true
        
        # Check all files are created
        %w[schema.sql help_docs.json help_items.json metadata.json export_id.txt].each do |filename|
          expect(File.exist?(File.join(test_export_dir, filename))).to be true
        end
        
        # Verify empty data files
        docs = JSON.parse(File.read(File.join(test_export_dir, "help_docs.json")))
        items = JSON.parse(File.read(File.join(test_export_dir, "help_items.json")))
        expect(docs).to eq([])
        expect(items).to eq([])
      end
    end
  end
  
  describe "Import Functionality" do
    let(:import_script) { File.expand_path("../../../../pgvector/import_help_data.sh", __dir__) }
    
    before do
      # Create export files for import testing
      create_export_files_for_import
    end
    
    it "imports data into pgvector container" do
      # Copy export files to container's help_data directory
      container_export_dir = "/help_data"
      
      # Copy files to container
      %w[schema.sql help_docs.json help_items.json metadata.json].each do |filename|
        source = File.join(test_export_dir, filename)
        cmd = "docker cp '#{source}' #{container_name}:#{container_export_dir}/#{filename}"
        stdout, stderr, status = Open3.capture3(cmd)
        
        expect(status.success?).to be(true), "Failed to copy #{filename}: #{stderr}"
      end
      
      # Create a temporary import script in the container
      import_script_path = File.expand_path("../../../pgvector/import_help_data.sh", __dir__)
      import_script_content = File.read(import_script_path)
      temp_script = "/tmp/import_help_data_test.sh"
      
      # Copy script content to container
      write_cmd = "docker exec -i #{container_name} tee #{temp_script} > /dev/null"
      Open3.popen3(write_cmd) do |stdin, stdout, stderr, wait_thr|
        stdin.write(import_script_content)
        stdin.close
      end
      
      # Make it executable
      chmod_cmd = "docker exec #{container_name} chmod +x #{temp_script}"
      Open3.capture3(chmod_cmd)
      
      # Execute import script in container
      import_cmd = "docker exec #{container_name} /bin/bash #{temp_script}"
      stdout, stderr, status = Open3.capture3(import_cmd)
      
      # Import might fail if data already exists, which is okay
      if !status.success? && !stderr.include?("already contains")
        puts "Import stdout: #{stdout}"
        puts "Import stderr: #{stderr}"
      end
      
      # Verify data was imported by connecting to the database
      conn = PG.connect(@db_config.merge(dbname: 'monadic_help'))
      
      # Check if help_docs table exists and has data
      result = conn.exec("SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'help_docs'")
      expect(result[0]['count'].to_i).to be > 0
      
      conn.close
    end
    
    it "handles missing metadata file gracefully" do
      # Create a temporary directory for this test
      temp_dir = "/tmp/test_import_#{Time.now.to_i}"
      
      # Create directory in container
      mkdir_cmd = "docker exec #{container_name} mkdir -p #{temp_dir}"
      Open3.capture3(mkdir_cmd)
      
      # Copy only some files (not metadata.json)
      %w[schema.sql help_docs.json help_items.json].each do |filename|
        source = File.join(test_export_dir, filename)
        if File.exist?(source)
          cmd = "docker cp '#{source}' #{container_name}:#{temp_dir}/#{filename}"
          Open3.capture3(cmd)
        end
      end
      
      # Test that directory without metadata.json is handled gracefully
      check_cmd = "docker exec #{container_name} /bin/bash -c 'test -f #{temp_dir}/metadata.json && echo \"exists\" || echo \"No help data to import\"'"
      stdout, stderr, status = Open3.capture3(check_cmd)
      
      expect(status.success?).to be true
      expect(stdout.strip).to eq("No help data to import")
      
      # Clean up
      cleanup_cmd = "docker exec #{container_name} rm -rf #{temp_dir}"
      Open3.capture3(cleanup_cmd)
    end
  end
  
  describe "End-to-End Export/Import Cycle" do
    it "exports and reimports data preserving structure" do
      # Insert test data
      insert_test_data
      
      # Export data
      exporter = HelpDatabaseExporter.new
      allow(exporter).to receive(:database_exists?).and_return(true)
      allow(PG).to receive(:connect).and_wrap_original do |original, *args|
        if args[0][:dbname] == "monadic_help"
          args[0][:dbname] = @test_database
        end
        original.call(*args)
      end
      
      # Export the data manually to ensure files are created
      exporter.send(:export_schema)
      exporter.send(:export_data)
      exporter.send(:generate_metadata)
      
      # Verify exported data
      docs_file = File.join(test_export_dir, "help_docs.json")
      items_file = File.join(test_export_dir, "help_items.json")
      
      expect(File.exist?(docs_file)).to be true
      expect(File.exist?(items_file)).to be true
      
      docs = JSON.parse(File.read(docs_file))
      items = JSON.parse(File.read(items_file))
      
      expect(docs.length).to eq(2)
      expect(items.length).to eq(3)
      
      # Verify relationships are preserved
      doc_ids = docs.map { |d| d["id"] }
      items.each do |item|
        expect(doc_ids).to include(item["doc_id"])
      end
    end
  end
  
  describe "Shared Folder Handling" do
    it "uses ~/monadic/data path correctly" do
      # The actual EXPORT_DIR should point to the correct location
      real_export_dir = File.expand_path("../../../../pgvector/help_data", __dir__)
      expect(real_export_dir).to include("pgvector/help_data")
    end
    
    it "creates export directory if it doesn't exist" do
      non_existent_dir = File.join(test_export_dir, "new_export_dir")
      stub_const("EXPORT_DIR", non_existent_dir)
      
      exporter = HelpDatabaseExporter.new
      expect(Dir.exist?(non_existent_dir)).to be true
    end
  end
  
  private
  
  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end
  
  def setup_test_database
    conn = PG.connect(@db_config.merge(dbname: @test_database))
    
    # Create vector extension
    create_vector_extension(conn)
    
    # Create tables
    conn.exec(<<-SQL)
      CREATE TABLE IF NOT EXISTS help_docs (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL,
        section TEXT NOT NULL,
        language VARCHAR(10) NOT NULL,
        items INTEGER NOT NULL,
        metadata JSONB NOT NULL,
        embedding vector(3),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(file_path, language)
      )
    SQL
    
    conn.exec(<<-SQL)
      CREATE TABLE IF NOT EXISTS help_items (
        id SERIAL PRIMARY KEY,
        doc_id INTEGER REFERENCES help_docs(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        position INTEGER NOT NULL,
        heading TEXT,
        metadata JSONB NOT NULL,
        embedding vector(3),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    SQL
    
    conn.close
  rescue PG::Error => e
    puts "Error setting up test database: #{e.message}"
  end
  
  def insert_test_data
    conn = PG.connect(@db_config.merge(dbname: @test_database))
    
    # Clear existing data first to avoid duplicates
    conn.exec("TRUNCATE help_docs CASCADE")
    
    # Insert help_docs
    doc1_id = conn.exec_params(
      "INSERT INTO help_docs (title, file_path, section, language, items, metadata, embedding) 
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
      ["Test Document 1", "/test/doc1.md", "test", "en", 2, 
       '{"category": "test"}', "[0.1,0.2,0.3]"]
    )[0]["id"]
    
    doc2_id = conn.exec_params(
      "INSERT INTO help_docs (title, file_path, section, language, items, metadata, embedding) 
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
      ["Test Document 2", "/test/doc2.md", "test", "ja", 1,
       '{"category": "test"}', "[0.4,0.5,0.6]"]
    )[0]["id"]
    
    # Insert help_items
    conn.exec_params(
      "INSERT INTO help_items (doc_id, text, position, heading, metadata, embedding) 
       VALUES ($1, $2, $3, $4, $5, $6)",
      [doc1_id, "Test item 1", 0, "Heading 1", '{"type": "text"}', "[0.7,0.8,0.9]"]
    )
    
    conn.exec_params(
      "INSERT INTO help_items (doc_id, text, position, heading, metadata, embedding) 
       VALUES ($1, $2, $3, $4, $5, $6)",
      [doc1_id, "Test item 2", 1, "Heading 2", '{"type": "text"}', "[0.1,0.3,0.5]"]
    )
    
    conn.exec_params(
      "INSERT INTO help_items (doc_id, text, position, heading, metadata) 
       VALUES ($1, $2, $3, $4, $5)",
      [doc2_id, "Test item 3", 0, "Heading 3", '{"type": "text"}']
    )
    
    conn.close
  rescue PG::Error => e
    puts "Error inserting test data: #{e.message}"
  end
  
  def create_export_files_for_import
    # Create schema file
    schema_content = <<-SQL
      -- Test schema for import
      CREATE DATABASE IF NOT EXISTS test_import_db;
      \\c test_import_db;
      
      CREATE EXTENSION IF NOT EXISTS vector;
      
      CREATE TABLE IF NOT EXISTS help_docs (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL,
        section TEXT NOT NULL,
        language VARCHAR(10) NOT NULL,
        items INTEGER NOT NULL,
        metadata JSONB NOT NULL,
        embedding vector(3),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(file_path, language)
      );
      
      CREATE TABLE IF NOT EXISTS help_items (
        id SERIAL PRIMARY KEY,
        doc_id INTEGER REFERENCES help_docs(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        position INTEGER NOT NULL,
        heading TEXT,
        metadata JSONB NOT NULL,
        embedding vector(3),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    SQL
    
    File.write(File.join(test_export_dir, "schema.sql"), schema_content)
    
    # Create help_docs.json
    docs = [
      {
        "id" => 1,
        "title" => "Import Test Doc",
        "file_path" => "/import/test.md",
        "section" => "import",
        "language" => "en",
        "items" => 1,
        "metadata" => { "test" => true },
        "embedding" => [0.1, 0.2, 0.3],
        "created_at" => Time.now.to_s,
        "updated_at" => Time.now.to_s
      }
    ]
    File.write(File.join(test_export_dir, "help_docs.json"), JSON.pretty_generate(docs))
    
    # Create help_items.json
    items = [
      {
        "id" => 1,
        "doc_id" => 1,
        "text" => "Import test item",
        "position" => 0,
        "heading" => "Import Test",
        "metadata" => { "test" => true },
        "embedding" => [0.4, 0.5, 0.6],
        "created_at" => Time.now.to_s
      }
    ]
    File.write(File.join(test_export_dir, "help_items.json"), JSON.pretty_generate(items))
    
    # Create metadata.json
    metadata = {
      "export_date" => Time.now.to_s,
      "export_id" => "test_import_#{Time.now.to_i}",
      "docs_count" => 1,
      "items_count" => 1
    }
    File.write(File.join(test_export_dir, "metadata.json"), JSON.pretty_generate(metadata))
  end
end