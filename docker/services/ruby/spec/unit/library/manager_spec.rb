# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::Manager do
  let(:store) { instance_double(Monadic::Library::Store) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }

  before do
    allow(store).to receive(:embeddings).and_return(embeddings)
    allow(store).to receive(:bootstrap_collections!)
    allow(store).to receive(:upsert_points)
    allow(store).to receive(:delete_conversation).and_return(true)
    allow(store).to receive(:visibility_filter) { |scope|
      case scope
      when :kb       then { must: [{ key: 'visibility', match: { any: %w[personal shareable] } }] }
      when :external then { must: [{ key: 'visibility', match: { value: 'shareable' } }] }
      end
    }
    allow(store).to receive(:conversation_filter) { |id|
      { must: [{ key: 'conversation_id', match: { value: id.to_s } }] }
    }
    allow(store).to receive(:combine_filters) { |*fs|
      m = fs.compact.flat_map { |f| Array(f[:must]) }
      m.empty? ? nil : { must: m }
    }
    allow(store).to receive(:conversation_count).and_return(0)
  end

  def summary_point(conv_id, payload_extras = {})
    {
      'id' => "summary-#{conv_id}",
      'vector' => { 'content' => Array.new(768, 0.0) },
      'payload' => {
        'conversation_id' => conv_id,
        'visibility' => 'personal',
        'source' => 'monadic-chat',
        'language' => 'en',
        'title' => "Conv #{conv_id}",
        'license' => 'private',
        'messages_count' => 4,
        'turns_count' => 2,
        'created_at' => "2026-04-#{conv_id.length.to_s.rjust(2, '0')}T00:00:00Z"
      }.merge(payload_extras)
    }
  end

  describe '.list_conversations' do
    it 'returns rows ordered by created_at desc' do
      allow(store).to receive(:scroll).and_return(
        { points: [summary_point('A'), summary_point('LONGER')], next: nil }
      )
      rows = described_class.list_conversations(store: store)
      expect(rows.map { |r| r[:conversation_id] }).to eq(%w[LONGER A])
    end

    it 'caps result at the requested limit' do
      allow(store).to receive(:scroll).and_return(
        { points: [summary_point('A'), summary_point('B'), summary_point('C')], next: nil }
      )
      rows = described_class.list_conversations(store: store, limit: 2)
      expect(rows.size).to eq(2)
    end

    it 'follows the scroll cursor across pages' do
      page1 = { points: [summary_point('a')], next: 'cur-1' }
      page2 = { points: [summary_point('b')], next: nil }
      expect(store).to receive(:scroll).with(hash_including(offset: nil)).and_return(page1)
      expect(store).to receive(:scroll).with(hash_including(offset: 'cur-1')).and_return(page2)
      rows = described_class.list_conversations(store: store)
      expect(rows.map { |r| r[:conversation_id] }).to contain_exactly('a', 'b')
    end
  end

  describe '.get_conversation_details' do
    it 'returns nil when no matching summary' do
      allow(store).to receive(:scroll).and_return(points: [], next: nil)
      expect(described_class.get_conversation_details(store: store, conversation_id: 'X')).to be_nil
    end

    it 'returns the summary row when found' do
      allow(store).to receive(:scroll).and_return(points: [summary_point('A')], next: nil)
      row = described_class.get_conversation_details(store: store, conversation_id: 'A')
      expect(row[:conversation_id]).to eq('A')
      expect(row[:title]).to eq('Conv A')
    end
  end

  describe '.library_stats' do
    it 'reports total / personal / shareable counts' do
      allow(store).to receive(:conversation_count).with(scope: :kb).and_return(10)
      allow(store).to receive(:conversation_count).with(scope: :external).and_return(3)
      stats = described_class.library_stats(store: store)
      expect(stats).to eq(
        conversations_total: 10,
        conversations_shareable: 3,
        conversations_personal: 7
      )
    end
  end

  describe '.update_visibility' do
    it 'rewrites visibility on every Library collection' do
      Monadic::VectorStore::Schema::LIBRARY_COLLECTIONS.each do |c|
        allow(store).to receive(:scroll).with(hash_including(collection: c)).and_return(
          { points: [{ 'id' => 'p1', 'vector' => { 'content' => [] }, 'payload' => { 'conversation_id' => 'x', 'visibility' => 'personal' } }], next: nil }
        )
      end

      Monadic::VectorStore::Schema::LIBRARY_COLLECTIONS.each do |c|
        expect(store).to receive(:upsert_points).with(
          collection: c,
          points: [hash_including(payload: hash_including('visibility' => 'shareable'))]
        )
      end
      described_class.update_visibility(store: store, conversation_id: 'x', visibility: 'shareable')
    end

    it 'rejects an invalid visibility value' do
      expect {
        described_class.update_visibility(store: store, conversation_id: 'x', visibility: 'gone')
      }.to raise_error(ArgumentError, /visibility/)
    end
  end

  describe '.delete_conversation' do
    it 'forwards to Store#delete_conversation' do
      expect(store).to receive(:delete_conversation).with('abc').and_return(true)
      expect(described_class.delete_conversation(store: store, conversation_id: 'abc')).to be true
    end
  end

  describe '.import_from_text' do
    let(:plain_text_input) do
      "Alice: Hello, Bob.\nBob: Hi Alice.\n"
    end

    before do
      # embed_passages must return one vector per text input.
      allow(embeddings).to receive(:embed_passages) { |texts| texts.map { Array.new(768, 0.1) } }
      allow(store).to receive(:upsert_points)
    end

    it 'auto-detects PlainText, ingests, and returns counts' do
      result = described_class.import_from_text(
        store: store, input: plain_text_input, options: { license: 'CC-BY-4.0' }
      )
      expect(result[:importer]).to eq('PlainText')
      expect(result[:counts][:turns]).to be > 0
      expect(result[:conversation_id]).not_to be_nil
    end

    it 'parses JSON input as ChatML when system role is present (Anthropic excludes system)' do
      json_input = JSON.dump([
        { 'role' => 'system', 'content' => 'Be brief.' },
        { 'role' => 'user', 'content' => 'hi' },
        { 'role' => 'assistant', 'content' => 'hello' }
      ])
      result = described_class.import_from_text(store: store, input: json_input)
      expect(result[:importer]).to eq('ChatML')
    end

    it 'parses bare user/assistant JSON as AnthropicMessages (more specific than ChatML)' do
      json_input = JSON.dump([
        { 'role' => 'user', 'content' => 'hi' },
        { 'role' => 'assistant', 'content' => 'hello' }
      ])
      result = described_class.import_from_text(store: store, input: json_input)
      expect(result[:importer]).to eq('AnthropicMessages')
    end

    it 'raises for unrecognised input' do
      expect {
        described_class.import_from_text(store: store, input: '???random???')
      }.to raise_error(ArgumentError, /known conversation format/)
    end
  end

  describe '.update_title' do
    let(:summary_pt) { summary_point('rename-me', 'title' => 'Old Title') }

    before do
      allow(store).to receive(:scroll).and_return({ points: [summary_pt], next: nil })
    end

    it 'rewrites the title on the summaries collection' do
      expect(store).to receive(:upsert_points) do |args|
        expect(args[:collection]).to eq(Monadic::VectorStore::Schema::LIBRARY_SUMMARIES)
        expect(args[:points].first[:payload]['title']).to eq('New Title')
      end
      result = described_class.update_title(
        store: store, conversation_id: 'rename-me', title: 'New Title'
      )
      expect(result).to be true
    end

    it 'strips whitespace from the title before storing' do
      expect(store).to receive(:upsert_points) do |args|
        expect(args[:points].first[:payload]['title']).to eq('Trimmed')
      end
      described_class.update_title(store: store, conversation_id: 'rename-me', title: '  Trimmed  ')
    end

    it 'rejects a blank title' do
      expect {
        described_class.update_title(store: store, conversation_id: 'rename-me', title: '   ')
      }.to raise_error(ArgumentError, /must not be blank/)
    end

    it 'rejects a title longer than the cap' do
      expect {
        described_class.update_title(
          store: store, conversation_id: 'rename-me',
          title: 'X' * (described_class::MAX_TITLE_LENGTH + 1)
        )
      }.to raise_error(ArgumentError, /characters or fewer/)
    end
  end

  describe '.import_conversation' do
    before do
      allow(embeddings).to receive(:embed_passages) { |texts| texts.map { Array.new(768, 0.1) } }
      allow(store).to receive(:upsert_points)
    end

    it 'ingests a pre-built v1 conversation directly (skipping dispatch)' do
      conv = Monadic::Library::Importers::Markdown.import(
        "# Section\n\n" + ('Body. ' * 50), filename: 'notes.md'
      )
      result = described_class.import_conversation(store: store, conversation: conv)
      expect(result[:conversation_id]).to eq(conv['conversation_id'])
      expect(result[:counts][:turns]).to be > 0
    end

    it 'forwards visibility to Hierarchical.ingest' do
      conv = Monadic::Library::Importers::Markdown.import(
        "# Section\n\nbody body body. " * 10, filename: 'notes.md'
      )
      described_class.import_conversation(
        store: store, conversation: conv, visibility: Monadic::Library::Store::VISIBILITY_SHAREABLE
      )
      expect(store).to have_received(:upsert_points).at_least(:once) do |args|
        payload = args[:points].first[:payload]
        expect(payload['visibility']).to eq('shareable')
      end
    end
  end
end
