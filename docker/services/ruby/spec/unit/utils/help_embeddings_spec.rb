# frozen_string_literal: true

require 'spec_helper'
require 'monadic/utils/help_embeddings'

# Behavioural tests against a fully fake VectorStore + Embeddings client. The
# point is to lock in the public API contract that monadic_help_tools.rb (and
# the MCP adapter) rely on, not to test Qdrant itself.
RSpec.describe HelpEmbeddings do
  let(:store) { instance_double(Monadic::VectorStore::Base) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }
  let(:db) { described_class.new(vector_store: store, embeddings: embeddings) }

  before do
    allow(embeddings).to receive(:embed_query).and_return([0.1, 0.2, 0.3])
  end

  def hit(id:, score:, payload:)
    { 'id' => id, 'score' => score, 'payload' => payload }
  end

  describe '#find_closest_text' do
    it 'searches help_items with a query embedding and joins doc-level title' do
      expect(store).to receive(:search).with(
        hash_including(
          collection: 'help_items',
          vector: [0.1, 0.2, 0.3],
          vector_name: 'content',
          limit: 5
        )
      ).and_return([
        hit(id: 11, score: 0.91,
            payload: { 'doc_id' => 1, 'text' => 'snippet', 'position' => 0,
                       'heading' => 'h', 'language' => 'en' })
      ])
      expect(store).to receive(:retrieve_points).with(
        collection: 'help_docs', ids: [1]
      ).and_return([{ 'id' => 1, 'payload' => { 'title' => 'T', 'file_path' => 'a.md', 'section' => 's' } }])

      results = db.find_closest_text('what is monad?', top_n: 5)
      expect(results.size).to eq(1)
      expect(results.first).to include(
        text: 'snippet', doc_id: 1, title: 'T', file_path: 'a.md', similarity: 0.91
      )
    end

    it 'filters out internal docs by default and includes them when asked' do
      expect(store).to receive(:search).with(
        hash_including(filter: { must: [{ key: 'is_internal', match: { value: false } }] })
      ).and_return([])

      db.find_closest_text('q')

      expect(store).to receive(:search).with(hash_including(filter: nil)).and_return([])

      db.find_closest_text('q', include_internal: true)
    end
  end

  describe '#find_closest_text_multi' do
    it 'caps chunks per doc and limits to top_n unique docs' do
      raw_hits = (1..6).map do |i|
        hit(id: i, score: 0.9 - (i * 0.05),
            payload: { 'doc_id' => (i <= 3 ? 1 : 2), 'text' => "t#{i}", 'position' => i })
      end
      allow(store).to receive(:search).and_return(raw_hits)
      allow(store).to receive(:retrieve_points).and_return([{ 'id' => 1, 'payload' => {} }])

      results = db.find_closest_text_multi('q', chunks_per_result: 2, top_n: 2)
      doc_ids = results.map { |r| r[:doc_id] }
      expect(doc_ids.tally).to eq(1 => 2, 2 => 2)
    end
  end

  describe '#find_closest_doc' do
    it 'searches help_docs and forwards a language filter when given' do
      expect(store).to receive(:search).with(
        hash_including(
          collection: 'help_docs',
          filter: { must: [{ key: 'language', match: { value: 'ja' } }] }
        )
      ).and_return([
        hit(id: 7, score: 0.8,
            payload: { 'title' => 'T', 'file_path' => 'a.md', 'language' => 'ja',
                       'items' => 3, 'metadata' => { 'category' => 'guide' } })
      ])

      results = db.find_closest_doc('q', top_n: 1, language: 'ja')
      expect(results.first).to include(doc_id: 7, language: 'ja', items: 3)
    end
  end

  describe '#list_titles' do
    it 'paginates via scroll until next is nil' do
      expect(store).to receive(:scroll).and_return(
        { points: [{ 'id' => 1, 'payload' => { 'title' => 'A' } }], next: 'cursor1' },
        { points: [{ 'id' => 2, 'payload' => { 'title' => 'B' } }], next: nil }
      )
      titles = db.list_titles
      expect(titles.map { |t| t[:title] }).to eq(%w[A B])
    end
  end

  describe '#get_text_snippets' do
    it 'returns items sorted by position' do
      allow(store).to receive(:scroll).and_return(
        { points: [
          { 'id' => 1, 'payload' => { 'text' => 'b', 'position' => 1 } },
          { 'id' => 2, 'payload' => { 'text' => 'a', 'position' => 0 } }
        ], next: nil }
      )
      snippets = db.get_text_snippets(99)
      expect(snippets.map { |s| s[:text] }).to eq(%w[a b])
    end
  end

  describe '#search (MCP alias)' do
    it 'returns title/content/distance shape' do
      allow(store).to receive(:search).and_return([
        hit(id: 1, score: 0.85, payload: { 'doc_id' => 1, 'text' => 'snippet' })
      ])
      allow(store).to receive(:retrieve_points).and_return([{ 'id' => 1, 'payload' => { 'title' => 'T' } }])

      results = db.search(query: 'q', num_results: 1)
      expect(results.first).to include(title: 'T', content: 'snippet')
      expect(results.first[:distance]).to be_within(0.001).of(0.15)
    end
  end

  describe '#get_stats' do
    it 'counts documents by language and reports averages' do
      allow(store).to receive(:scroll).and_return(
        { points: [
          { 'id' => 1, 'payload' => { 'language' => 'en', 'items' => 4 } },
          { 'id' => 2, 'payload' => { 'language' => 'en', 'items' => 8 } },
          { 'id' => 3, 'payload' => { 'language' => 'ja', 'items' => 6 } }
        ], next: nil }
      )
      allow(store).to receive(:count).and_return(18)

      stats = db.get_stats
      expect(stats[:documents_by_language]).to eq('en' => 2, 'ja' => 1)
      expect(stats[:total_items]).to eq(18)
      expect(stats[:avg_items_per_doc]).to eq(6.0)
    end
  end

  describe '#upsert_doc and #upsert_item' do
    it 'wraps the embedding under the named "content" vector' do
      expect(store).to receive(:upsert_points).with(
        hash_including(
          collection: 'help_docs',
          points: [{
            id: 5,
            vector: { 'content' => [0.1, 0.2] },
            payload: hash_including('title' => 'T', 'language' => 'en')
          }]
        )
      )
      db.upsert_doc(id: 5, embedding: [0.1, 0.2], title: 'T', language: 'en')
    end

    it 'stores doc_id on items so they can be filtered later' do
      expect(store).to receive(:upsert_points).with(
        hash_including(
          collection: 'help_items',
          points: [{
            id: 11,
            vector: { 'content' => [0.5] },
            payload: hash_including('doc_id' => 5, 'text' => 'hello', 'position' => 0)
          }]
        )
      )
      db.upsert_item(id: 11, embedding: [0.5], doc_id: 5, text: 'hello', position: 0)
    end
  end

  describe '#bootstrap_collections!' do
    it 'creates only the missing collections' do
      allow(store).to receive(:collection_exists?).with(name: 'help_docs').and_return(true)
      allow(store).to receive(:collection_exists?).with(name: 'help_items').and_return(false)

      expect(store).to receive(:create_collection).with(hash_including(name: 'help_items'))
      expect(store).not_to receive(:create_collection).with(hash_including(name: 'help_docs'))

      db.bootstrap_collections!
    end
  end

  describe '#data_loaded?' do
    it 'returns true when help_docs has at least one point' do
      allow(store).to receive(:collection_exists?).and_return(true)
      allow(store).to receive(:count).with(collection: 'help_docs').and_return(42)
      expect(db.data_loaded?).to be true
    end

    it 'returns false on an empty database' do
      allow(store).to receive(:collection_exists?).and_return(true)
      allow(store).to receive(:count).with(collection: 'help_docs').and_return(0)
      expect(db.data_loaded?).to be false
    end
  end
end
