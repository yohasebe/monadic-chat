# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/monadic/adapters/stream_records'

RSpec.describe StreamRecords do
  def read(format, chunks)
    reader = described_class.new(format)
    out = []
    chunks.each { |c| reader.feed(c) { |*rec| out << rec } }
    reader.finish { |*rec| out << rec }
    out
  end

  # Every way of cutting the bytes in two gives the same records.
  def each_split(bytes)
    (0..bytes.bytesize).each do |i|
      yield [bytes.byteslice(0, i), bytes.byteslice(i, bytes.bytesize - i)]
    end
  end

  describe ':ndjson' do
    let(:stream) { %({"content":"日本語"}\n{"content":"tail"}\n).b }

    it 'gives each line whatever the chunks' do
      each_split(stream) do |chunks|
        expect(read(:ndjson, chunks)).to eq([[%({"content":"日本語"})], [%({"content":"tail"})]])
      end
    end

    it 'gives several records of one chunk' do
      expect(read(:ndjson, [stream]).size).to eq(2)
    end

    it 'gives the last record without a newline and skips blank lines' do
      expect(read(:ndjson, ["\n{\"a\":1}\n\n{\"b\":2}"])).to eq([['{"a":1}'], ['{"b":2}']])
    end
  end

  describe ':sse' do
    let(:stream) do
      "event: message_start\r\ndata: {\"t\":\"Grüß\"}\r\n\r\n: keep-alive\n" \
        "data: {\"t\":\"日本\"}\n\ndata: [DONE]\n\n".b
    end

    it 'gives the data of each data line with its event, whatever the chunks' do
      expected = [['{"t":"Grüß"}', 'message_start'], ['{"t":"日本"}', nil], ['[DONE]', nil]]
      each_split(stream) do |chunks|
        expect(read(:sse, chunks)).to eq(expected)
      end
    end

    it 'gives a data line cut just after a closing brace only once it is whole' do
      line = %(data: {"choices":[{"delta":{"content":"hello"}}]}\n)
      cut = line.index('}') + 1
      expect(read(:sse, [line[0, cut], line[cut..]])).to eq([[line.chomp.delete_prefix('data: '), nil]])
    end

    it 'gives the last data line without a newline' do
      expect(read(:sse, ['data: {"x":1}'])).to eq([['{"x":1}', nil]])
    end
  end

  it 'refuses an unknown format' do
    expect { described_class.new(:json) }.to raise_error(ArgumentError)
  end
end
