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

    it 'is true ONLY for ElevenLabs v3 (Flash v2.5 and Multilingual v2 do not interpret tags)' do
      expect(described_class.tag_aware?('elevenlabs-v3')).to be true
      expect(described_class.tag_aware?('eleven_v3')).to be true

      %w[elevenlabs elevenlabs-flash elevenlabs-multilingual eleven_flash_v2_5 eleven_multilingual_v2].each do |p|
        expect(described_class.tag_aware?(p)).to be(false), "expected #{p} to NOT be tag-aware"
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
      # openai-tts-4o is now the instruction-meta family (returns a
      # different kind of addendum). The plain OpenAI TTS models and
      # unknown providers still have no addendum.
      expect(described_class.prompt_addendum_for('openai-tts')).to be_nil
      expect(described_class.prompt_addendum_for('openai-tts-hd')).to be_nil
      expect(described_class.prompt_addendum_for(nil)).to be_nil
    end

    context 'for OpenAI instruction-mode (openai-tts-4o)' do
      it 'returns the sentinel-prefix variant by default (non-Monadic app)' do
        addendum = described_class.prompt_addendum_for('openai-tts-4o')
        expect(addendum).to include('<<TTS:')
        expect(addendum).to include('>>')
        expect(addendum).to include('Voice:')
        expect(addendum).to include('Tone:')
      end

      it 'returns the JSON-sibling variant when app_is_monadic: true' do
        addendum = described_class.prompt_addendum_for('openai-tts-4o', app_is_monadic: true)
        expect(addendum).to include('tts_instructions')
        expect(addendum).to include('"message"')
        expect(addendum).not_to include('<<TTS:')
      end

      # Both variants must teach the LLM to escalate directive intensity
      # to match reply intensity. Without this guidance the LLM defaults to
      # mild adjectives ("warm and playful") even for dramatic content,
      # which the TTS engine interprets as only slight variation.
      it 'includes intensity-matching guidance in both variants' do
        [
          described_class.prompt_addendum_for('openai-tts-4o'),
          described_class.prompt_addendum_for('openai-tts-4o', app_is_monadic: true)
        ].each do |addendum|
          expect(addendum).to match(/match.{0,30}intensity/i)
          expect(addendum).to include('visceral')
          # A selection of the recommended body-state verbs.
          expect(addendum).to include('breathless')
          expect(addendum).to include('gasping')
          expect(addendum).to include('trembling')
        end
      end

      it 'includes a dramatic-amusement example in the sentinel variant' do
        addendum = described_class.prompt_addendum_for('openai-tts-4o')
        expect(addendum).to include('strong amusement')
        expect(addendum).to match(/breathless.{0,60}laughter/i)
      end

      it 'includes a dramatic-amusement example in the JSON variant' do
        addendum = described_class.prompt_addendum_for('openai-tts-4o', app_is_monadic: true)
        expect(addendum).to include('strong amusement')
        expect(addendum).to match(/breathless.{0,60}laughter/i)
      end
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

      # Hybrid addendum — Gemini accepts both inline tags and a leading
      # `<<TTS:...>>` directive block (per Google's speech-generation docs).
      it 'teaches both inline markers AND the sentinel directive block' do
        expect(addendum).to match(/<<TTS:/)
        expect(addendum).to include('Voice:')
        expect(addendum).to include('Tone:')
        expect(addendum).to include('Pacing:')
      end

      it 'includes intensity-matching guidance (visceral body-state verbs)' do
        expect(addendum).to match(/match.{0,30}intensity/i)
        expect(addendum).to include('breathless')
        expect(addendum).to include('gasping')
      end

      it 'permits the LLM to use markers, directive, both, or neither per turn' do
        expect(addendum).to match(/markers only.{0,80}both.{0,40}neither/im)
      end

      it 'applies to all Gemini TTS provider dropdown values' do
        %w[gemini gemini-flash gemini-pro].each do |p|
          a = described_class.prompt_addendum_for(p)
          expect(a).to match(/<<TTS:/), "expected #{p} to receive hybrid addendum"
          expect(a).to include('[whispers]')
        end
      end
    end
  end

  describe '.instruction_capable?' do
    it 'is true for OpenAI gpt-4o-mini-tts (out-of-band instructions)' do
      expect(described_class.instruction_capable?('openai-tts-4o')).to be true
    end

    it 'is true for Gemini TTS (in-band directive prefix)' do
      %w[gemini gemini-flash gemini-pro].each do |p|
        expect(described_class.instruction_capable?(p)).to be(true), "expected #{p} to be instruction_capable"
      end
    end

    it 'is false for OpenAI plain TTS (tts-1 / tts-1-hd)' do
      expect(described_class.instruction_capable?('openai-tts')).to be false
      expect(described_class.instruction_capable?('openai-tts-hd')).to be false
    end

    it 'is false for tag-only families (xAI, ElevenLabs v3)' do
      expect(described_class.instruction_capable?('grok')).to be false
      expect(described_class.instruction_capable?('elevenlabs-v3')).to be false
    end

    it 'is nil-safe' do
      expect(described_class.instruction_capable?(nil)).to be false
      expect(described_class.instruction_capable?('')).to be false
    end
  end
end
