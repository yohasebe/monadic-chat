# frozen_string_literal: true

require_relative '../../spec_helper'
require 'tmpdir'
require_relative '../../../lib/monadic/library/desk_import'

RSpec.describe Monadic::Library::DeskImport do
  let(:root) { Dir.mktmpdir('desk-import-') }
  let(:sha) { 'a' * 64 }
  let(:entry) { { 'path' => 'conversations/c/workbench/notes.md', 'size' => 12, 'sha256' => sha } }
  let(:board) { double('board') }
  let(:store) { double('store') }
  let(:imported) { [] }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(root)
    allow(board).to receive(:file_entry).with('i_1', sha256: sha).and_return(entry)
    allow(board).to receive(:item).with('i_1').and_return({ 'id' => 'i_1', 'kind' => 'file', 'file' => entry })
    allow(board).to receive(:file_read).with('i_1', sha256: sha, limit: Monadic::Library::FileImporter::MAX_BYTES)
                                      .and_return(entry: entry, bytes: '# Notes text')
    allow(Thread).to receive(:new) { |&blk| blk.call }
    allow(Monadic::Library::Manager).to receive(:import_file) do |**kw|
      imported << kw.merge(bytes: File.binread(kw[:path]))
      { conversation_id: 'conv-1', counts: { summary: 1 } }
    end
    Monadic::Library::ImportTracker.reset!
  end

  after { FileUtils.rm_rf(root) }

  it 'imports a copy of the bytes checked against the version, and removes the copy' do
    import_id = described_class.start(board, 'i_1', sha, store: store)

    expect(imported.size).to eq(1)
    expect(imported.first).to include(store: store, filename: 'notes.md', options: { title: 'notes' }, bytes: '# Notes text')
    expect(File).not_to exist(imported.first[:path])
    expect(Monadic::Library::ImportTracker.get(import_id)).to include(stage: 'done', conversation_id: 'conv-1')
  end

  it 'refuses a file the Library does not take' do
    allow(board).to receive(:file_entry).and_return(entry.merge('path' => 'conversations/c/workbench/cat.png'))

    expect { described_class.start(board, 'i_1', sha, store: store) }
      .to raise_error(described_class::Refused, 'not_importable')
    expect(imported).to be_empty
  end

  it 'refuses a file larger than an import takes, before reading it' do
    allow(board).to receive(:file_entry).and_return(entry.merge('size' => Monadic::Library::FileImporter::MAX_BYTES + 1))

    expect { described_class.start(board, 'i_1', sha, store: store) }
      .to raise_error(described_class::Refused, 'too_large')
    expect(board).not_to have_received(:file_read)
  end

  it 'imports nothing when the document is not the version the tab shows' do
    allow(board).to receive(:file_entry).and_raise(Monadic::Workbench::Artifact::Changed, 'changed')

    expect { described_class.start(board, 'i_1', sha, store: store) }.to raise_error(Monadic::Workbench::Artifact::Changed)
    expect(imported).to be_empty
  end

  it 'says the import failed, by the kind of failure only, and removes the copy' do
    allow(Monadic::Library::Manager).to receive(:import_file) do |**kw|
      imported << kw
      raise Monadic::VectorStore::BackendError, 'qdrant down at /some/path'
    end

    import_id = described_class.start(board, 'i_1', sha, store: store)

    expect(Monadic::Library::ImportTracker.get(import_id)).to include(stage: 'error', error: 'BackendError')
    expect(File).not_to exist(imported.first[:path])
  end

  describe 'a record of a conversation' do
    let(:record_bytes) { "# Tides and moons\n\n_App: Chat_\n\n## User\n\nWhy tides?\n" }
    let(:records) { [] }

    before do
      allow(board).to receive(:item).with('i_1')
                                    .and_return({ 'id' => 'i_1', 'kind' => 'file', 'file' => entry, 'draft' => { 'source_chat_id' => 'c_1' } })
      allow(board).to receive(:file_read).and_return(entry: entry, bytes: record_bytes)
      allow(store).to receive(:records_from_chat).with('c_1') { records }
      allow(Monadic::Library::Manager).to receive(:replace_file) do |**kw|
        imported << kw.merge(replaced: true)
        { conversation_id: kw[:conversation_id], counts: { summary: 1 }, updated: true, leftover: false }
      end
    end

    it 'is kept titled by its first heading, as a conversation, naming its chat' do
      import_id = described_class.start(board, 'i_1', sha, app_name: 'ChatOpenAI', store: store)

      expect(imported.first[:options]).to eq(title: 'Tides and moons', content_type: 'conversation',
                                             source: 'monadic-chat', source_chat_id: 'c_1')
      expect(Monadic::Library::ImportTracker.get(import_id)).to include(stage: 'done')
    end

    it 'is refused for an app that does not keep its chats' do
      allow(Monadic::Library::ConversationDraft).to receive(:app_allows?).with('ImageGeneratorOpenAI').and_return(false)

      expect { described_class.start(board, 'i_1', sha, app_name: 'ImageGeneratorOpenAI', store: store) }
        .to raise_error(described_class::Refused, 'not_saved_by_app')
      expect(imported).to be_empty
    end

    it 'asks the user to choose when records of its chat are kept, with them, newest first' do
      records << { conversation_id: 'conv-2', title: 'Later', created_at: 't2', revision: 'v2' } << { conversation_id: 'conv-1', title: 'Tides', created_at: 't1', revision: 'v1' }

      expect { described_class.start(board, 'i_1', sha, store: store) }
        .to raise_error(described_class::Choose) { |e| expect(e.records.map { |r| r[:conversation_id] }).to eq(%w[conv-2 conv-1]) }
      expect(imported).to be_empty
    end

    it 'keeps it besides the others, or updates the chosen one as it was offered' do
      records << { conversation_id: 'conv-1', title: 'Tides', created_at: 't1', revision: 'v1' }

      described_class.start(board, 'i_1', sha, choice: 'new', store: store)
      expect(imported.last).not_to include(:replaced)

      import_id = described_class.start(board, 'i_1', sha, choice: { 'update' => 'conv-1', 'seen' => 'v1' }, store: store)
      expect(imported.last).to include(replaced: true, conversation_id: 'conv-1', revision: 'v1')
      expect(Monadic::Library::ImportTracker.get(import_id)).to include(updated: true, conversation_id: 'conv-1')
    end

    it 'updates nothing when the chosen record changed since it was offered, or is gone' do
      records << { conversation_id: 'conv-1', title: 'Tides', created_at: 't1', revision: 'v9' }

      expect { described_class.start(board, 'i_1', sha, choice: { 'update' => 'conv-1', 'seen' => 'v1' }, store: store) }
        .to raise_error(described_class::Refused, 'record_changed')
      expect { described_class.start(board, 'i_1', sha, choice: { 'update' => 'conv-x', 'seen' => 't1' }, store: store) }
        .to raise_error(described_class::Refused, 'record_missing')
      expect(imported).to be_empty
    end

    it 'is titled as the user names it, else by its first heading wherever it is' do
      described_class.start(board, 'i_1', sha, title: '  My notes  ', store: store)
      expect(imported.last[:options][:title]).to eq('My notes')

      allow(board).to receive(:file_read).and_return(entry: entry, bytes: "Some words first.\n\n# C#\n\nText.\n")
      described_class.start(board, 'i_1', sha, title: '', store: store)
      expect(imported.last[:options][:title]).to eq('C#')
    end

    it 'keeps one record of a chat at a time' do
      allow(Thread).to receive(:new)

      described_class.start(board, 'i_1', sha, store: store)
      expect { described_class.start(board, 'i_1', sha, choice: 'new', store: store) }
        .to raise_error(described_class::Refused, 'in_progress')
    ensure
      described_class.release('c_1')
    end

    it 'lets the chat be kept again when its keep is refused before it starts' do
      records << { conversation_id: 'conv-1', title: 'Tides', created_at: 't1', revision: 'v1' }
      expect { described_class.start(board, 'i_1', sha, store: store) }.to raise_error(described_class::Choose)

      described_class.start(board, 'i_1', sha, choice: 'new', store: store)
      expect(imported.size).to eq(1)
    end

    it 'is titled by its file name when it has no heading' do
      allow(board).to receive(:file_read).and_return(entry: entry, bytes: "no heading here\n")

      described_class.start(board, 'i_1', sha, store: store)

      expect(imported.first[:options][:title]).to eq('notes')
    end
  end
end
