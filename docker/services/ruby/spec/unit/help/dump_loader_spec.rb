# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tempfile'
require 'monadic/help/dump_loader'

RSpec.describe Monadic::Help::DumpLoader do
  let(:store) { instance_double(Monadic::VectorStore::Base) }
  let(:silent_log) { StringIO.new }

  def write_dump(payload)
    file = Tempfile.new(['dump', '.json'])
    file.write(JSON.dump(payload))
    file.close
    file.path
  end

  describe '.load' do
    it 'upserts every point in every collection in batches' do
      points = (1..10).map do |i|
        { 'id' => i, 'vector' => { 'content' => [0.1] * 768 }, 'payload' => { 'k' => i } }
      end
      path = write_dump(
        'version' => '1',
        'embedding_model' => 'intfloat/multilingual-e5-base',
        'embedding_dimension' => 768,
        'collections' => {
          'help_docs' => { 'points' => points },
          'help_items' => { 'points' => [] }
        }
      )

      received = []
      expect(store).to receive(:upsert_points).at_least(:once) do |args|
        received << args
      end

      counts = described_class.load(store: store, path: path, batch_size: 4, log: silent_log)
      expect(counts['help_docs']).to eq(10)
      expect(counts['help_items']).to eq(0)
      # 10 points / 4 per batch -> 3 calls for help_docs, 0 for empty help_items.
      help_docs_calls = received.select { |c| c[:collection] == 'help_docs' }
      expect(help_docs_calls.size).to eq(3)
      expect(help_docs_calls.flat_map { |c| c[:points] }.size).to eq(10)
    end

    it 'returns nil and logs when the version is unsupported' do
      path = write_dump('version' => '99', 'embedding_dimension' => 768)

      expect(store).not_to receive(:upsert_points)
      expect(described_class.load(store: store, path: path, log: silent_log)).to be_nil
      expect(silent_log.string).to match(/unsupported dump version/)
    end

    it 'returns nil when the dump dimension does not match the schema' do
      path = write_dump(
        'version' => '1', 'embedding_dimension' => 1536,
        'collections' => { 'help_docs' => { 'points' => [] } }
      )

      expect(store).not_to receive(:upsert_points)
      expect(described_class.load(store: store, path: path, log: silent_log)).to be_nil
      expect(silent_log.string).to match(/dimension mismatch/)
    end
  end
end
