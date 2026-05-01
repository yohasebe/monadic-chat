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
    # Mirror the real Store#combine_filters: AND the :must clauses of the
    # supplied filters, dropping nils. Tests that omit payload_filter still
    # see only the conversation_id clause; tests that pass one see both.
    allow(store).to receive(:combine_filters) { |*filters|
      merged = { must: [] }
      filters.compact.each do |f|
        merged[:must].concat(Array(f[:must])) if f.is_a?(Hash) && f[:must]
      end
      merged[:must].empty? ? nil : merged
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

    it 'searches summaries with scope :external and the configured summary_top_k by default' do
      expect(store).to receive(:search).with(hash_including(
        collection: 'library_summaries',
        scope: :external,
        limit: Monadic::Library::Retriever::DEFAULT_SUMMARY_TOP_K
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

  describe '.cascade_search payload_filter pass-through' do
    let(:payload_filter) { { must: [{ key: 'source', match: { value: 'monadic-chat' } }] } }

    it 'forwards payload_filter to the summary pass' do
      summary_filter_seen = nil
      allow(store).to receive(:search).with(hash_including(collection: 'library_summaries')) do |args|
        summary_filter_seen = args[:filter]
        []
      end
      described_class.cascade_search('q', store: store, payload_filter: payload_filter)
      expect(summary_filter_seen).to eq(payload_filter)
    end

    it 'does NOT forward payload_filter to the turn pass (turn payloads lack source/content_type)' do
      # Turn-level payloads only carry conversation_id / visibility /
      # turn_idx — narrowing fields like `source` live on the summary
      # alone. Applying payload_filter here would return zero turn hits
      # whenever the LLM uses a narrowing param. Guard against regression.
      allow(store).to receive(:search).with(hash_including(collection: 'library_summaries')).and_return([
        summary_hit('A', 0.92, title: 'Talk A', source: 'monadic-chat')
      ])
      turn_filter_seen = nil
      allow(store).to receive(:search).with(hash_including(collection: 'library_turns')) do |args|
        turn_filter_seen = args[:filter]
        []
      end
      described_class.cascade_search('q', store: store, payload_filter: payload_filter)
      expect(turn_filter_seen).to eq(
        { must: [{ key: 'conversation_id', match: { value: 'A' } }] }
      )
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
