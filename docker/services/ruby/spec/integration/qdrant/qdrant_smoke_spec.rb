# frozen_string_literal: true

require 'spec_helper'
require 'monadic/vector_store'
require_relative '../../support/vector_service_helper'

# End-to-end smoke test against a real Qdrant container.
# Skips automatically when the qdrant_service is not reachable on
# http://localhost:6333.
RSpec.describe 'Qdrant integration smoke', :integration do
  before(:all) do
    VectorServiceHelper.skip_unless_both! unless VectorServiceHelper.qdrant_available?

    @backend = Monadic::VectorStore::QdrantBackend.new(endpoint: VectorServiceHelper::QDRANT_URL)
    @collection = "smoke_test_#{Process.pid}_#{Time.now.to_i}"
  end

  before do
    skip 'qdrant not running' unless VectorServiceHelper.qdrant_available?
  end

  after(:all) do
    @backend&.delete_collection(name: @collection) if @collection
  rescue StandardError
    # collection may not exist; ignore
  end

  it 'creates a collection, upserts points, searches, and counts' do
    # 1. Create collection with two named vectors
    @backend.create_collection(
      name: @collection,
      vectors: { 'content' => { size: 4, distance: 'Cosine' } }
    )

    # 2. Upsert a few points
    @backend.upsert_points(
      collection: @collection,
      points: [
        { id: 1, vector: { 'content' => [1.0, 0.0, 0.0, 0.0] }, payload: { 'label' => 'a' } },
        { id: 2, vector: { 'content' => [0.0, 1.0, 0.0, 0.0] }, payload: { 'label' => 'b' } },
        { id: 3, vector: { 'content' => [0.0, 0.0, 1.0, 0.0] }, payload: { 'label' => 'c' } }
      ]
    )

    # 3. Count
    expect(@backend.count(collection: @collection)).to eq(3)

    # 4. Search: query vector aligned with point 2 should return point 2 first
    hits = @backend.search(
      collection: @collection,
      vector: [0.0, 1.0, 0.0, 0.0],
      vector_name: 'content',
      limit: 3
    )
    expect(hits.first['id']).to eq(2)
    expect(hits.first.dig('payload', 'label')).to eq('b')

    # 5. Filter by payload
    filtered = @backend.search(
      collection: @collection,
      vector: [1.0, 0.0, 0.0, 0.0],
      vector_name: 'content',
      filter: { must: [{ key: 'label', match: { value: 'c' } }] },
      limit: 5
    )
    expect(filtered.first['id']).to eq(3)

    # 6. Scroll through all points
    page = @backend.scroll(collection: @collection, limit: 10)
    expect(page[:points].size).to eq(3)

    # 7. Health check
    expect(@backend.health).to be true
  end
end
