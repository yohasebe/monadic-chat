# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

# Behavioural tests for the Library Store facade. The vector store and
# embeddings client are both stubbed; we only verify that Library::Store
# builds the right requests and enforces the scope_app / conversation_id
# payload conventions.
RSpec.describe Monadic::Library::Store do
  let(:vector_store) { instance_double(Monadic::VectorStore::Base) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }
  let(:store) { described_class.new(vector_store: vector_store, embeddings: embeddings) }

  before do
    allow(vector_store).to receive(:collection_exists?).and_return(true)
    allow(vector_store).to receive(:create_collection)
    allow(vector_store).to receive(:upsert_points)
    allow(vector_store).to receive(:delete_points)
    allow(vector_store).to receive(:search).and_return([])
    allow(vector_store).to receive(:count).and_return(0)
  end

  describe 'collection identifiers' do
    it 'tracks the Library collections' do
      expect(described_class::COLLECTIONS).to contain_exactly(
        'library_summaries',
        'library_turns',
        'library_messages'
      )
    end

    it 'shares schema constants with VectorStore::Schema' do
      expect(described_class::COLLECTIONS).to eq(Monadic::VectorStore::Schema::LIBRARY_COLLECTIONS)
    end
  end

  describe '#bootstrap_collections!' do
    it 'creates only the missing collections' do
      Monadic::VectorStore::Schema::LIBRARY_COLLECTIONS.each do |name|
        allow(vector_store).to receive(:collection_exists?).with(name: name).and_return(name == 'library_turns')
      end

      expect(vector_store).to receive(:create_collection).with(hash_including(name: 'library_summaries'))
      expect(vector_store).to receive(:create_collection).with(hash_including(name: 'library_messages'))
      expect(vector_store).not_to receive(:create_collection).with(hash_including(name: 'library_turns'))

      store.bootstrap_collections!
    end

    it 'is idempotent when all collections already exist' do
      Monadic::VectorStore::Schema::LIBRARY_COLLECTIONS.each do |name|
        allow(vector_store).to receive(:collection_exists?).with(name: name).and_return(true)
      end
      expect(vector_store).not_to receive(:create_collection)
      store.bootstrap_collections!
    end
  end

  describe '#upsert_points' do
    let(:valid_point) do
      {
        id: 'pt-1',
        vector: { 'content' => Array.new(768, 0.0) },
        payload: { 'conversation_id' => 'conv-abc', 'scope_app' => 'ChatOpenAI' }
      }
    end

    it 'forwards to the vector store for a known Library collection' do
      expect(vector_store).to receive(:upsert_points).with(
        collection: 'library_turns', points: [valid_point]
      )
      store.upsert_points(collection: 'library_turns', points: [valid_point])
    end

    it 'rejects non-Library collections' do
      expect {
        store.upsert_points(collection: 'pdf_docs', points: [valid_point])
      }.to raise_error(ArgumentError, /not a Library collection/)
    end

    it 'rejects points without conversation_id' do
      bad_point = valid_point.merge(payload: { 'scope_app' => 'ChatOpenAI' })
      expect {
        store.upsert_points(collection: 'library_turns', points: [bad_point])
      }.to raise_error(ArgumentError, /conversation_id/)
    end

    it 'rejects points without scope_app' do
      bad_point = valid_point.merge(payload: { 'conversation_id' => 'conv-abc' })
      expect {
        store.upsert_points(collection: 'library_turns', points: [bad_point])
      }.to raise_error(ArgumentError, /scope_app/)
    end

    it 'accepts symbol-keyed payload as well as string-keyed' do
      sym_point = valid_point.merge(payload: { conversation_id: 'conv-abc', scope_app: 'Global' })
      expect(vector_store).to receive(:upsert_points)
      store.upsert_points(collection: 'library_summaries', points: [sym_point])
    end
  end

  describe '#search' do
    let(:vec) { Array.new(768, 0.1) }

    it 'restricts to scope_app IN [app_name, "Global"] when app_name is given' do
      expect(vector_store).to receive(:search) do |args|
        filter = args[:filter]
        expect(filter[:must]).to include(
          { key: 'scope_app', match: { any: %w[ChatOpenAI Global] } }
        )
      end
      store.search(collection: 'library_turns', vector: vec, app_name: 'ChatOpenAI')
    end

    it 'omits the scope filter entirely when app_name is nil (KB UI behaviour)' do
      expect(vector_store).to receive(:search) do |args|
        # When no scope filter is needed and no extra filter is supplied,
        # the resulting filter is nil so Qdrant searches across everything.
        expect(args[:filter]).to be_nil
      end
      store.search(collection: 'library_turns', vector: vec, app_name: nil)
    end

    it 'composes an additional filter with the scope filter' do
      expect(vector_store).to receive(:search) do |args|
        keys = args[:filter][:must].map { |c| c[:key] }
        expect(keys).to include('scope_app', 'conversation_id')
      end
      store.search(
        collection: 'library_turns', vector: vec, app_name: 'ChatOpenAI',
        filter: store.conversation_filter('conv-abc')
      )
    end

    it 'rejects non-Library collections' do
      expect {
        store.search(collection: 'help_docs', vector: vec)
      }.to raise_error(ArgumentError, /not a Library collection/)
    end
  end

  describe '#delete_conversation' do
    it 'removes the conversation from every Library collection' do
      Monadic::VectorStore::Schema::LIBRARY_COLLECTIONS.each do |name|
        expect(vector_store).to receive(:delete_points).with(
          collection: name,
          filter: { must: [{ key: 'conversation_id', match: { value: 'conv-abc' } }] }
        )
      end
      expect(store.delete_conversation('conv-abc')).to be true
    end
  end

  describe '#conversation_count' do
    it 'counts summaries with no scope filter when app_name is nil' do
      allow(vector_store).to receive(:count).and_return(7)
      expect(vector_store).to receive(:count).with(
        collection: 'library_summaries',
        filter: nil,
        exact: true
      )
      expect(store.conversation_count).to eq(7)
    end

    it 'narrows to scope_app IN [app_name, "Global"] when app_name is given' do
      expect(vector_store).to receive(:count).with(
        collection: 'library_summaries',
        filter: { must: [{ key: 'scope_app', match: { any: %w[CodeInterpreterOpenAI Global] } }] },
        exact: true
      )
      store.conversation_count(app_name: 'CodeInterpreterOpenAI')
    end
  end

  describe '#scroll' do
    let(:page) { { points: [{ 'id' => 'x' }], next: 'cursor-1' } }

    it 'forwards collection / filter / limit / offset to the vector store' do
      allow(vector_store).to receive(:scroll).and_return(page)
      expect(vector_store).to receive(:scroll).with(
        collection: 'library_summaries',
        filter: { must: [{ key: 'scope_app', match: { any: %w[ChatOpenAI Global] } }] },
        limit: 50, offset: 'cur-prev', with_vectors: false
      )
      store.scroll(
        collection: 'library_summaries',
        filter: store.scope_filter('ChatOpenAI'),
        limit: 50, offset: 'cur-prev'
      )
    end

    it 'forwards with_vectors when callers ask for raw embeddings' do
      allow(vector_store).to receive(:scroll).and_return(page)
      expect(vector_store).to receive(:scroll).with(
        hash_including(collection: 'library_summaries', with_vectors: true)
      )
      store.scroll(collection: 'library_summaries', with_vectors: true)
    end

    it 'returns the underlying page hash unchanged' do
      allow(vector_store).to receive(:scroll).and_return(page)
      expect(store.scroll(collection: 'library_summaries')).to eq(page)
    end

    it 'rejects non-Library collections' do
      expect {
        store.scroll(collection: 'pdf_docs')
      }.to raise_error(ArgumentError, /not a Library collection/)
    end
  end

  describe '#combine_filters' do
    it 'merges multiple `must` arrays into a single filter' do
      a = { must: [{ key: 'x', match: { value: 1 } }] }
      b = { must: [{ key: 'y', match: { value: 2 } }] }
      expect(store.combine_filters(a, b)).to eq(
        must: [
          { key: 'x', match: { value: 1 } },
          { key: 'y', match: { value: 2 } }
        ]
      )
    end

    it 'returns nil when there is nothing to combine' do
      expect(store.combine_filters(nil)).to be_nil
      expect(store.combine_filters({})).to be_nil
    end

    it 'ignores nil arguments' do
      a = { must: [{ key: 'x', match: { value: 1 } }] }
      expect(store.combine_filters(a, nil)).to eq(a)
    end
  end

  describe 'scope constants' do
    it 'exposes the "Global" sentinel as the cross-app scope value' do
      expect(described_class::SCOPE_GLOBAL).to eq('Global')
    end
  end

  describe '#scope_filter' do
    it 'returns nil for nil/empty input so KB-UI surfaces see every entry' do
      expect(store.scope_filter(nil)).to be_nil
      expect(store.scope_filter('   ')).to be_nil
    end

    it 'returns a match.any filter that includes the literal app name + Global' do
      f = store.scope_filter('ChatOpenAI')
      expect(f[:must].first[:match][:any]).to eq(%w[ChatOpenAI Global])
    end
  end
end
