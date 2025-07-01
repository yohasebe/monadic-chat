# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"
require "fileutils"
require "pg"

# Load the script to test
script_path = File.expand_path("../../../../scripts/utilities/export_help_database_docker.rb", __dir__)
require script_path

RSpec.describe HelpDatabaseExporter do
  let(:exporter) { HelpDatabaseExporter.new }
  let(:test_export_dir) { Dir.mktmpdir }
  
  before do
    # Stub the EXPORT_DIR constant
    stub_const("EXPORT_DIR", test_export_dir)
    
    # Mock container check
    allow(exporter).to receive(:container_running?).and_return(true)
  end
  
  after do
    FileUtils.rm_rf(test_export_dir) if Dir.exist?(test_export_dir)
  end
  
  describe "#initialize" do
    it "creates export directory" do
      expect(Dir.exist?(test_export_dir)).to be true
    end
  end
  
  describe "#decode_vector" do
    it "decodes PostgreSQL vector string to array" do
      vector_string = "[0.1,0.2,0.3,-0.4]"
      result = exporter.send(:decode_vector, vector_string)
      
      expect(result).to eq([0.1, 0.2, 0.3, -0.4])
    end
    
    it "handles empty vectors" do
      vector_string = "[]"
      result = exporter.send(:decode_vector, vector_string)
      
      expect(result).to eq([])
    end
  end
  
  describe "#export_all" do
    context "when database does not exist" do
      before do
        allow(exporter).to receive(:database_exists?).and_return(false)
      end
      
      it "creates empty export files" do
        result = exporter.export_all
        
        expect(result).to be true
        expect(File.exist?(File.join(test_export_dir, "schema.sql"))).to be true
        expect(File.exist?(File.join(test_export_dir, "help_docs.json"))).to be true
        expect(File.exist?(File.join(test_export_dir, "help_items.json"))).to be true
        expect(File.exist?(File.join(test_export_dir, "metadata.json"))).to be true
        expect(File.exist?(File.join(test_export_dir, "export_id.txt"))).to be true
        
        # Check empty arrays
        docs = JSON.parse(File.read(File.join(test_export_dir, "help_docs.json")))
        items = JSON.parse(File.read(File.join(test_export_dir, "help_items.json")))
        expect(docs).to eq([])
        expect(items).to eq([])
      end
    end
    
    context "when container is not running" do
      before do
        allow(exporter).to receive(:container_running?).and_return(false)
      end
      
      it "returns false with error message" do
        expect { exporter.export_all }.to output(/pgvector container is not running/).to_stdout
        expect(exporter.export_all).to be false
      end
    end
    
    context "with successful export" do
      let(:mock_conn) { double("PG::Connection") }
      
      before do
        allow(exporter).to receive(:database_exists?).and_return(true)
        allow(PG).to receive(:connect).and_return(mock_conn)
        
        # Mock help_docs query
        docs_result = [
          {
            "id" => "1",
            "title" => "Test Doc",
            "file_path" => "/test/doc.md",
            "section" => "test",
            "language" => "en",
            "items" => "5",
            "metadata" => '{"key": "value"}',
            "embedding" => "[0.1,0.2,0.3]",
            "created_at" => "2024-01-01",
            "updated_at" => "2024-01-01"
          }
        ]
        allow(mock_conn).to receive(:exec).with(/SELECT \* FROM help_docs/).and_return(docs_result)
        
        # Mock help_items query
        items_result = [
          {
            "id" => "1",
            "doc_id" => "1",
            "text" => "Test item",
            "position" => "0",
            "heading" => "Test",
            "metadata" => '{"key": "value"}',
            "embedding" => "[0.4,0.5,0.6]",
            "created_at" => "2024-01-01"
          }
        ]
        allow(mock_conn).to receive(:exec).with(/SELECT \* FROM help_items/).and_return(items_result)
        
        # Mock count queries
        allow(mock_conn).to receive(:exec).with(/SELECT COUNT/).and_return([{"count" => "1"}])
        allow(mock_conn).to receive(:close)
      end
      
      it "exports all data successfully" do
        result = exporter.export_all
        
        expect(result).to be true
        
        # Verify schema file
        schema = File.read(File.join(test_export_dir, "schema.sql"))
        expect(schema).to include("CREATE TABLE IF NOT EXISTS help_docs")
        expect(schema).to include("CREATE TABLE IF NOT EXISTS help_items")
        expect(schema).to include("CREATE EXTENSION IF NOT EXISTS vector")
        
        # Verify docs export
        docs = JSON.parse(File.read(File.join(test_export_dir, "help_docs.json")))
        expect(docs.length).to eq(1)
        expect(docs[0]["title"]).to eq("Test Doc")
        expect(docs[0]["embedding"]).to eq([0.1, 0.2, 0.3])
        
        # Verify items export
        items = JSON.parse(File.read(File.join(test_export_dir, "help_items.json")))
        expect(items.length).to eq(1)
        expect(items[0]["text"]).to eq("Test item")
        expect(items[0]["embedding"]).to eq([0.4, 0.5, 0.6])
        
        # Verify metadata
        metadata = JSON.parse(File.read(File.join(test_export_dir, "metadata.json")))
        expect(metadata["docs_count"]).to eq(1)
        expect(metadata["items_count"]).to eq(1)
        expect(metadata["export_id"]).to match(/[a-f0-9]{32}/)
      end
    end
  end
  
  describe "#container_running?" do
    it "checks if Docker container is running" do
      # Test when container is running
      exporter_running = described_class.new
      allow(exporter_running).to receive(:system).and_return(true)
      expect(exporter_running.send(:container_running?)).to be true
      
      # Test when container is not running
      exporter_not_running = described_class.new
      allow(exporter_not_running).to receive(:system).and_return(false)
      expect(exporter_not_running.send(:container_running?)).to be false
    end
  end
  
  describe "#create_empty_export" do
    it "creates all required empty export files" do
      exporter.send(:create_empty_export)
      
      # Check all files exist
      %w[schema.sql help_docs.json help_items.json metadata.json export_id.txt].each do |filename|
        expect(File.exist?(File.join(test_export_dir, filename))).to be true
      end
      
      # Verify metadata structure
      metadata = JSON.parse(File.read(File.join(test_export_dir, "metadata.json")))
      expect(metadata["docs_count"]).to eq(0)
      expect(metadata["items_count"]).to eq(0)
    end
  end
end