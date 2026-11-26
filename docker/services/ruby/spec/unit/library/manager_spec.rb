# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'
require 'digest'
require 'tmpdir'

RSpec.describe Monadic::Library::Manager do
  let(:store) { instance_double(Monadic::Library::Store) }
  let(:embeddings) { instance_double(Monadic::Embeddings::Client) }

  before do
    allow(store).to receive(:embeddings).and_return(embeddings)
    allow(store).to receive(:bootstrap_collections!)
    allow(store).to receive(:upsert_points)
    allow(store).to receive(:delete_conversation).and_return(true)
    allow(store).to receive(:conversation_filter) { |id|
      { must: [{ key: 'conversation_id', match: { value: id.to_s } }] }
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

    it 'finds the newest entries on a later page when the first page fills the limit' do
      old = summary_point('old', 'created_at' => '2026-01-01T00:00:00Z')
      older = summary_point('older', 'created_at' => '2025-01-01T00:00:00Z')
      newest = summary_point('newest', 'created_at' => '2026-10-01T00:00:00Z')
      allow(store).to receive(:scroll).with(hash_including(offset: nil)).and_return({ points: [old, older], next: 'cur' })
      allow(store).to receive(:scroll).with(hash_including(offset: 'cur')).and_return({ points: [newest], next: nil })
      rows = described_class.list_conversations(store: store, limit: 2)
      expect(rows.map { |r| r[:conversation_id] }).to eq(%w[newest old])
    end

    it 'follows the scroll cursor across pages' do
      page1 = { points: [summary_point('a')], next: 'cur-1' }
      page2 = { points: [summary_point('b')], next: nil }
      expect(store).to receive(:scroll).with(hash_including(offset: nil)).and_return(page1)
      expect(store).to receive(:scroll).with(hash_including(offset: 'cur-1')).and_return(page2)
      rows = described_class.list_conversations(store: store)
      expect(rows.map { |r| r[:conversation_id] }).to contain_exactly('a', 'b')
    end

    it 'lists every entry, whatever app it was saved in' do
      expect(store).to receive(:scroll).with(hash_excluding(:filter)).and_return(
        points: [summary_point('A', 'scope_app' => 'ChatOpenAI'), summary_point('B')], next: nil
      )
      rows = described_class.list_conversations(store: store)
      expect(rows.map { |r| r[:conversation_id] }).to contain_exactly('A', 'B')
      expect(rows.first).not_to have_key(:scope_app)
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
    it 'reports the number of entries' do
      allow(store).to receive(:conversation_count).with(no_args).and_return(4)
      expect(described_class.library_stats(store: store)).to eq(conversations_total: 4)
    end
  end

  describe '.delete_conversation' do
    it 'forwards to Store#delete_conversation' do
      allow(store).to receive(:original_of).with('abc').and_return(nil)
      expect(described_class.delete_conversation(store: store, conversation_id: 'abc')).to be true
    end

    it 'then removes the kept file when no other entry names it' do
      sha256 = 'a' * 64
      allow(store).to receive(:original_of).with('abc').and_return('sha256' => sha256)
      allow(store).to receive(:original_refs).with(sha256).and_return(0)
      expect(store).to receive(:delete_conversation).with('abc').ordered
      expect(Monadic::Library::Originals).to receive(:remove_if_unused).with(sha256).ordered.and_call_original
      allow(File).to receive(:file?).and_call_original

      described_class.delete_conversation(store: store, conversation_id: 'abc')
    end
  end

  describe '.import_file' do
    let(:root) { Dir.mktmpdir('library-') }
    let(:upload) do
      path = File.join(root, 'upload.md')
      File.write(path, "# Notes\n\nSome text.\n")
      path
    end
    let(:sha256) { Digest::SHA256.file(upload).hexdigest }

    before do
      allow(Monadic::Utils::Environment).to receive(:library_path).and_return(File.join(root, 'library'))
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(root)
      Monadic::Library::Originals.instance_variable_set(:@held, Hash.new(0))
      allow(embeddings).to receive(:embed_passages) { |texts| texts.map { Array.new(768, 0.1) } }
    end

    after { FileUtils.rm_rf(root) }

    it 'keeps the file and names it on the entry as its original' do
      payloads = []
      allow(store).to receive(:upsert_points) { |collection:, points:| payloads.concat(points.map { |pt| [collection, pt[:payload]] }) }
      stages = []

      result = described_class.import_file(store: store, path: upload, filename: 'Notes.MD', on_stage: ->(s) { stages << s })

      original = { 'sha256' => sha256, 'filename' => 'Notes.MD', 'extension' => 'md', 'bytes' => File.size(upload) }
      expect(result[:original]).to eq(original)
      summary = payloads.find { |c, _| c == Monadic::VectorStore::Schema::LIBRARY_SUMMARIES }.last
      expect(summary['original']).to eq(original)
      expect(Monadic::Library::Originals.read(sha256)).to eq(File.binread(upload))
      expect(Monadic::Library::Originals.held?(sha256)).to be false
      expect(stages).to eq(%i[extracting embedding_storing])
    end

    it 'removes the kept file again when the import fails and nothing else names it' do
      allow(store).to receive(:upsert_points).and_raise(Monadic::VectorStore::BackendError, 'down')
      allow(store).to receive(:delete_point_ids)
      allow(store).to receive(:original_refs).with(sha256).and_return(0)

      expect { described_class.import_file(store: store, path: upload, filename: 'upload.md') }
        .to raise_error(Monadic::VectorStore::BackendError)
      expect { Monadic::Library::Originals.read(sha256) }.to raise_error(Monadic::Library::Originals::Missing)
    end

    it 'keeps the file when the import fails while another import holds the same bytes' do
      allow(store).to receive(:upsert_points).and_raise(Monadic::VectorStore::BackendError, 'down')
      allow(store).to receive(:delete_point_ids)
      allow(store).to receive(:original_refs).and_return(0)
      Monadic::Library::Originals.keep(upload)

      expect { described_class.import_file(store: store, path: upload, filename: 'upload.md') }
        .to raise_error(Monadic::VectorStore::BackendError)
      expect(Monadic::Library::Originals.read(sha256)).to eq(File.binread(upload))
    end

    it 'keeps the file when the import fails and the entries cannot be counted' do
      allow(store).to receive(:upsert_points).and_raise(Monadic::VectorStore::BackendError, 'down')
      allow(store).to receive(:delete_point_ids)
      allow(store).to receive(:original_refs).and_raise(Monadic::VectorStore::BackendError, 'down')

      expect { described_class.import_file(store: store, path: upload, filename: 'upload.md') }
        .to raise_error(Monadic::VectorStore::BackendError)
      expect(Monadic::Library::Originals.read(sha256)).to eq(File.binread(upload))
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

    it 'writes every point as Global' do
      conv = Monadic::Library::Importers::Markdown.import(
        "# Section\n\nbody body body. " * 10, filename: 'notes.md'
      )
      described_class.import_conversation(store: store, conversation: conv)
      expect(store).to have_received(:upsert_points).at_least(:once) do |args|
        expect(args[:points].map { |pt| pt[:payload]['scope_app'] }.uniq).to eq(['Global'])
      end
    end
  end
end
