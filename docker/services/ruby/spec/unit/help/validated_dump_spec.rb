# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'monadic/help/validated_dump'

RSpec.describe Monadic::Help::ValidatedDump do
  around do |example|
    Dir.mktmpdir('help-dump-spec') do |dir|
      @path = File.join(dir, 'dump.json')
      example.run
    end
  end

  let(:point) { { 'id' => 1, 'vector' => { 'content' => [0.1] * 768 }, 'payload' => { 'is_internal' => false } } }
  let(:data) do
    {
      'version' => '1', 'embedding_model' => described_class::MODEL, 'embedding_dimension' => 768,
      'collections' => {
        'help_docs' => { 'points' => [Marshal.load(Marshal.dump(point))] },
        'help_items' => { 'points' => [point.merge('payload' => { 'is_internal' => false, 'doc_id' => 1 })] }
      }
    }
  end

  def load_dump
    File.write(@path, JSON.generate(data))
    described_class.new(@path)
  end

  it 'hashes the exact validated bytes and records both counts' do
    dump = load_dump
    expect(dump.sha256).to eq(Digest::SHA256.file(@path).hexdigest)
    expect(dump.record('job')).to include('expected_docs' => 1, 'expected_items' => 1, 'state' => 'installing')
  end

  {
    'version' => '99', 'embedding_model' => 'other-model', 'embedding_dimension' => '768'
  }.each do |key, value|
    it "rejects incompatible #{key}" do
      data[key] = value
      expect { load_dump }.to raise_error(described_class::Invalid)
    end
  end

  it 'rejects a missing file and malformed JSON' do
    expect { described_class.new(@path) }.to raise_error(described_class::Invalid)
    File.write(@path, '{')
    expect { described_class.new(@path) }.to raise_error(described_class::Invalid)
  end

  [nil, [], true, 'text'].each do |root|
    it "rejects non-object root #{root.inspect}" do
      File.write(@path, JSON.generate(root))
      expect { described_class.new(@path) }.to raise_error(described_class::Invalid)
    end
  end

  %w[help_docs help_items].each do |name|
    it "requires #{name}" do
      data['collections'].delete(name)
      expect { load_dump }.to raise_error(described_class::Invalid)
    end

    [nil, [], {}].each do |entries|
      it "rejects empty/missing/invalid #{name} points #{entries.inspect}" do
        data['collections'][name]['points'] = entries
        expect { load_dump }.to raise_error(described_class::Invalid)
      end
    end

    it "rejects duplicate IDs in #{name}" do
      data['collections'][name]['points'] *= 2
      expect { load_dump }.to raise_error(described_class::Invalid, /Duplicate ID/)
    end

    [nil, true, 'false', 0].each do |flag|
      it "rejects non-public #{name} point #{flag.inspect}" do
        data['collections'][name]['points'][0]['payload']['is_internal'] = flag
        expect { load_dump }.to raise_error(described_class::Invalid, /public/)
      end
    end

    [nil, [], { 'other' => [0.1] * 768 }, { 'content' => [0.1] * 767 },
     { 'content' => [0.1] * 767 + ['1'] }, { 'content' => [0.1] * 767 + [nil] },
     { 'content' => [0.1] * 767 + [true] }, { 'content' => [0.1] * 767 + [1e100] },
     { 'content' => [[0.1] * 768] }].each_with_index do |vector, index|
      it "rejects invalid #{name} vector case #{index}" do
        data['collections'][name]['points'][0]['vector'] = vector
        expect { load_dump }.to raise_error(described_class::Invalid, /vector/)
      end
    end
  end

  %w[library_summaries pdf_docs arbitrary].each do |name|
    it "rejects extra collection #{name}" do
      data['collections'][name] = { 'points' => [point] }
      expect { load_dump }.to raise_error(described_class::Invalid, /Exactly/)
    end
  end

  [nil, '1', 2].each do |parent|
    it "rejects missing/untyped doc reference #{parent.inspect}" do
      data['collections']['help_items']['points'][0]['payload']['doc_id'] = parent
      expect { load_dump }.to raise_error(described_class::Invalid, /Missing document/)
    end
  end

  it 'checks the last vector, not only a sample of the dump' do
    data['collections']['help_items']['points'] << point.merge('id' => 2, 'vector' => { 'content' => [0] })
    expect { load_dump }.to raise_error(described_class::Invalid, /dimension/)
  end

  it 'rejects a JSON number that overflows to infinity' do
    File.write(@path, JSON.generate(data).sub('0.1', '1e999'))
    expect { described_class.new(@path) }.to raise_error(described_class::Invalid, /number/)
  end

  [-1, 2**64, '1', 1.5, nil].each do |id|
    it "rejects invalid point ID #{id.inspect}" do
      data['collections']['help_docs']['points'][0]['id'] = id
      expect { load_dump }.to raise_error(described_class::Invalid, /Invalid ID/)
    end
  end

  it 'validates the shipped public dump' do
    path = File.expand_path('../../../help_data/help_db.json', __dir__)
    expect { described_class.new(path) }.not_to raise_error
  end
end
