# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/real_audio_test_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Voice Pipeline (TTS -> STT)', :api, :media do
  include RealAudioTestHelper
  include ProviderMatrixHelper

  # Note: webspeech is a browser-side Web Speech API - not testable from backend

  it 'generates audio with OpenAI TTS and transcribes with STT' do
    skip 'RUN_API is not enabled' unless ENV['RUN_API'] == 'true'

    text = 'Hello from the voice pipeline test'
    audio_file = generate_real_audio_file(text, provider: 'openai', voice: 'alloy')
    expect(File.exist?(audio_file)).to be true

    transcription = transcribe_audio_file(audio_file, model: ENV['STT_MODEL'] || 'whisper-1', lang: 'en')
    expect(transcription).to be_a(String)
    expect(transcription.strip.length).to be > 0
  ensure
    File.delete(audio_file) if audio_file && File.exist?(audio_file)
  end

  it 'generates audio with ElevenLabs TTS and transcribes with STT' do
    skip 'RUN_API is not enabled' unless ENV['RUN_API'] == 'true'
    skip 'ELEVENLABS_API_KEY is not set' unless elevenlabs_api_key_available?

    text = 'Hello from the voice pipeline test'
    # ElevenLabs requires a proper voice ID - use 'Rachel' default voice
    audio_file = generate_real_audio_file(text, provider: 'elevenlabs', voice: '21m00Tcm4TlvDq8ikWAM')
    expect(File.exist?(audio_file)).to be true

    transcription = transcribe_audio_file(audio_file, model: ENV['STT_MODEL'] || 'whisper-1', lang: 'en')
    expect(transcription).to be_a(String)
    expect(transcription.strip.length).to be > 0
  ensure
    File.delete(audio_file) if audio_file && File.exist?(audio_file)
  end

  private

  def elevenlabs_api_key_available?
    # Check config file first
    config_paths = ['/monadic/config/env', File.expand_path('~/monadic/config/env')]
    config_paths.each do |path|
      next unless File.exist?(path)
      content = File.read(path)
      if content.include?('ELEVENLABS_API_KEY=') && !content[/ELEVENLABS_API_KEY=(.*)/, 1].to_s.strip.empty?
        return true
      end
    end
    # Fallback to ENV
    ENV['ELEVENLABS_API_KEY'] && !ENV['ELEVENLABS_API_KEY'].empty?
  end
end
