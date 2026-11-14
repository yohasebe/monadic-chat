# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/tts_instruction_extractor'

RSpec.describe Monadic::Utils::TtsInstructionExtractor do
  # ---- Extraction ------------------------------------------------------------

  describe '.extract' do
    let(:valid_sentinel) do
      "<<TTS:Voice: warm, calm.\nTone: sincere.\nPacing: steady.>>\n\nI'm sorry about that."
    end

    it 'peels the leading <<TTS:...>> block and returns the cleaned message' do
      message, instructions = described_class.extract(valid_sentinel)
      expect(message).to eq("I'm sorry about that.")
      expect(instructions).to include('Voice: warm, calm.')
      expect(instructions).to include('Tone: sincere.')
      expect(instructions).to include('Pacing: steady.')
    end

    it 'returns [text, nil] when there is no sentinel at the start' do
      expect(described_class.extract("Hello, how can I help?")).to eq(["Hello, how can I help?", nil])
    end

    it 'is nil- and empty-safe' do
      expect(described_class.extract(nil)).to eq([nil, nil])
      expect(described_class.extract('')).to eq(['', nil])
    end

    it 'ignores a sentinel that does not start at the beginning' do
      text = "Hello! <<TTS:Voice: warm>> is not a directive here."
      expect(described_class.extract(text)).to eq([text, nil])
    end

    it 'tolerates leading whitespace before the sentinel' do
      text = "   <<TTS:Voice: calm.>>\nReply."
      message, instructions = described_class.extract(text)
      expect(message).to eq('Reply.')
      expect(instructions).to eq('Voice: calm.')
    end

    it 'returns [cleaned, nil] when the directive block is empty' do
      text = "<<TTS:>>Just a reply."
      message, instructions = described_class.extract(text)
      expect(message).to eq('Just a reply.')
      expect(instructions).to be_nil
    end

    it 'uses the first >> non-greedily (does not over-consume)' do
      text = "<<TTS:Voice: calm.>>Hello >> world"
      message, instructions = described_class.extract(text)
      expect(message).to eq('Hello >> world')
      expect(instructions).to eq('Voice: calm.')
    end

    it 'handles multi-line directive bodies' do
      text = "<<TTS:Voice: warm.\nTone: gentle.\nPacing: slow.>>\nReply"
      _, instructions = described_class.extract(text)
      expect(instructions.lines.size).to eq(3)
    end
  end

  # ---- History strip ---------------------------------------------------------

  describe '.strip_from_history' do
    it 'removes a leading <<TTS:...>> block' do
      input = "<<TTS:Voice: calm.>>\nReply body"
      expect(described_class.strip_from_history(input)).to eq('Reply body')
    end

    it 'returns the input unchanged when sentinel is absent' do
      expect(described_class.strip_from_history('Hello')).to eq('Hello')
    end

    it 'does not touch a sentinel in the middle of the text' do
      input = 'Hello <<TTS:x>> world'
      expect(described_class.strip_from_history(input)).to eq(input)
    end

    it 'is nil-safe' do
      expect(described_class.strip_from_history(nil)).to be_nil
    end
  end

  # ---- Streaming helpers -----------------------------------------------------

  describe '.possibly_sentinel_start?' do
    it 'is true for any prefix of "<<TTS:"' do
      %w[< << <<T <<TT <<TTS <<TTS: <<TTS:any].each do |prefix|
        expect(described_class.possibly_sentinel_start?(prefix)).to be(true), "expected true for '#{prefix}'"
      end
    end

    it 'is true for leading whitespace + partial sentinel' do
      expect(described_class.possibly_sentinel_start?(" <<")).to be(true)
      expect(described_class.possibly_sentinel_start?("  <<TTS:")).to be(true)
    end

    it 'is false for text that cannot grow into a sentinel' do
      expect(described_class.possibly_sentinel_start?('Hello')).to be(false)
      expect(described_class.possibly_sentinel_start?('><')).to be(false)
      expect(described_class.possibly_sentinel_start?('<!')).to be(false)
    end

    it 'is true for an empty buffer (could still grow into anything)' do
      expect(described_class.possibly_sentinel_start?('')).to be(true)
    end
  end

  describe '.try_consume_sentinel' do
    it 'returns nil when sentinel is not yet complete' do
      expect(described_class.try_consume_sentinel('<<TTS:Voice: calm.')).to be_nil
    end

    it 'returns [instructions, remainder] when sentinel is complete' do
      result = described_class.try_consume_sentinel('<<TTS:Voice: calm.>>Hello')
      expect(result).to eq(['Voice: calm.', 'Hello'])
    end

    it 'returns nil for empty/nil input' do
      expect(described_class.try_consume_sentinel(nil)).to be_nil
      expect(described_class.try_consume_sentinel('')).to be_nil
    end

    it 'returns nil when the buffer starts with something else' do
      expect(described_class.try_consume_sentinel('Hello <<TTS:...>>')).to be_nil
    end

    it 'tolerates leading whitespace before the sentinel' do
      result = described_class.try_consume_sentinel("  <<TTS:Voice: calm.>>Rest")
      expect(result).to eq(['Voice: calm.', 'Rest'])
    end
  end
end
