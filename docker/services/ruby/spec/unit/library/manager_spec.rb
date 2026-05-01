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
    allow(store).to receive(:scope_filter) { |app|
      s = app.to_s.strip
      next nil if s.empty?
      { must: [{ key: 'scope_app', match: { any: [s, 'Global'] } }] }
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
        'scope_app' => 'Global',
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

    it 'narrows to entries the requesting app can see when app_name is given' do
      expect(store).to receive(:scroll).with(
        hash_including(filter: hash_including(must: include(hash_including(key: 'scope_app'))))
      ).and_return(points: [summary_point('A')], next: nil)
      described_class.list_conversations(store: store, app_name: 'ChatOpenAI')
    end

    it 'omits the scope filter when app_name is nil (KB UI behaviour)' do
      expect(store).to receive(:scroll).with(hash_including(filter: nil)).and_return(points: [], next: nil)
      described_class.list_conversations(store: store, app_name: nil)
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
      expect(row[:scope_app]).to eq('Global')
    end
  end

  describe '.library_stats' do
    it 'reports total + a per-scope breakdown' do
      allow(store).to receive(:conversation_count).with(no_args).and_return(4)
      allow(store).to receive(:scroll).and_return(
        { points: [
            summary_point('a', 'scope_app' => 'Global'),
            summary_point('b', 'scope_app' => 'ChatOpenAI'),
            summary_point('c', 'scope_app' => 'ChatOpenAI'),
            summary_point('d', 'scope_app' => 'KnowledgeBaseClaude')
          ],
          next: nil }
      )
      stats = described_class.library_stats(store: store)
      expect(stats[:conversations_total]).to eq(4)
      expect(stats[:conversations_by_scope]).to eq(
        'Global' => 1, 'ChatOpenAI' => 2, 'KnowledgeBaseClaude' => 1
      )
    end

    it 'falls back to "Global" when scope_app is missing on legacy points' do
      allow(store).to receive(:conversation_count).with(no_args).and_return(1)
      allow(store).to receive(:scroll).and_return(
        { points: [{ 'payload' => { 'conversation_id' => 'x' } }], next: nil }
      )
      stats = described_class.library_stats(store: store)
      expect(stats[:conversations_by_scope]).to eq('Global' => 1)
    end
  end

  describe '.delete_conversation' do
    it 'forwards to Store#delete_conversation' do
      expect(described_class.delete_conversation(store: store, conversation_id: 'abc')).to be true
    end
  end

  describe '.update_scope_app' do
    let(:scoped_pt) { summary_point('flip-me', 'scope_app' => 'ChatOpenAI') }

    before do
      allow(store).to receive(:scroll).and_return({ points: [scoped_pt], next: nil })
    end

    it 'rewrites scope_app on every Library collection' do
      expect(store).to receive(:upsert_points)
        .at_least(:once) do |args|
          expect(args[:points].first[:payload]['scope_app']).to eq('Global')
        end
      result = described_class.update_scope_app(
        store: store, conversation_id: 'flip-me', scope_app: 'Global'
      )
      expect(result).to be true
    end

    it 'rejects a blank scope_app value' do
      expect {
        described_class.update_scope_app(store: store, conversation_id: 'flip-me', scope_app: '   ')
      }.to raise_error(ArgumentError, /scope_app must be a non-empty string/)
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

  describe '.import_from_text' do
    let(:plain_text_input) do
      "Alice: Hello, Bob.\nBob: Hi Alice.\n"
    end

    before do
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

    it 'parses JSON input as ChatML when system role is present' do
      json_input = JSON.dump([
        { 'role' => 'system', 'content' => 'Be brief.' },
        { 'role' => 'user', 'content' => 'hi' },
        { 'role' => 'assistant', 'content' => 'hello' }
      ])
      result = described_class.import_from_text(store: store, input: json_input)
      expect(result[:importer]).to eq('ChatML')
    end

    it 'parses bare user/assistant JSON as AnthropicMessages' do
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

  describe '.import_conversation' do
    before do
      allow(embeddings).to receive(:embed_passages) { |texts| texts.map { Array.new(768, 0.1) } }
      allow(store).to receive(:upsert_points)
    end

    it 'ingests a pre-built v1 conversation directly' do
      conv = Monadic::Library::Importers::Markdown.import(
        "# Section\n\n" + ('Body. ' * 50), filename: 'notes.md'
      )
      result = described_class.import_conversation(store: store, conversation: conv)
      expect(result[:conversation_id]).to eq(conv['conversation_id'])
      expect(result[:counts][:turns]).to be > 0
    end

    it 'forwards scope_app to Hierarchical.ingest' do
      conv = Monadic::Library::Importers::Markdown.import(
        "# Section\n\nbody body body. " * 10, filename: 'notes.md'
      )
      described_class.import_conversation(
        store: store, conversation: conv, scope_app: 'ChatOpenAI'
      )
      expect(store).to have_received(:upsert_points).at_least(:once) do |args|
        payload = args[:points].first[:payload]
        expect(payload['scope_app']).to eq('ChatOpenAI')
      end
    end
  end
end
