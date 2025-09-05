# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/real_audio_test_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Voice Pipeline (TTS -> STT)', :api, :media do
  include RealAudioTestHelper
  include ProviderMatrixHelper

  it 'generates audio with TTS and transcribes it with STT (openai/elevenlabs/webspeech)' do
    require_run_media!
    text = 'Hello from the voice pipeline test'
    %w[openai elevenlabs webspeech].each do |tts|
      audio_file = generate_real_audio_file(text, provider: tts, voice: (tts == 'elevenlabs' ? 'alloy' : 'alloy'))
      expect(File.exist?(audio_file)).to be true
      transcription = transcribe_audio_file(audio_file, model: ENV['STT_MODEL'] || 'whisper-1', lang: 'en')
      expect(transcription).to be_a(String)
      expect(transcription.strip.length).to be > 0
      File.delete(audio_file) if File.exist?(audio_file)
    end
  end
end
