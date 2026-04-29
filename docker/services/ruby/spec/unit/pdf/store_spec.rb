# frozen_string_literal: true

require 'spec_helper'
require 'monadic/pdf'

# Behavioural tests for the new PDF storage facade. The vector store and
# embeddings client are both stubbed; we only verify that Pdf::Store builds
# the right requests and decodes responses correctly.
RSpec.describe Monadic::Pdf::Store do
  let(:store) { instance_double(Monadic::VectorStore::Base) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }
  let(:pdf) do
    described_class.new(app_key: 'pdfnavigatoropenai', vector_store: store, embeddings: embeddings)
  end

  before do
    allow(store).to receive(:collection_exists?).and_return(true)
    allow(store).to receive(:create_collection)
  end

  def hit(id:, score:, payload:)
    { 'id' => id, 'score' => score, 'payload' => payload }
  end

  describe '#bootstrap_collections!' do
    it 'creates only the missing collections' do
      allow(store).to receive(:collection_exists?).with(name: 'pdf_docs').and_return(false)
      allow(store).to receive(:collection_exists?).with(name: 'pdf_items').and_return(true)

      expect(store).to receive(:create_collection).with(hash_including(name: 'pdf_docs'))
      expect(store).not_to receive(:create_collection).with(hash_including(name: 'pdf_items'))

      pdf.bootstrap_collections!
    end
  end

  describe '#any_docs?' do
    it 'returns true when the count for this app_key is positive' do
      allow(store).to receive(:count).with(
        collection: 'pdf_docs',
        filter: { must: [{ key: 'app_key', match: { value: 'pdfnavigatoropenai' } }] }
      ).and_return(3)
      expect(pdf.any_docs?).to be true
    end

    it 'returns false on zero count' do
      allow(store).to receive(:count).and_return(0)
      expect(pdf.any_docs?).to be false
    end
  end

  describe '#store_embeddings' do
    it 'embeds items, computes a doc-level mean vector, and writes both collections' do
      allow(embeddings).to receive(:embed_passages).with(['hello', 'world'])
        .and_return([[1.0, 0.0], [0.0, 1.0]])

      received = []
      allow(store).to receive(:upsert_points) do |args|
        received << args
        nil
      end

      doc_id = pdf.store_embeddings(
        { title: 'paper.pdf', metadata: { tokens: 1000 } },
        [{ text: 'hello' }, { text: 'world' }]
      )

      expect(doc_id).to be_a(String) # UUID

      docs_call = received.find { |c| c[:collection] == 'pdf_docs' }
      items_call = received.find { |c| c[:collection] == 'pdf_items' }
      expect(docs_call).not_to be_nil
      expect(items_call).not_to be_nil

      doc_point = docs_call[:points].first
      expect(doc_point[:id]).to eq(doc_id)
      expect(doc_point[:vector]['content']).to eq([0.5, 0.5])  # mean of [1,0] and [0,1]
      expect(doc_point[:payload]).to include(
        'app_key' => 'pdfnavigatoropenai',
        'title' => 'paper.pdf',
        'items' => 2
      )

      item_points = items_call[:points]
      expect(item_points.size).to eq(2)
      expect(item_points.map { |p| p[:payload]['position'] }).to eq([0, 1])
      expect(item_points.map { |p| p[:payload]['app_key'] }.uniq).to eq(['pdfnavigatoropenai'])
      expect(item_points.first[:vector]['content']).to eq([1.0, 0.0])
    end

    it 'rejects an empty items list locally without contacting the embedder' do
      expect(embeddings).not_to receive(:embed_passages)
      expect {
        pdf.store_embeddings({ title: 'x' }, [])
      }.to raise_error(ArgumentError, /at least one item/)
    end
  end

  describe '#find_closest_text' do
    it 'sends the app_key filter and embeds with the query task' do
      allow(embeddings).to receive(:embed_query).and_return([0.1, 0.2])
      expect(store).to receive(:search).with(
        hash_including(
          collection: 'pdf_items',
          vector: [0.1, 0.2],
          vector_name: 'content',
          filter: hash_including(must: [{ key: 'app_key', match: { value: 'pdfnavigatoropenai' } }]),
          limit: 5
        )
      ).and_return([
        hit(id: 'u-1', score: 0.91,
            payload: { 'doc_id' => 'd-1', 'text' => 'snippet', 'position' => 0 })
      ])

      results = pdf.find_closest_text('what is monad?', top_n: 5)
      expect(results.first).to include(text: 'snippet', similarity: 0.91, doc_id: 'd-1')
    end
  end

  describe '#list_titles' do
    it 'paginates via scroll until next is nil' do
      allow(store).to receive(:scroll).and_return(
        { points: [{ 'id' => 'd-1', 'payload' => { 'title' => 'A', 'items' => 2 } }],
          next: 'cursor1' },
        { points: [{ 'id' => 'd-2', 'payload' => { 'title' => 'B', 'items' => 5 } }],
          next: nil }
      )
      titles = pdf.list_titles
      expect(titles.map { |t| [t[:doc_id], t[:title], t[:items]] })
        .to eq([['d-1', 'A', 2], ['d-2', 'B', 5]])
    end
  end

  describe '#get_text_snippets' do
    it 'returns items sorted by position' do
      allow(store).to receive(:scroll).and_return(
        { points: [
          { 'id' => 'i2', 'payload' => { 'text' => 'b', 'position' => 1 } },
          { 'id' => 'i1', 'payload' => { 'text' => 'a', 'position' => 0 } }
        ], next: nil }
      )
      snippets = pdf.get_text_snippets('d-1')
      expect(snippets.map { |s| s['text'] }).to eq(%w[a b])
    end
  end

  describe '#delete_doc' do
    it 'removes items first then the doc, both filtered by app_key' do
      call_log = []
      allow(store).to receive(:delete_points) do |args|
        call_log << args
        nil
      end

      pdf.delete_doc('d-7')

      expect(call_log[0][:collection]).to eq('pdf_items')
      expect(call_log[0][:filter][:must]).to include({ key: 'doc_id', match: { value: 'd-7' } })
      expect(call_log[1][:collection]).to eq('pdf_docs')
      expect(call_log[1][:filter][:must]).to include({ has_id: ['d-7'] })
      # Both delete operations should carry the app_key filter.
      expect(call_log.map { |c| c[:filter][:must] }.flatten)
        .to include({ key: 'app_key', match: { value: 'pdfnavigatoropenai' } })
    end
  end

  describe '#clear_all' do
    it 'deletes both collections scoped to this app_key' do
      collections = []
      allow(store).to receive(:delete_points) do |args|
        collections << args[:collection]
        # Each delete call should include the app_key filter.
        expect(args[:filter][:must]).to include({ key: 'app_key', match: { value: 'pdfnavigatoropenai' } })
        nil
      end

      pdf.clear_all
      expect(collections).to contain_exactly('pdf_docs', 'pdf_items')
    end
  end

  describe 'app isolation' do
    it 'a Store with app_key A never sees data tagged with app_key B' do
      a = described_class.new(app_key: 'A', vector_store: store, embeddings: embeddings)
      allow(embeddings).to receive(:embed_query).and_return([0.0])

      expect(store).to receive(:search) do |args|
        expect(args[:filter]).to eq({ must: [{ key: 'app_key', match: { value: 'A' } }] })
        []
      end
      a.find_closest_text('q')
    end
  end
end
