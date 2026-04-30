# frozen_string_literal: true

require 'spec_helper'
require 'monadic/embeddings'
require_relative '../../support/vector_service_helper'

# End-to-end smoke test against a real embeddings_service container.
# Verifies that multilingual-e5-base produces 768-dim normalized vectors
# and that semantically similar inputs land near each other in vector
# space.
RSpec.describe 'Embeddings service integration smoke', :integration do
  before(:all) do
    # In production-mode `rake test:all[full]` the embeddings container runs
    # on the docker network without a host port. Recreate it with the dev
    # overlay so the spec process can reach localhost:8002.
    VectorServiceHelper.ensure_dev_overlay!

    @client = Monadic::Embeddings::Client.new(endpoint: VectorServiceHelper::EMBEDDINGS_URL)
  end

  it 'reports the expected model and dimension via /v1/info' do
    info = @client.info
    expect(info['model']).to include('multilingual-e5')
    expect(info['dimension']).to eq(768)
  end

  it 'returns L2-normalized vectors' do
    vectors = @client.embed(texts: ['hello world'], task: :passage)
    expect(vectors.size).to eq(1)
    norm = Math.sqrt(vectors.first.sum { |x| x * x })
    expect(norm).to be_within(0.05).of(1.0)  # normalize_embeddings=True
  end

  it 'returns the right number of vectors for a batched request' do
    texts = %w[apple banana cherry date elderberry]
    vectors = @client.embed(texts: texts, task: :passage)
    expect(vectors.size).to eq(texts.size)
    expect(vectors.first.size).to eq(768)
  end

  it 'puts semantically related queries closer than unrelated ones' do
    target_vec, near_vec, far_vec = @client.embed(
      texts: [
        'How do I configure the Ruby web server?',
        'Setting up the Ruby application server',
        'Cooking recipe for chocolate chip cookies'
      ],
      task: :query
    )
    near_sim = dot(target_vec, near_vec)
    far_sim = dot(target_vec, far_vec)
    expect(near_sim).to be > far_sim
  end

  it 'distinguishes query and passage prefix conventions' do
    # Same text under different tasks should produce different vectors
    # because e5 prepends "query: " vs "passage: ".
    q = @client.embed(texts: ['Monadic Chat'], task: :query).first
    p = @client.embed(texts: ['Monadic Chat'], task: :passage).first
    diff = q.zip(p).map { |a, b| (a - b).abs }.sum
    expect(diff).to be > 0  # vectors differ
  end

  def dot(a, b)
    a.zip(b).sum { |x, y| x * y }
  end
end
