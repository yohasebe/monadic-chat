# frozen_string_literal: true

require 'spec_helper'
require_relative 'lib/runner'

# Runs unconditionally: pure formatting, no network. The report is where the
# "100% means silence, not a wrong answer" reading either survives or gets
# lost, so the distinction is pinned here rather than left to a footnote.
RSpec.describe SttNoiseBenchmark::Runner::Report do
  def row(engine:, condition:, wer:, words:, error: nil)
    { engine: engine, condition: condition, wer: wer, hypothesis_words: words, error: error }
  end

  let(:result) do
    {
      rows: [
        row(engine: 'ref', condition: 'clean', wer: 0.0, words: 24),
        row(engine: 'ref', condition: 'babble_0dB', wer: 0.0, words: 24),
        row(engine: 'silent', condition: 'clean', wer: 0.0, words: 24),
        row(engine: 'silent', condition: 'babble_0dB', wer: 1.0, words: 0),
        row(engine: 'fabricator', condition: 'clean', wer: 0.0, words: 24),
        row(engine: 'fabricator', condition: 'babble_0dB', wer: 1.0, words: 26)
      ]
    }
  end

  it 'renders one column per engine and one row per condition' do
    table = described_class.to_markdown(result)

    expect(table).to include('| condition | ref | silent | fabricator |')
    expect(table).to include('| clean |')
    expect(table).to include('| babble_0dB |')
  end

  it 'shows silence and fabrication differently at the same WER' do
    table = described_class.to_markdown(result)
    babble_line = table.lines.find { |line| line.start_with?('| babble_0dB') }

    expect(babble_line).to include('100% (0w)')  # dropped everything
    expect(babble_line).to include('100% (26w)') # invented a fluent answer
  end

  it 'marks an errored engine without losing the rest of the table' do
    result[:rows] << row(engine: 'broken', condition: 'clean', wer: nil, words: nil,
                         error: 'Errno::ECONNREFUSED: connection refused')

    table = described_class.to_markdown(result)

    expect(table).to include('ERR (Errno')
    expect(table).to include('| ref |').or include('ref')
  end

  it 'uses an em dash for a combination that was never measured' do
    partial = { rows: [row(engine: 'a', condition: 'clean', wer: 0.0, words: 5),
                       row(engine: 'b', condition: 'white_0dB', wer: 0.5, words: 5)] }

    table = described_class.to_markdown(partial)

    expect(table).to include('—')
  end

  it 'explains how to read the cells' do
    expect(described_class.to_markdown(result)).to include('fabrication')
  end
end
