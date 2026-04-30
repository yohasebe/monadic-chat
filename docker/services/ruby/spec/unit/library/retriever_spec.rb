# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Retriever do
  let(:store) { instance_double(Monadic::Library::Store) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }

  before do
    allow(store).to receive(:embeddings).and_return(embeddings)
    allow(store).to receive(:conversation_filter) { |id|
      { must: [{ key: 'conversation_id', match: { value: id.to_s } }] }
    }
    allow(embeddings).to receive(:embed_query).and_return(Array.new(768, 0.1))
  end

  def summary_hit(conv_id, score, title: nil, source: 'monadic-chat', language: 'en')
    {
      'id' => "summary-#{conv_id}", 'score' => score,
      'payload' => {
        'conversation_id' => conv_id, 'title' => title,
        'source' => source, 'language' => language
      }
    }
  end

  def turn_hit(conv_id, turn_idx, score, text:, speaker_role: 'human')
    {
      'id' => "turn-#{conv_id}-#{turn_idx}", 'score' => score,
      'payload' => {
        'conversation_id' => conv_id, 'turn_idx' => turn_idx,
        'text' => text, 'speaker_role' => speaker_role,
        'start_message_id' => "m-#{conv_id}-#{turn_idx}"
      }
    }
  end

  describe '.cascade_search (happy path)' do
    before do
      allow(store).to receive(:search).with(hash_including(collection: 'library_summaries')).and_return([
        summary_hit('A', 0.92, title: 'Talk A', source: 'ted-talk'),
        summary_hit('B', 0.81, title: 'Chat B', source: 'monadic-chat')
      ])
      allow(store).to receive(:search).with(hash_including(collection: 'library_turns')) do |args|
        cid = args[:filter][:must].first[:match][:value]
        case cid
        when 'A'
          [turn_hit('A', 3, 0.88, text: 'rare insight from A'),
           turn_hit('A', 7, 0.74, text: 'related point in A')]
        when 'B'
          [turn_hit('B', 1, 0.85, text: 'top match in B'),
           turn_hit('B', 5, 0.70, text: 'lower match in B')]
        end
      end
    end

    it 'embeds the query exactly once' do
      expect(embeddings).to receive(:embed_query).once.with('how to ...').and_return(Array.new(768, 0.1))
      described_class.cascade_search('how to ...', store: store)
    end

    it 'searches summaries with scope :external by default' do
      expect(store).to receive(:search).with(hash_including(
        collection: 'library_summaries', scope: :external, limit: 3
      )).and_return([])
      described_class.cascade_search('q', store: store)
    end

    it 'searches turns scoped to each candidate conversation' do
      hits = described_class.cascade_search('q', store: store)
      expect(hits.map { |h| h[:conversation_id] }).to contain_exactly('A', 'A', 'B')
    end

    it 'returns top_n hits sorted by turn-level score desc' do
      hits = described_class.cascade_search('q', store: store, top_n: 3)
      expect(hits.map { |h| h[:score] }).to eq([0.88, 0.85, 0.74])
    end

    it 'caps the result count at top_n' do
      hits = described_class.cascade_search('q', store: store, top_n: 2)
      expect(hits.size).to eq(2)
      expect(hits.first[:score]).to eq(0.88)
    end

    it 'decorates each hit with summary metadata for citation' do
      hits = described_class.cascade_search('q', store: store, top_n: 1)
      h = hits.first
      expect(h[:conversation_title]).to eq('Talk A')
      expect(h[:conversation_source]).to eq('ted-talk')
      expect(h[:text]).to eq('rare insight from A')
      expect(h[:turn_idx]).to eq(3)
    end
  end

  describe '.cascade_search (kb scope)' do
    it 'forwards :kb scope so personal data is included' do
      expect(store).to receive(:search).with(hash_including(scope: :kb)).at_least(:once).and_return([])
      described_class.cascade_search('q', store: store, scope: :kb)
    end
  end

  describe '.cascade_search (degenerate cases)' do
    it 'returns [] for an empty query' do
      expect(store).not_to receive(:search)
      expect(described_class.cascade_search('   ', store: store)).to eq([])
    end

    it 'returns [] when no summary hits' do
      allow(store).to receive(:search).and_return([])
      expect(described_class.cascade_search('q', store: store)).to eq([])
    end

    it 'skips conversations whose summary has no conversation_id' do
      allow(store).to receive(:search).with(hash_including(collection: 'library_summaries')).and_return([
        { 'score' => 0.9, 'payload' => {} } # no conversation_id
      ])
      expect(store).not_to receive(:search).with(hash_including(collection: 'library_turns'))
      expect(described_class.cascade_search('q', store: store)).to eq([])
    end
  end
end
