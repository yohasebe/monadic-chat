# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

# Mock TextEmbeddings parent class first
require_relative '../../../../lib/monadic/utils/environment'

class TextEmbeddings
  def self.connect_to_db(db_name, recreate_db: false)
    # Mock connection
  end
end

# Define a mock HelpEmbeddings class before loading
class HelpEmbeddings < TextEmbeddings
  def initialize(recreate_db: false); end
  def document_needs_update?(path, hash, lang); true; end
  def store_document(title, path, section, lang, chunks, metadata); true; end
  def insert_doc(doc_data); { doc_id: 1 }; end
  def insert_items(items); true; end
  def get_embeddings(texts)
    if texts.is_a?(Array)
      texts.map { Array.new(3072, 0.0) }
    else
      Array.new(3072, 0.0)
    end
  end
  def get_stats
    {
      documents_by_language: { "en" => 10 },
      total_items: 50,
      avg_items_per_doc: 5.0
    }
  end
end

# Suppress constant redefinition warnings
original_verbose = $VERBOSE
$VERBOSE = nil

# Load the script to test
script_path = File.expand_path("../../../../scripts/utilities/process_documentation.rb", __dir__)
load script_path

$VERBOSE = original_verbose

RSpec.describe ProcessDocumentation do
  let(:processor) { ProcessDocumentation.new }
  let(:test_docs_dir) { Dir.mktmpdir }
  let(:mock_help_db) { instance_double(HelpEmbeddings) }
  
  before do
    # Stub the DOCS_PATH constant
    stub_const("ProcessDocumentation::DOCS_PATH", test_docs_dir)
    
    # Mock HelpEmbeddings
    allow(HelpEmbeddings).to receive(:new).and_return(mock_help_db)
    allow(mock_help_db).to receive(:document_needs_update?).and_return(true)
    allow(mock_help_db).to receive(:store_document).and_return(true)
    allow(mock_help_db).to receive(:insert_doc).and_return(1)
    allow(mock_help_db).to receive(:insert_items).and_return(true)
    allow(mock_help_db).to receive(:insert_item).and_return(true)
    allow(mock_help_db).to receive(:get_embeddings) do |texts|
      # Return array of embeddings, one for each text
      if texts.is_a?(Array)
        texts.map { Array.new(3072, 0.0) }
      else
        Array.new(3072, 0.0)
      end
    end
    allow(mock_help_db).to receive(:get_stats).and_return({
      documents_by_language: { "en" => 2 },
      total_items: 10,
      avg_items_per_doc: 5.0
    })
    
    # Create test directory structure
    FileUtils.mkdir_p(File.join(test_docs_dir, "basic-usage"))
    FileUtils.mkdir_p(File.join(test_docs_dir, "advanced-features"))
  end
  
  after do
    FileUtils.rm_rf(test_docs_dir) if Dir.exist?(test_docs_dir)
  end
  
  describe "#process_all_docs" do
    before do
      # Create test documentation files
      File.write(File.join(test_docs_dir, "README.md"), "# Main Documentation\n\nThis is the main docs.")
      File.write(File.join(test_docs_dir, "basic-usage", "getting-started.md"), "# Getting Started\n\nBasic usage guide.")
      File.write(File.join(test_docs_dir, "advanced-features", "api.md"), "# API Reference\n\nAPI documentation.")
      
      # Mock root docs
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/README\.md$/).and_return(false)
      allow(File).to receive(:exist?).with(/CHANGELOG\.md$/).and_return(false)
    end
    
    it "processes all documentation files" do
      expect { processor.process_all_docs }.to output(/Starting documentation processing/).to_stdout
      expect { processor.process_all_docs }.to output(/Processing Complete/).to_stdout
    end
    
    it "displays processing statistics" do
      output = capture_stdout { processor.process_all_docs }
      
      expect(output).to include("Files processed:")
      expect(output).to include("Total chunks created:")
      expect(output).to include("Documents by language:")
      expect(output).to include("Total items in database:")
    end
  end
  
  describe "chunk processing" do
    it "chunks content appropriately" do
      long_content = "# Test Document\n\n" + ("This is a test paragraph. " * 200)
      
      # Create a test file with long content
      test_file = File.join(test_docs_dir, "long-doc.md")
      File.write(test_file, long_content)
      
      # Spy on store_document to check chunking
      allow(mock_help_db).to receive(:store_document) do |title, path, section, lang, chunks, metadata|
        expect(chunks).to be_an(Array)
        expect(chunks).not_to be_empty
        chunks.each do |chunk|
          expect(chunk[:text].length).to be <= ProcessDocumentation::CHUNK_SIZE + 100 # Allow some overflow
        end
        true
      end
      
      processor.process_all_docs
    end
  end
  
  describe "metadata extraction" do
    it "extracts headings from markdown" do
      content = <<~MD
        # Main Title
        
        ## Section 1
        Some content here.
        
        ### Subsection 1.1
        More content.
        
        ## Section 2
        Final content.
      MD
      
      test_file = File.join(test_docs_dir, "structured.md")
      File.write(test_file, content)
      
      # Check metadata extraction
      allow(mock_help_db).to receive(:store_document) do |title, path, section, lang, chunks, metadata|
        expect(metadata[:headings]).to include("Main Title")
        expect(metadata[:headings]).to include("Section 1")
        expect(metadata[:headings]).to include("Subsection 1.1")
        expect(metadata[:headings]).to include("Section 2")
        true
      end
      
      processor.process_all_docs
    end
    
    it "extracts code blocks from markdown" do
      content = <<~MD
        # Code Examples
        
        Here's a Ruby example:
        
        ```ruby
        def hello
          puts "Hello, world!"
        end
        ```
        
        And a Python example:
        
        ```python
        def hello():
            print("Hello, world!")
        ```
      MD
      
      test_file = File.join(test_docs_dir, "code-examples.md")
      File.write(test_file, content)
      
      allow(mock_help_db).to receive(:store_document) do |title, path, section, lang, chunks, metadata|
        expect(metadata[:code_blocks]).to eq(2)
        true
      end
      
      processor.process_all_docs
    end
  end
  
  describe "error handling" do
    it "handles missing documentation directory gracefully" do
      stub_const("ProcessDocumentation::DOCS_PATH", "/non/existent/path")
      
      expect { processor.process_all_docs }.not_to raise_error
      expect { processor.process_all_docs }.to output(/Does path exist\? false/).to_stdout
    end
    
    it "skips unchanged documents" do
      test_file = File.join(test_docs_dir, "unchanged.md")
      File.write(test_file, "# Unchanged Document")
      
      # Mock that document doesn't need update
      allow(mock_help_db).to receive(:document_needs_update?).and_return(false)
      
      output = capture_stdout { processor.process_all_docs }
      expect(output).to include("Skipping (unchanged)")
    end
  end
  
  private
  
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end