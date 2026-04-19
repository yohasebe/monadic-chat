# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'VoiceChatGrok audio fixation settings' do
  before(:all) do
    TestAppLoader.load_all_apps
  end

  let(:app) { APPS['Voice Chat (xAI Grok)'] || APPS.values.find { |a| a.settings['app_name'].to_s == 'VoiceChatGrok' } }

  it 'is registered in APPS' do
    expect(app).not_to be_nil
  end

  it 'fixes the TTS provider to xAI' do
    expect(app.settings['tts_provider']).to eq('xai')
  end

  it 'fixes the default TTS voice to eve' do
    expect(app.settings['tts_voice']).to eq('eve')
  end

  it 'fixes the STT provider to xAI' do
    expect(app.settings['stt_provider']).to eq('xai')
  end

  it 'fixes the STT model to xai-stt' do
    expect(app.settings['stt_model']).to eq('xai-stt')
  end

  it 'keeps unrelated Voice Chat variants free of audio fixation keys' do
    openai_app = APPS.values.find { |a| a.settings['app_name'].to_s == 'VoiceChatOpenAI' }
    expect(openai_app).not_to be_nil
    expect(openai_app.settings['tts_provider']).to be_nil
    expect(openai_app.settings['stt_provider']).to be_nil
  end

  describe 'system prompt TTS markers guidance' do
    let(:prompt) { app.settings['initial_prompt'].to_s }

    it 'lists inline markers so the model knows the vocabulary' do
      expect(prompt).to include('[laugh]')
      expect(prompt).to include('[pause]')
      expect(prompt).to include('[sigh]')
    end

    it 'lists wrapping markers' do
      expect(prompt).to include('<whisper>')
      expect(prompt).to include('<soft>')
      expect(prompt).to include('<sing>')
    end

    it 'includes good-example phrasings that model the natural insertion style' do
      expect(prompt).to match(/Good examples/i)
    end

    it 'prohibits meta-reference to the markers' do
      expect(prompt).to match(/never name, quote, describe, explain, or list the markers/i)
    end

    it 'preserves the original brevity guideline' do
      expect(prompt).to include('under 50 words')
    end
  end
end
