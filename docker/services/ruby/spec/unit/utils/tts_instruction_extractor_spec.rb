# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../lib/monadic/utils/tts_instruction_extractor'

RSpec.describe Monadic::Utils::TtsInstructionExtractor do
  # ---- Sentinel path (non-Monadic apps) --------------------------------------

  describe '.extract_sentinel' do
    let(:valid_sentinel) do
      "<<TTS:Voice: warm, calm.\nTone: sincere.\nPacing: steady.>>\n\nI'm sorry about that."
    end

    it 'peels the leading <<TTS:...>> block and returns the cleaned message' do
      message, instructions = described_class.extract_sentinel(valid_sentinel)
      expect(message).to eq("I'm sorry about that.")
      expect(instructions).to include('Voice: warm, calm.')
      expect(instructions).to include('Tone: sincere.')
      expect(instructions).to include('Pacing: steady.')
    end

    it 'returns [text, nil] when there is no sentinel at the start' do
      expect(described_class.extract_sentinel("Hello, how can I help?")).to eq(["Hello, how can I help?", nil])
    end

    it 'is nil- and empty-safe' do
      expect(described_class.extract_sentinel(nil)).to eq([nil, nil])
      expect(described_class.extract_sentinel('')).to eq(['', nil])
    end

    it 'ignores a sentinel that does not start at the beginning' do
      text = "Hello! <<TTS:Voice: warm>> is not a directive here."
      expect(described_class.extract_sentinel(text)).to eq([text, nil])
    end

    it 'tolerates leading whitespace before the sentinel' do
      text = "   <<TTS:Voice: calm.>>\nReply."
      message, instructions = described_class.extract_sentinel(text)
      expect(message).to eq('Reply.')
      expect(instructions).to eq('Voice: calm.')
    end

    it 'returns [cleaned, nil] when the directive block is empty' do
      text = "<<TTS:>>Just a reply."
      message, instructions = described_class.extract_sentinel(text)
      expect(message).to eq('Just a reply.')
      expect(instructions).to be_nil
    end

    it 'uses the first >> non-greedily (does not over-consume)' do
      text = "<<TTS:Voice: calm.>>Hello >> world"
      message, instructions = described_class.extract_sentinel(text)
      expect(message).to eq('Hello >> world')
      expect(instructions).to eq('Voice: calm.')
    end

    it 'handles multi-line directive bodies' do
      text = "<<TTS:Voice: warm.\nTone: gentle.\nPacing: slow.>>\nReply"
      _, instructions = described_class.extract_sentinel(text)
      expect(instructions.lines.size).to eq(3)
    end
  end

  # ---- JSON path (Monadic apps) ----------------------------------------------

  describe '.extract_json' do
    it 'pulls message and tts_instructions from a valid Monadic JSON' do
      text = {
        'message' => 'Hello!',
        'context' => { 'mood' => 'happy' },
        'tts_instructions' => "Voice: warm.\nTone: friendly."
      }.to_json

      message, instructions = described_class.extract_json(text)
      expect(message).to eq('Hello!')
      expect(instructions).to eq("Voice: warm.\nTone: friendly.")
    end

    it 'returns [text, nil] when tts_instructions is missing' do
      text = { 'message' => 'Hello!', 'context' => {} }.to_json
      message, instructions = described_class.extract_json(text)
      expect(message).to eq('Hello!')
      expect(instructions).to be_nil
    end

    it 'returns [text, nil] when tts_instructions is an empty string' do
      text = { 'message' => 'Hello!', 'tts_instructions' => '' }.to_json
      _, instructions = described_class.extract_json(text)
      expect(instructions).to be_nil
    end

    it 'returns [raw, nil] when message field is missing or non-string' do
      text = { 'tts_instructions' => 'Voice: calm.' }.to_json
      expect(described_class.extract_json(text)).to eq([text, nil])

      text2 = { 'message' => 42, 'tts_instructions' => 'Voice: calm.' }.to_json
      expect(described_class.extract_json(text2)).to eq([text2, nil])
    end

    it 'returns [raw, nil] when JSON is malformed' do
      text = "{message: not really JSON"
      expect(described_class.extract_json(text)).to eq([text, nil])
    end

    it 'returns [raw, nil] when JSON is a scalar or array, not a Hash' do
      expect(described_class.extract_json('"just a string"')).to eq(['"just a string"', nil])
      expect(described_class.extract_json('[1, 2, 3]')).to eq(['[1, 2, 3]', nil])
    end

    it 'is nil- and empty-safe' do
      expect(described_class.extract_json(nil)).to eq([nil, nil])
      expect(described_class.extract_json('')).to eq(['', nil])
    end

    it 'rejects non-string tts_instructions gracefully' do
      text = { 'message' => 'Hello!', 'tts_instructions' => { nested: 'wrong' } }.to_json
      message, instructions = described_class.extract_json(text)
      expect(message).to eq('Hello!')
      expect(instructions).to be_nil
    end
  end

  # ---- Dispatcher ------------------------------------------------------------

  describe '.extract' do
    it 'routes to extract_json when app_is_monadic: true' do
      text = { 'message' => 'Hi', 'tts_instructions' => 'Voice: calm.' }.to_json
      expect(described_class.extract(text, app_is_monadic: true))
        .to eq(['Hi', 'Voice: calm.'])
    end

    it 'routes to extract_sentinel when app_is_monadic: false' do
      text = "<<TTS:Voice: calm.>>\nHi"
      expect(described_class.extract(text, app_is_monadic: false))
        .to eq(['Hi', 'Voice: calm.'])
    end

    it 'is nil-safe on both paths' do
      expect(described_class.extract(nil, app_is_monadic: true)).to eq([nil, nil])
      expect(described_class.extract(nil, app_is_monadic: false)).to eq([nil, nil])
    end
  end

  # ---- History strip ---------------------------------------------------------

  describe '.strip_from_history_json' do
    it 'removes tts_instructions from a valid object' do
      input = {
        'message' => 'Hello',
        'context' => { 'k' => 'v' },
        'tts_instructions' => 'Voice: calm.'
      }.to_json
      stripped = described_class.strip_from_history_json(input)
      parsed = JSON.parse(stripped)
      expect(parsed).not_to have_key('tts_instructions')
      expect(parsed['message']).to eq('Hello')
      expect(parsed['context']).to eq({ 'k' => 'v' })
    end

    it 'returns the input unchanged when tts_instructions is absent' do
      input = { 'message' => 'Hello', 'context' => {} }.to_json
      expect(described_class.strip_from_history_json(input)).to eq(input)
    end

    it 'returns the input unchanged when input is not valid JSON' do
      expect(described_class.strip_from_history_json("not JSON")).to eq("not JSON")
    end

    it 'returns the input unchanged for non-Hash JSON' do
      expect(described_class.strip_from_history_json('[1,2,3]')).to eq('[1,2,3]')
    end

    it 'is nil-safe' do
      expect(described_class.strip_from_history_json(nil)).to be_nil
    end
  end

  describe '.strip_from_history_sentinel' do
    it 'removes a leading <<TTS:...>> block' do
      input = "<<TTS:Voice: calm.>>\nReply body"
      expect(described_class.strip_from_history_sentinel(input)).to eq('Reply body')
    end

    it 'returns the input unchanged when sentinel is absent' do
      expect(described_class.strip_from_history_sentinel('Hello')).to eq('Hello')
    end

    it 'does not touch a sentinel in the middle of the text' do
      input = 'Hello <<TTS:x>> world'
      expect(described_class.strip_from_history_sentinel(input)).to eq(input)
    end

    it 'is nil-safe' do
      expect(described_class.strip_from_history_sentinel(nil)).to be_nil
    end
  end

  describe '.strip_from_history' do
    it 'dispatches to JSON when app_is_monadic' do
      input = { 'message' => 'Hi', 'tts_instructions' => 'V: calm.' }.to_json
      parsed = JSON.parse(described_class.strip_from_history(input, app_is_monadic: true))
      expect(parsed).not_to have_key('tts_instructions')
    end

    it 'dispatches to sentinel when not app_is_monadic' do
      input = "<<TTS:V: calm.>>\nHi"
      expect(described_class.strip_from_history(input, app_is_monadic: false)).to eq('Hi')
    end

    it 'is nil-safe on both paths' do
      expect(described_class.strip_from_history(nil, app_is_monadic: true)).to be_nil
      expect(described_class.strip_from_history(nil, app_is_monadic: false)).to be_nil
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
