# frozen_string_literal: true

require 'digest'
require 'tmpdir'
require_relative '../../../lib/monadic/library/originals'
require_relative '../../../lib/monadic/vector_store'

RSpec.describe Monadic::Library::Originals do
  let(:root) { Dir.mktmpdir('library-') }
  let(:source_dir) { Dir.mktmpdir('upload-') }

  before do
    allow(Monadic::Utils::Environment).to receive(:library_path).and_return(root)
    described_class.instance_variable_set(:@held, Hash.new(0))
  end

  after do
    FileUtils.rm_rf(root)
    FileUtils.rm_rf(source_dir)
  end

  def upload(name, bytes)
    path = File.join(source_dir, name)
    File.binwrite(path, bytes)
    path
  end

  def kept_files
    Dir.children(described_class.dir)
  end

  describe '.keep' do
    it 'keeps the bytes once, named by their SHA-256, private to the user' do
      kept = described_class.keep(upload('a.pdf', 'pdf bytes'))

      expect(kept).to eq(sha256: Digest::SHA256.hexdigest('pdf bytes'), bytes: 9)
      expect(kept_files).to eq([kept[:sha256]])
      expect(File.binread(described_class.path_of(kept[:sha256]))).to eq('pdf bytes')
      expect(File.stat(described_class.path_of(kept[:sha256])).mode & 0o777).to eq(0o600)
      expect(File.stat(described_class.dir).mode & 0o777).to eq(0o700)
    end

    it 'keeps the same bytes under other names as one file' do
      first = described_class.keep(upload('notes.md', 'same'))
      second = described_class.keep(upload('notes.rb', 'same'))

      expect(second[:sha256]).to eq(first[:sha256])
      expect(kept_files).to eq([first[:sha256]])
    end

    it 'refuses when the kept file of that name has other bytes' do
      sha256 = described_class.keep(upload('a.txt', 'original'))[:sha256]
      File.binwrite(described_class.path_of(sha256), 'replaced')

      expect { described_class.keep(upload('b.txt', 'original')) }.to raise_error(described_class::Changed)
      expect(File.binread(described_class.path_of(sha256))).to eq('replaced')
    end

    it 'leaves no part file behind' do
      described_class.keep(upload('a.txt', 'x'))

      expect(kept_files.grep(/\.part\z/)).to be_empty
    end
  end

  describe '.remove_if_unused' do
    let(:sha256) { described_class.keep(upload('a.pdf', 'bytes'))[:sha256] }

    it 'keeps a file an import still holds, whatever the count' do
      expect(described_class.remove_if_unused(sha256) { 0 }).to be false
      expect(File).to exist(described_class.path_of(sha256))
    end

    it 'removes it once released when no entry names it' do
      described_class.release(sha256)

      expect(described_class.remove_if_unused(sha256) { 0 }).to be true
      expect(File).not_to exist(described_class.path_of(sha256))
    end

    it 'keeps it while an entry names it' do
      described_class.release(sha256)

      expect(described_class.remove_if_unused(sha256) { 1 }).to be false
      expect(File).to exist(described_class.path_of(sha256))
    end

    it 'keeps it when the count cannot be had' do
      described_class.release(sha256)

      expect(described_class.remove_if_unused(sha256) { |_| raise Monadic::VectorStore::BackendError, 'down' }).to be false
      expect(described_class.remove_if_unused(sha256) { nil }).to be false
      expect(File).to exist(described_class.path_of(sha256))
    end

    it 'keeps it while a second import of the same bytes holds it' do
      described_class.keep(upload('again.pdf', 'bytes'))
      described_class.release(sha256)

      expect(described_class.remove_if_unused(sha256) { 0 }).to be false
      expect(File).to exist(described_class.path_of(sha256))
    end
  end

  describe '.read' do
    it 'gives the bytes kept' do
      sha256 = described_class.keep(upload('a.pdf', 'bytes'))[:sha256]

      expect(described_class.read(sha256)).to eq('bytes')
    end

    it 'says when the file is gone or changed' do
      sha256 = described_class.keep(upload('a.pdf', 'bytes'))[:sha256]
      File.binwrite(described_class.path_of(sha256), 'other')
      expect { described_class.read(sha256) }.to raise_error(described_class::Changed)

      File.delete(described_class.path_of(sha256))
      expect { described_class.read(sha256) }.to raise_error(described_class::Missing)
    end

    it 'does not follow a link in place of the file' do
      sha256 = described_class.keep(upload('a.pdf', 'bytes'))[:sha256]
      target = described_class.path_of(sha256)
      File.delete(target)
      File.symlink(upload('elsewhere', 'bytes'), target)

      expect { described_class.read(sha256) }.to raise_error(described_class::Missing)
    end

    it 'takes only a SHA-256 as the name' do
      expect { described_class.read('../escape') }.to raise_error(ArgumentError)
    end
  end
end
