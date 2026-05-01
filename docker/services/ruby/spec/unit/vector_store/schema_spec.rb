# frozen_string_literal: true

require 'spec_helper'
require 'monadic/vector_store/schema'

RSpec.describe Monadic::VectorStore::Schema do
  describe 'collection identifiers' do
    it 'enumerates Help/Pdf and Library collections in ALL_COLLECTIONS' do
      expect(described_class::ALL_COLLECTIONS).to contain_exactly(
        'help_docs', 'help_items',
        'pdf_docs', 'pdf_items',
        'library_summaries', 'library_turns', 'library_messages'
      )
    end

    it 'exposes LIBRARY_COLLECTIONS as a subset of ALL_COLLECTIONS' do
      expect(described_class::LIBRARY_COLLECTIONS).to contain_exactly(
        'library_summaries', 'library_turns', 'library_messages'
      )
      expect(described_class::ALL_COLLECTIONS).to include(*described_class::LIBRARY_COLLECTIONS)
    end

    it 'has a DEFINITIONS entry for every collection' do
      missing = described_class::ALL_COLLECTIONS.reject do |name|
        described_class::DEFINITIONS.key?(name)
      end
      expect(missing).to be_empty
    end
  end

  describe 'vector configuration' do
    it 'uses the e5-base dimension (768) everywhere' do
      sizes = described_class::DEFINITIONS.values.flat_map do |defn|
        defn[:vectors].values.map { |v| v[:size] }
      end
      expect(sizes.uniq).to eq([768])
    end

    it 'uses Cosine distance for all collections (matches L2-normalized e5)' do
      distances = described_class::DEFINITIONS.values.flat_map do |defn|
        defn[:vectors].values.map { |v| v[:distance] }
      end
      expect(distances.uniq).to eq(['Cosine'])
    end
  end

  describe 'payload indexes' do
    it 'indexes language for both help collections' do
      help_doc_fields = described_class::DEFINITIONS['help_docs'][:payload_indexes].map { |i| i[:field] }
      help_item_fields = described_class::DEFINITIONS['help_items'][:payload_indexes].map { |i| i[:field] }
      expect(help_doc_fields).to include('language')
      expect(help_item_fields).to include('language')
    end

    it 'indexes doc_id on item-level collections so per-document scrolls are fast' do
      %w[help_items pdf_items].each do |coll|
        fields = described_class::DEFINITIONS[coll][:payload_indexes].map { |i| i[:field] }
        expect(fields).to include('doc_id'), "expected doc_id index on #{coll}"
      end
    end
  end
end
