# frozen_string_literal: true

require "dotenv/load"
require "pg"
require_relative "../spec_helper"
require_relative "../../lib/monadic/utils/text_embeddings"

# Load CONFIG from env file if available
if File.exist?(File.expand_path("~/monadic/config/env"))
  Dotenv.load(File.expand_path("~/monadic/config/env"))
  Object.send(:remove_const, :CONFIG) if defined?(CONFIG)
  CONFIG = ENV.to_h
end

RSpec.describe "TextEmbeddings with real database", type: :integration do
  before(:all) do
    skip "OPENAI_API_KEY is required for embedding tests" unless (defined?(CONFIG) && CONFIG["OPENAI_API_KEY"]) || ENV["OPENAI_API_KEY"]
    skip "PostgreSQL is not available" unless can_connect_to_postgres?
    
    # Set API_KEY constant if not already set
    unless defined?(API_KEY)
      api_key = (defined?(CONFIG) && CONFIG["OPENAI_API_KEY"]) || ENV["OPENAI_API_KEY"]
      Object.const_set(:API_KEY, api_key) if api_key
    end
    
    # Create a test database for embeddings
    @test_db_name = "test_embeddings_#{Time.now.to_i}_#{rand(1000)}"
    @text_db = TextEmbeddings.new(@test_db_name, recreate_db: true)
  end

  after(:all) do
    if @text_db
      @text_db.close_connection
      
      # Drop the test database
      begin
        conn = PG.connect(postgres_connection_params)
        conn.exec("DROP DATABASE IF EXISTS #{@test_db_name}")
        conn.close
      rescue => e
        puts "Warning: Could not drop test database: #{e.message}"
      end
    end
  end

  describe "#get_embeddings" do
    context "with real OpenAI API" do
      it "returns a valid embedding vector" do
        text = "This is a test sentence for embeddings."
        
        embedding = @text_db.get_embeddings(text)
        
        expect(embedding).to be_a(Array)
        expect(embedding.size).to eq(3072)  # text-embedding-3-large dimension
        expect(embedding.all? { |val| val.is_a?(Numeric) }).to be true
      end

      it "returns different embeddings for different texts" do
        text1 = "The quick brown fox jumps over the lazy dog."
        text2 = "Machine learning models process vast amounts of data."
        
        embedding1 = @text_db.get_embeddings(text1)
        embedding2 = @text_db.get_embeddings(text2)
        
        expect(embedding1).not_to eq(embedding2)
        
        # Calculate cosine similarity to ensure they're different but still valid
        similarity = cosine_similarity(embedding1, embedding2)
        expect(similarity).to be_between(0, 1)
        expect(similarity).to be < 0.95  # They should be different enough
      end
    end

    context "with invalid input" do
      it "raises an error for empty text" do
        expect { @text_db.get_embeddings("") }.to raise_error(ArgumentError)
      end

      it "raises an error for nil text" do
        expect { @text_db.get_embeddings(nil) }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#store_embeddings and #find_closest_text" do
    context "with real database operations" do
      before do
        @doc_title = "Test Document #{Time.now.to_i}"
        @doc_data = { title: @doc_title, metadata: { category: "test" } }

        @text1 = "The weather is sunny and warm today."
        @metadata1 = {
          "author" => "John Doe",
          "date" => "2024-01-01",
          "tokens" => 7
        }
        @item_data1 = { text: @text1, metadata: @metadata1 }

        @text2 = "It's raining heavily with thunderstorms."
        @metadata2 = { 
          "author" => "Jane Smith", 
          "date" => "2024-01-02", 
          "tokens" => 6 
        }
        @item_data2 = { text: @text2, metadata: @metadata2 }

        @text3 = "The sky is clear and the sun is shining brightly."
        @metadata3 = { 
          "author" => "Bob Wilson", 
          "date" => "2024-01-03", 
          "tokens" => 10 
        }
        @item_data3 = { text: @text3, metadata: @metadata3 }

        @items_data = [@item_data1, @item_data2, @item_data3]
      end

      it "stores embeddings in the database" do
        result = @text_db.store_embeddings(@doc_data, @items_data)
        
        expect(result).to be_a(Hash)
        expect(result[:doc_id]).to be_a(Integer)
        expect(result[:doc_id]).to be > 0
        
        # Verify the data was actually stored
        conn = @text_db.instance_variable_get(:@conn)
        doc_result = conn.exec_params(
          "SELECT COUNT(*) FROM docs WHERE id = $1",
          [result[:doc_id]]
        )
        expect(doc_result[0]['count'].to_i).to eq(1)
        
        items_result = conn.exec_params(
          "SELECT COUNT(*) FROM items WHERE doc_id = $1",
          [result[:doc_id]]
        )
        expect(items_result[0]['count'].to_i).to eq(3)
      end

      it "finds the closest matching text" do
        # Store the embeddings first
        res = @text_db.store_embeddings(@doc_data, @items_data)
        doc_id = res[:doc_id]

        # Search for similar text
        query_text = "The weather is beautiful and sunny."
        results = @text_db.find_closest_text(query_text, top_n: 2)
        
        expect(results).to be_a(Array)
        expect(results.size).to eq(2)
        
        # The first result should be the most similar
        first_result = results[0]
        expect(first_result[:doc_id]).to be_a(Integer)
        expect(first_result[:doc_title]).to be_a(String)
        # Should match with text1 or text3 (both about sunny weather)
        expect([1, 3]).to include(first_result[:position])
      end

      it "respects the top_n parameter" do
        res = @text_db.store_embeddings(@doc_data, @items_data)
        
        query_text = "Weather conditions"
        
        results1 = @text_db.find_closest_text(query_text, top_n: 1)
        expect(results1.size).to eq(1)
        
        results3 = @text_db.find_closest_text(query_text, top_n: 3)
        expect(results3.size).to eq(3)
      end

      it "returns results for unrelated queries" do
        res = @text_db.store_embeddings(@doc_data, @items_data)
        
        # Search for something completely unrelated
        query_text = "Quantum physics and nuclear fusion research"
        results = @text_db.find_closest_text(query_text, top_n: 1)
        
        # Should still return results even if not very similar
        expect(results).to be_a(Array)
        expect(results.size).to eq(1)
      end
    end

    context "with invalid queries" do
      it "returns false for empty query text" do
        # No need to store embeddings for this test
        result = @text_db.find_closest_text("")
        expect(result).to be_falsey
      end
    end
  end

  describe "#delete_by_title" do
    it "removes a document and its items from the database" do
      # Set up test data first
      doc_title = "Delete Test Doc #{Time.now.to_i}"
      doc_data = { title: doc_title, metadata: {} }
      items_data = [{ text: "Test content", metadata: {} }]
      
      res = @text_db.store_embeddings(doc_data, items_data)
      doc_id = res[:doc_id]
      
      # Verify document exists
      conn = @text_db.instance_variable_get(:@conn)
      before_count = conn.exec_params(
        "SELECT COUNT(*) FROM docs WHERE id = $1",
        [doc_id]
      )[0]['count'].to_i
      expect(before_count).to eq(1)
      
      # Delete the document by title
      result = @text_db.delete_by_title(doc_title)
      expect(result).to be true
      
      # Verify document is deleted
      after_count = conn.exec_params(
        "SELECT COUNT(*) FROM docs WHERE id = $1",
        [doc_id]
      )[0]['count'].to_i
      expect(after_count).to eq(0)
      
      # Verify items are also deleted
      items_count = conn.exec_params(
        "SELECT COUNT(*) FROM items WHERE doc_id = $1",
        [doc_id]
      )[0]['count'].to_i
      expect(items_count).to eq(0)
    end
  end

  describe "#list_titles" do
    it "returns all stored documents" do
      # Store multiple documents
      doc1 = @text_db.store_embeddings(
        { title: "Doc 1 #{Time.now.to_i}", metadata: {} },
        [{ text: "Text 1", metadata: {} }]
      )
      
      doc2 = @text_db.store_embeddings(
        { title: "Doc 2 #{Time.now.to_i}", metadata: {} },
        [{ text: "Text 2", metadata: {} }]
      )
      
      documents = @text_db.list_titles
      
      expect(documents).to be_a(Array)
      expect(documents.size).to be >= 2
      
      doc_ids = documents.map { |d| d[:id] }
      expect(doc_ids).to include(doc1[:doc_id])
      expect(doc_ids).to include(doc2[:doc_id])
    end
  end

  private

  def can_connect_to_postgres?
    conn = PG.connect(postgres_connection_params)
    conn.close
    true
  rescue => e
    puts "PostgreSQL connection failed: #{e.message}"
    false
  end

  def cosine_similarity(vec1, vec2)
    # Calculate cosine similarity between two vectors
    dot_product = vec1.zip(vec2).map { |a, b| a * b }.sum
    magnitude1 = Math.sqrt(vec1.map { |a| a * a }.sum)
    magnitude2 = Math.sqrt(vec2.map { |a| a * a }.sum)
    
    dot_product / (magnitude1 * magnitude2)
  end
end