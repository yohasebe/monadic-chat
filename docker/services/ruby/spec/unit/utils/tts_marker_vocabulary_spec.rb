# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/tts_marker_vocabulary'

RSpec.describe Monadic::Utils::TtsMarkerVocabulary do
  describe '.family_for' do
    it 'delegates to TtsTextProcessors so normalisation stays single-source' do
      expect(described_class.family_for('grok')).to eq('xai')
      expect(described_class.family_for('gemini-flash')).to eq('gemini')
    end
  end

  describe '.tag_aware?' do
    it 'is true for xAI / Grok' do
      expect(described_class.tag_aware?('grok')).to be true
      expect(described_class.tag_aware?('xai-tts')).to be true
    end

    it 'is true for ElevenLabs variants' do
      %w[elevenlabs elevenlabs-flash elevenlabs-multilingual elevenlabs-v3].each do |p|
        expect(described_class.tag_aware?(p)).to be(true), "expected #{p} to be tag-aware"
      end
    end

    it 'is true for Gemini TTS variants' do
      %w[gemini gemini-flash gemini-pro].each do |p|
        expect(described_class.tag_aware?(p)).to be(true), "expected #{p} to be tag-aware"
      end
    end

    it 'is false for providers without a vocabulary' do
      expect(described_class.tag_aware?('openai-tts-4o')).to be false
      expect(described_class.tag_aware?('mistral')).to be false
      expect(described_class.tag_aware?('webspeech')).to be false
    end

    it 'is nil-safe' do
      expect(described_class.tag_aware?(nil)).to be false
      expect(described_class.tag_aware?('')).to be false
    end
  end

  describe '.vocabulary_for' do
    it 'returns the inline / wrapping / examples tables for xAI' do
      vocab = described_class.vocabulary_for('grok')
      expect(vocab[:inline]).to include('laugh', 'pause', 'long-pause', 'sigh')
      expect(vocab[:wrapping]).to include('whisper', 'soft', 'loud')
      expect(vocab[:examples]).to be_an(Array)
      expect(vocab[:examples].size).to be >= 2
    end

    it 'returns nil for unregistered providers' do
      expect(described_class.vocabulary_for('openai-tts-4o')).to be_nil
    end
  end

  describe '.prompt_addendum_for' do
    let(:addendum) { described_class.prompt_addendum_for('grok') }

    it 'returns a non-empty string for tag-aware providers' do
      expect(addendum).to be_a(String)
      expect(addendum).not_to be_empty
    end

    it 'lists the inline marker vocabulary' do
      expect(addendum).to include('[laugh]')
      expect(addendum).to include('[pause]')
      expect(addendum).to include('[sigh]')
    end

    it 'lists the wrapping marker vocabulary' do
      expect(addendum).to include('<whisper>...</whisper>')
      expect(addendum).to include('<soft>...</soft>')
    end

    it 'includes good-example phrasings' do
      expect(addendum).to include('Good examples:')
      expect(addendum).to match(/\[laugh\]/)
    end

    it 'prohibits meta-reference to the markers' do
      expect(addendum).to match(/never name, quote, describe, explain, or list the markers/i)
    end

    it 'instructs the model not to open a conversation with a marker' do
      expect(addendum).to match(/never open a conversation with a marker/i)
    end

    it 'returns nil for unregistered providers' do
      expect(described_class.prompt_addendum_for('openai-tts-4o')).to be_nil
      expect(described_class.prompt_addendum_for(nil)).to be_nil
    end

    context 'for ElevenLabs' do
      let(:addendum) { described_class.prompt_addendum_for('elevenlabs-v3') }

      it 'lists the curated single-word tag set' do
        expect(addendum).to include('[laughs]')
        expect(addendum).to include('[whispers]')
        expect(addendum).to include('[excited]')
      end

      it 'omits the wrapping markers section because ElevenLabs has none' do
        expect(addendum).not_to include('Wrapping markers')
      end
    end

    context 'for Gemini' do
      let(:addendum) { described_class.prompt_addendum_for('gemini-flash') }

      it 'lists Gemini fixed tags only (not free-form)' do
        expect(addendum).to include('[amazed]')
        expect(addendum).to include('[mischievously]')
        expect(addendum).to include('[trembling]')
      end

      it 'omits the wrapping markers section' do
        expect(addendum).not_to include('Wrapping markers')
      end
    end
  end
end
