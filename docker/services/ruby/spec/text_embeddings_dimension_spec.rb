# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/monadic/utils/text_embeddings"

RSpec.describe "TextEmbeddings Dimension Handling" do
  let(:db_name) { "test_dimension_db" }
  let(:text_db) { TextEmbeddings.new(db_name, recreate_db: true) }

  after(:each) do
    text_db.close_connection if text_db
  end

  describe "embedding model configuration" do
    it "is configured to use text-embedding-3-large" do
      expect(EMBEDDINGS_MODEL).to eq("text-embedding-3-large")
    end

    it "cannot be changed via environment variable" do
      # The constant should not be affected by ENV changes
      original_env = ENV["EMBEDDING_MODEL"]
      ENV["EMBEDDING_MODEL"] = "text-embedding-3-small"
      
      # Constant should still be text-embedding-3-large
      expect(EMBEDDINGS_MODEL).to eq("text-embedding-3-large")
      
      # Restore original
      ENV["EMBEDDING_MODEL"] = original_env
    end
  end

  describe "database schema validation" do
    it "creates docs table with 3072-dimensional vectors" do
      # Try to insert a 3072-dimensional vector
      expect {
        embedding = Array.new(3072, 0.1)
        text_db.conn.exec_params(
          "INSERT INTO docs (title, items, metadata, embedding) VALUES ($1, $2, $3, $4)",
          ["Test Doc", 1, "{}", "[#{embedding.join(',')}]"]
        )
      }.not_to raise_error
    end

    it "creates items table with 3072-dimensional vectors" do
      # Insert a doc first
      doc_result = text_db.conn.exec_params(
        "INSERT INTO docs (title, items, metadata) VALUES ($1, $2, $3) RETURNING id",
        ["Test Doc", 1, "{}"]
      )
      doc_id = doc_result.first["id"]

      # Try to insert a 3072-dimensional vector
      expect {
        embedding = Array.new(3072, 0.1)
        text_db.conn.exec_params(
          "INSERT INTO items (doc_id, text, position, metadata, embedding) VALUES ($1, $2, $3, $4, $5)",
          [doc_id, "Test text", 0, "{}", "[#{embedding.join(',')}]"]
        )
      }.not_to raise_error
    end

    it "rejects vectors with wrong dimensions" do
      # Try 1536 dimensions (old size)
      expect {
        embedding = Array.new(1536, 0.1)
        text_db.conn.exec_params(
          "INSERT INTO docs (title, items, metadata, embedding) VALUES ($1, $2, $3, $4)",
          ["Test Doc", 1, "{}", "[#{embedding.join(',')}]"]
        )
      }.to raise_error(PG::Error, /expected 3072 dimensions/)
    end
  end

  describe "combine_embeddings method" do
    it "returns 3072-dimensional zero vector for empty input" do
      result = text_db.combine_embeddings([])
      expect(result).to be_a(Vector)
      expect(result.size).to eq(3072)
      expect(result.to_a).to all(eq(0))
    end

    it "correctly combines multiple 3072-dimensional embeddings" do
      # Create test embeddings
      embedding1 = Vector[*Array.new(3072) { 0.1 }]
      embedding2 = Vector[*Array.new(3072) { 0.2 }]
      
      result = text_db.combine_embeddings([embedding1, embedding2])
      expect(result.size).to eq(3072)
      
      # Average should be 0.15
      expected_value = 0.15
      result.to_a.each do |val|
        expect(val).to be_within(0.001).of(expected_value)
      end
    end
  end

  describe "API integration" do
    it "requests embeddings with correct model parameter" do
      # Mock HTTP request to verify model parameter
      expect(Net::HTTP).to receive(:start) do |host, port, &block|
        http = double("http")
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        
        # Verify the request body contains correct model
        expect(Net::HTTP::Post).to receive(:new).with("/v1/embeddings") do |path|
          post = double("post")
          expect(post).to receive(:body=) do |body|
            parsed = JSON.parse(body)
            expect(parsed["model"]).to eq("text-embedding-3-large")
          end
          allow(post).to receive(:[]=)
          post
        end
        
        # Mock response
        response = double("response")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(response).to receive(:body).and_return(
          { data: [{ embedding: Array.new(3072, 0.1) }] }.to_json
        )
        
        allow(http).to receive(:request).and_return(response)
        block.call(http)
      end

      text_db.get_embeddings("test text")
    end
  end

  describe "backward compatibility" do
    it "handles requests for old embeddings gracefully" do
      # If someone tries to work with old 1536-dim embeddings
      # The system should reject them at database level
      old_embedding = Array.new(1536, 0.1)
      
      expect {
        text_db.conn.exec_params(
          "INSERT INTO docs (title, items, metadata, embedding) VALUES ($1, $2, $3, $4)",
          ["Old Doc", 1, "{}", "[#{old_embedding.join(',')}]"]
        )
      }.to raise_error(PG::Error)
    end
  end

  describe "performance considerations" do
    it "handles large 3072-dimensional vectors efficiently" do
      # Create a large embedding
      large_embedding = Array.new(3072) { rand }
      
      # Should complete within reasonable time
      start_time = Time.now
      
      # Insert
      text_db.conn.exec_params(
        "INSERT INTO docs (title, items, metadata, embedding) VALUES ($1, $2, $3, $4)",
        ["Large Doc", 1, "{}", "[#{large_embedding.join(',')}]"]
      )
      
      # Query (without index)
      result = text_db.conn.exec(
        "SELECT embedding FROM docs WHERE title = 'Large Doc'"
      )
      
      end_time = Time.now
      expect(end_time - start_time).to be < 1.0  # Should complete in under 1 second
    end
  end
end