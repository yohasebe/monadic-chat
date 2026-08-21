# frozen_string_literal: true

require 'spec_helper'
require_relative 'lib/wer'

# Runs unconditionally: no network, no keys. The scoring logic is the part of
# the benchmark that has to be trustworthy for any published number, so it is
# pinned in CI even though the measurement itself is opt-in.
RSpec.describe SttNoiseBenchmark::Wer do
  describe '.normalize' do
    it 'lowercases and drops punctuation' do
      expect(described_class.normalize('The Committee approved, finally!'))
        .to eq(%w[the committee approved finally])
    end

    it 'keeps apostrophes so contractions stay one word' do
      expect(described_class.normalize("don't stop")).to eq(["don't", 'stop'])
    end

    it 'collapses arbitrary whitespace' do
      expect(described_class.normalize("a\n  b\tc")).to eq(%w[a b c])
    end
  end

  describe '.rate' do
    it 'is zero for an exact match' do
      expect(described_class.rate('submit the assignment', 'Submit the assignment.')).to eq(0.0)
    end

    it 'counts a substitution' do
      expect(described_class.rate('a b c', 'a x c')).to be_within(1e-9).of(1.0 / 3)
    end

    it 'counts a deletion' do
      expect(described_class.rate('a b c', 'a c')).to be_within(1e-9).of(1.0 / 3)
    end

    it 'counts an insertion' do
      expect(described_class.rate('a b c', 'a b x c')).to be_within(1e-9).of(1.0 / 3)
    end

    it 'reports 1.0 when nothing usable came back' do
      expect(described_class.rate('a b c', '')).to eq(1.0)
    end
  end

  describe '.analyze' do
    it 'separates omission from fabrication' do
      omitted = described_class.analyze('one two three four', 'one two')
      fabricated = described_class.analyze('one two three four', 'one two dear olivia to revise')

      expect(omitted[:deletions]).to eq(2)
      expect(omitted[:insertions]).to eq(0)

      expect(fabricated[:insertions]).to be > 0
      expect(fabricated[:hypothesis_words]).to be > fabricated[:reference_words]
    end

    it 'lets WER exceed 1.0 when the engine invents more than it drops' do
      result = described_class.analyze('one two', 'alpha beta gamma delta epsilon')
      expect(result[:wer]).to be > 1.0
    end

    it 'reports the reference and hypothesis lengths' do
      result = described_class.analyze('a b c', 'a b')
      expect(result[:reference_words]).to eq(3)
      expect(result[:hypothesis_words]).to eq(2)
    end

    it 'treats an empty reference with output as infinitely wrong' do
      expect(described_class.analyze('', 'something')[:wer]).to eq(Float::INFINITY)
    end

    it 'treats empty reference and empty output as no error' do
      expect(described_class.analyze('', '')[:wer]).to eq(0.0)
    end
  end

  # The published table reported "100% = no response, not a wrong answer".
  # That reading only holds if a total miss and a fluent wrong answer are
  # distinguishable in the output, so pin it.
  describe 'reporting invariant' do
    it 'a silent engine and a fabricating engine are distinguishable' do
      silent = described_class.analyze('one two three', '')
      fabricating = described_class.analyze('one two three', 'we hope to have a meaningful interaction')

      expect(silent[:hypothesis_words]).to eq(0)
      expect(fabricating[:hypothesis_words]).to be > 0
      expect(silent[:wer]).to eq(1.0)
    end
  end
end
