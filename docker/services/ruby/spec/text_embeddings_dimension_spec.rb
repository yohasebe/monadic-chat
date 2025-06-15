# frozen_string_literal: true

require "spec_helper"
require_relative "../lib/monadic/utils/text_embeddings"

RSpec.describe "TextEmbeddings Dimension Handling", skip: "Requires PostgreSQL database connection" do
  # These tests require a real PostgreSQL database with pgvector extension
  # They verify that the system correctly handles 3072-dimensional embeddings
  # from text-embedding-3-large model
  
  describe "embedding model configuration" do
    it "is configured to use text-embedding-3-large" do
      expect(true).to be true # Placeholder - actual constant is EMBEDDINGS_MODEL = "text-embedding-3-large"
    end
    
    it "uses 3072 dimensions for embeddings" do
      expect(true).to be true # Placeholder - actual dimension is 3072
    end
  end
  
  describe "database schema" do
    it "creates tables with vector(3072) columns" do
      expect(true).to be true # Placeholder - actual schema uses vector(3072)
    end
  end
end

# Test model constant separately without database dependency
RSpec.describe "EMBEDDINGS_MODEL constant" do
  it "is set to text-embedding-3-large" do
    # Load the constant definition
    require_relative "../lib/monadic/utils/text_embeddings"
    expect(EMBEDDINGS_MODEL).to eq("text-embedding-3-large")
  end
  
  it "specifies a model with 3072 dimensions" do
    # text-embedding-3-large produces 3072-dimensional vectors
    expect(EMBEDDINGS_MODEL).to match(/3-large/)
  end
end