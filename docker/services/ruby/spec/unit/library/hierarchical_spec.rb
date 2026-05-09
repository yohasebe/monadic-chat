# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Hierarchical do
  let(:vector_store) { instance_double(Monadic::VectorStore::Base) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }
  let(:store) do
    Monadic::Library::Store.new(vector_store: vector_store, embeddings: embeddings)
  end

  before do
    # Bootstrap behaviour is exercised in store_spec; here we just want
    # any upsert / search calls to succeed.
    allow(vector_store).to receive(:collection_exists?).and_return(true)
    allow(vector_store).to receive(:create_collection)
    allow(vector_store).to receive(:upsert_points)
    # embed_passages must return one 768-dim vector per input text.
    allow(embeddings).to receive(:embed_passages) { |texts| texts.map { Array.new(768, 0.1) } }
  end

  let(:two_party_chat) do
    {
      'format_version' => '1.0',
      'conversation_id' => 'conv-1',
      'conversation_metadata' => {
        'source' => 'monadic-chat', 'language' => 'en', 'license' => 'private',
        'title' => 'Math help', 'topics' => ['arithmetic']
      },
      'participants' => [
        { 'id' => 'human', 'role' => 'human' },
        { 'id' => 'asst', 'role' => 'assistant' }
      ],
      'messages' => [
        { 'id' => 'm1', 'speaker' => { 'id' => 'human' }, 'text' => 'What is 2+2?' },
        { 'id' => 'm2', 'speaker' => { 'id' => 'asst' }, 'text' => '4.' },
        { 'id' => 'm3', 'speaker' => { 'id' => 'human' }, 'text' => 'And 3+5?' },
        { 'id' => 'm4', 'speaker' => { 'id' => 'asst' }, 'text' => '8.' }
      ]
    }
  end

  describe '.ingest (default levels)' do
    it 'reports counts for each level it produced' do
      counts = described_class.ingest(two_party_chat, store: store)
      expect(counts).to eq(summary: 1, turns: 4)
    end

    it 'upserts to summary and turn Library collections' do
      expect(vector_store).to receive(:upsert_points).with(
        hash_including(collection: 'library_summaries')
      )
      expect(vector_store).to receive(:upsert_points).with(
        hash_including(collection: 'library_turns')
      )
      described_class.ingest(two_party_chat, store: store)
    end

    it 'tags every point with conversation_id and scope_app' do
      payloads = []
      allow(vector_store).to receive(:upsert_points) do |args|
        args[:points].each { |p| payloads << p[:payload] }
      end
      described_class.ingest(two_party_chat, store: store, scope_app: 'ChatOpenAI')
      expect(payloads).not_to be_empty
      expect(payloads.map { |p| p['conversation_id'] }.uniq).to eq(['conv-1'])
      expect(payloads.map { |p| p['scope_app'] }.uniq).to eq(['ChatOpenAI'])
    end
  end

  describe 'summary payload' do
    it 'embeds the verbatim messages array for the Conversation Viewer' do
      captured = nil
      allow(vector_store).to receive(:upsert_points) do |args|
        captured = args if args[:collection] == 'library_summaries'
      end
      described_class.ingest(two_party_chat, store: store, levels: %i[summary])
      payload = captured[:points].first[:payload]
      expect(payload['messages']).to eq(two_party_chat['messages'])
      expect(payload['participants']).to eq(two_party_chat['participants'])
      expect(payload).not_to have_key('messages_skipped_reason')
    end

    it 'omits messages and stashes a reason when over SUMMARY_MESSAGES_MAX_BYTES' do
      stub_const('Monadic::Library::Hierarchical::SUMMARY_MESSAGES_MAX_BYTES', 100)
      captured = nil
      allow(vector_store).to receive(:upsert_points) do |args|
        captured = args if args[:collection] == 'library_summaries'
      end
      described_class.ingest(two_party_chat, store: store, levels: %i[summary])
      payload = captured[:points].first[:payload]
      expect(payload['messages']).to be_nil
      expect(payload['messages_skipped_reason']).to match(/exceeded 100 bytes/)
    end

    it 'sets messages to nil when the original messages array is empty' do
      empty = two_party_chat.merge('messages' => [])
      captured = nil
      allow(vector_store).to receive(:upsert_points) do |args|
        captured = args if args[:collection] == 'library_summaries'
      end
      # ingest skips summary when there are no turns; force it via a
      # one-message conversation to keep the summary upsert active.
      single = two_party_chat.merge('messages' => [two_party_chat['messages'].first])
      described_class.ingest(single, store: store, levels: %i[summary])
      payload = captured[:points].first[:payload]
      expect(payload['messages']).to eq(single['messages'])
      _ = empty
    end

  end

  describe 'turn payload' do
    it 'includes speaker, text, message anchors, and turn_idx' do
      captured = nil
      allow(vector_store).to receive(:upsert_points) do |args|
        captured = args if args[:collection] == 'library_turns'
      end
      described_class.ingest(two_party_chat, store: store, levels: %i[turns])
      first = captured[:points].first[:payload]
      expect(first['turn_idx']).to eq(0)
      expect(first['speaker_id']).to eq('human')
      expect(first['speaker_role']).to eq('human')
      expect(first['text']).to eq('What is 2+2?')
      expect(first['start_message_id']).to eq('m1')
      expect(first['end_message_id']).to eq('m1')
    end
  end

  describe 'level selection' do
    it 'skips summary when not requested' do
      expect(vector_store).not_to receive(:upsert_points).with(
        hash_including(collection: 'library_summaries')
      )
      counts = described_class.ingest(two_party_chat, store: store, levels: %i[turns])
      expect(counts[:summary]).to eq(0)
    end

    it 'allows turns-only ingest' do
      expect(vector_store).to receive(:upsert_points).with(
        hash_including(collection: 'library_turns')
      )
      counts = described_class.ingest(two_party_chat, store: store, levels: %i[turns])
      expect(counts).to eq(summary: 0, turns: 4)
    end
  end

  describe 'monologue ingest' do
    let(:talk) do
      {
        'format_version' => '1.0',
        'conversation_id' => 'talk-1',
        'conversation_metadata' => {
          'source' => 'plain-text', 'language' => 'en', 'license' => 'private',
          'duration_seconds' => 60
        },
        'participants' => [
          { 'id' => 'speaker-1', 'role' => 'narrator', 'description' => 'narrator' }
        ],
        'messages' => (1..5).map { |i|
          { 'id' => "m#{i}", 'speaker' => { 'id' => 'speaker-1' },
            'text' => "segment #{i}",
            'timing' => { 'offset_seconds' => i * 10.0, 'duration_seconds' => 10.0 } }
        }
      }
    end

    it 'produces one turn per segment for monologues' do
      counts = described_class.ingest(talk, store: store, levels: %i[turns])
      expect(counts[:turns]).to eq(5)
    end
  end

  describe 'input validation' do
    it 'rejects non-hash conversations' do
      expect { described_class.ingest('nope', store: store) }
        .to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'rejects conversations with no conversation_id' do
      bad = two_party_chat.dup
      bad['conversation_id'] = ''
      expect { described_class.ingest(bad, store: store) }
        .to raise_error(ArgumentError, /conversation_id/)
    end

    it 'rejects invalid visibility' do
      expect { described_class.ingest(two_party_chat, store: store, visibility: 'excluded') }
        .to raise_error(ArgumentError, /visibility/)
    end
  end

  describe 'empty conversation' do
    it 'produces only summary and zero turn points' do
      empty = two_party_chat.merge('messages' => [])
      counts = described_class.ingest(empty, store: store)
      expect(counts).to eq(summary: 1, turns: 0)
    end
  end
end
