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
end
