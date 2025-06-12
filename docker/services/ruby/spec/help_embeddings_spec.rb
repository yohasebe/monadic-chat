# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/monadic/utils/help_embeddings"

RSpec.describe HelpEmbeddings do
  let(:help_embeddings) { HelpEmbeddings.new(recreate_db: true) }

  after(:each) do
    help_embeddings.close_connection if help_embeddings
  end

  describe "database schema" do
    it "creates help_docs table with 3072-dimensional vector column" do
      result = help_embeddings.conn.exec(<<~SQL)
        SELECT column_name, data_type, udt_name
        FROM information_schema.columns
        WHERE table_name = 'help_docs' AND column_name = 'embedding'
      SQL
      
      expect(result.first["udt_name"]).to eq("vector")
      
      # Check dimension by attempting to insert a vector
      # This will fail if dimensions don't match
      expect {
        help_embeddings.conn.exec_params(
          "INSERT INTO help_docs (title, file_path, section, language, items, metadata, embedding) VALUES ($1, $2, $3, $4, $5, $6, $7)",
          ["Test", "/test", "test", "en", 1, "{}", "[" + Array.new(3072, 0).join(",") + "]"]
        )
      }.not_to raise_error
    end

    it "creates help_items table with 3072-dimensional vector column" do
      result = help_embeddings.conn.exec(<<~SQL)
        SELECT column_name, data_type, udt_name
        FROM information_schema.columns
        WHERE table_name = 'help_items' AND column_name = 'embedding'
      SQL
      
      expect(result.first["udt_name"]).to eq("vector")
    end

    it "does not create ivfflat indexes due to dimension limit" do
      result = help_embeddings.conn.exec(<<~SQL)
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE tablename IN ('help_docs', 'help_items')
        AND indexdef LIKE '%ivfflat%'
      SQL
      
      expect(result.count).to eq(0)
    end

    it "creates standard indexes for non-vector columns" do
      result = help_embeddings.conn.exec(<<~SQL)
        SELECT indexname
        FROM pg_indexes
        WHERE tablename IN ('help_docs', 'help_items')
        AND indexname IN ('idx_help_docs_language', 'idx_help_docs_file_path', 'idx_help_items_doc_id')
      SQL
      
      expect(result.count).to eq(3)
    end
  end

  describe "embedding model configuration" do
    it "uses text-embedding-3-large model" do
      expect(EMBEDDINGS_MODEL).to eq("text-embedding-3-large")
    end
  end

  describe "embedding generation" do
    it "generates 3072-dimensional embeddings" do
      # Mock the OpenAI API response
      mock_response = double('response')
      allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(mock_response).to receive(:body).and_return(
        { data: [{ embedding: Array.new(3072) { rand } }] }.to_json
      )
      allow(Net::HTTP).to receive(:start).and_return(mock_response)

      # HelpEmbeddings#get_embeddings expects an array of texts
      embeddings = help_embeddings.get_embeddings(["test text"])
      expect(embeddings).to be_a(Array)
      expect(embeddings.first).to be_a(Array)
      expect(embeddings.first.size).to eq(3072)
    end
  end

  describe "search functionality" do
    before do
      # Mock embeddings for testing - HelpEmbeddings#get_embeddings expects array input and returns array of embeddings
      allow(help_embeddings).to receive(:get_embeddings) do |texts|
        texts.map { Array.new(3072) { rand } }
      end
      
      # Also mock the parent class method that's used internally
      allow(help_embeddings).to receive(:get_embedding) do |text|
        Array.new(3072) { rand }
      end
    end

    it "performs similarity search without vector indexes" do
      # Insert test document
      doc_id = help_embeddings.insert_doc(
        title: "Test Document",
        file_path: "/test/doc.md",
        section: "test",
        language: "en",
        items: 1,
        metadata: {}
      )

      # Insert test item
      help_embeddings.insert_item(
        doc_id: doc_id,
        text: "This is test content",
        position: 0,
        heading: "Test Heading",
        metadata: {}
      )

      # Search should work without indexes
      results = help_embeddings.find_closest_text("test query", top_n: 1)
      expect(results).not_to be_empty
      expect(results.first[:text]).to eq("This is test content")
    end

    it "handles empty embeddings gracefully" do
      result = help_embeddings.combine_embeddings([])
      expect(result).to be_a(Vector)
      expect(result.size).to eq(3072)
      expect(result.to_a).to all(eq(0))
    end
  end

  describe "error handling" do
    it "handles database errors gracefully" do
      # Force a connection error
      allow(help_embeddings.conn).to receive(:exec).and_raise(PG::Error.new("Connection lost"))
      
      expect {
        help_embeddings.list_titles
      }.to raise_error(TextEmbeddings::DatabaseError)
    end

    it "validates embedding dimensions on insert" do
      # Try to insert wrong dimension embedding
      wrong_embedding = Array.new(1536, 0)  # Wrong size
      
      expect {
        help_embeddings.conn.exec_params(
          "INSERT INTO help_docs (title, file_path, section, language, items, metadata, embedding) VALUES ($1, $2, $3, $4, $5, $6, $7)",
          ["Test", "/test", "test", "en", 1, "{}", "[" + wrong_embedding.join(",") + "]"]
        )
      }.to raise_error(PG::Error, /expected 3072 dimensions/)
    end
  end
end