# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/tts_text_processors'

RSpec.describe Monadic::Utils::TtsTextProcessors do
  describe '.family_for' do
    it 'maps xAI provider strings to the xai family' do
      expect(described_class.family_for('grok')).to eq('xai')
      expect(described_class.family_for('xai-tts')).to eq('xai')
    end

    it 'maps ElevenLabs variants to the elevenlabs family' do
      %w[elevenlabs elevenlabs-flash elevenlabs-multilingual elevenlabs-v3].each do |p|
        expect(described_class.family_for(p)).to eq('elevenlabs')
      end
    end

    it 'maps OpenAI TTS variants to the openai family' do
      %w[openai-tts openai-tts-4o openai-tts-hd tts-1 tts-1-hd].each do |p|
        expect(described_class.family_for(p)).to eq('openai')
      end
    end

    it 'maps Gemini TTS variants to the gemini family' do
      %w[gemini gemini-flash gemini-pro].each do |p|
        expect(described_class.family_for(p)).to eq('gemini')
      end
    end

    it 'maps Mistral / Voxtral to the mistral family' do
      %w[mistral voxtral-mini-tts-2603].each do |p|
        expect(described_class.family_for(p)).to eq('mistral')
      end
    end

    it 'is case-insensitive and nil-safe' do
      expect(described_class.family_for('GROK')).to eq('xai')
      expect(described_class.family_for(nil)).to eq('')
    end
  end

  describe '.pre_send' do
    it 'is the identity function for unregistered providers' do
      expect(described_class.pre_send('openai-tts-4o', 'hello world')).to eq('hello world')
      expect(described_class.pre_send('gemini', 'こんにちは')).to eq('こんにちは')
    end

    it 'returns the original text for nil / empty input without raising' do
      expect(described_class.pre_send('grok', nil)).to be_nil
      expect(described_class.pre_send('grok', '')).to eq('')
    end
  end

  describe '.sanitize_for_display' do
    context 'with the xai family' do
      it 'strips inline markers' do
        input = 'Oh wow [laugh] that is surprising [pause] I think.'
        expect(described_class.sanitize_for_display('grok', input))
          .to eq('Oh wow that is surprising I think.')
      end

      it 'strips wrapping tags while keeping their inner text' do
        input = '<whisper>Do not tell anyone.</whisper> Okay?'
        expect(described_class.sanitize_for_display('grok', input))
          .to eq('Do not tell anyone. Okay?')
      end

      it 'handles the complete marker vocabulary' do
        input = '[long-pause][inhale][exhale][click][smack][sigh][cry] text ' \
                '<loud>x</loud><soft>y</soft><high>z</high><low>w</low>' \
                '<fast>a</fast><slow>b</slow><sing>c</sing>'
        out = described_class.sanitize_for_display('grok', input)
        expect(out).not_to match(/\[[a-z-]+\]/)
        expect(out).not_to match(%r{</?[a-z]+>})
        expect(out).to include('x', 'y', 'z', 'w', 'a', 'b', 'c', 'text')
      end

      it 'does not punch holes before punctuation' do
        expect(described_class.sanitize_for_display('grok', 'Wait [pause] , really?'))
          .to eq('Wait, really?')
      end
    end

    it 'is the identity function for providers without a registered sanitizer' do
      input = '<whisper>kept as-is</whisper>'
      expect(described_class.sanitize_for_display('openai-tts-4o', input)).to eq(input)
      expect(described_class.sanitize_for_display('gemini', input)).to eq(input)
    end

    it 'is nil-safe' do
      expect(described_class.sanitize_for_display('grok', nil)).to be_nil
      expect(described_class.sanitize_for_display('grok', '')).to eq('')
    end
  end

  describe '.tag_aware?' do
    it 'reports true for providers with a display sanitizer' do
      expect(described_class.tag_aware?('grok')).to be true
    end

    it 'reports false for providers without one' do
      expect(described_class.tag_aware?('openai-tts-4o')).to be false
      expect(described_class.tag_aware?('gemini')).to be false
    end
  end
end
