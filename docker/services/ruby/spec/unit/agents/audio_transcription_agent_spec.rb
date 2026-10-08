# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/monadic/agents/audio_transcription_agent'

RSpec.describe AudioTranscriptionAgent do
  let(:test_class) do
    Class.new do
      include AudioTranscriptionAgent

      attr_accessor :settings

      def initialize
        @settings = { "provider" => "openai" }
      end
    end
  end

  let(:agent) { test_class.new }

  around do |example|
    Dir.mktmpdir('analysis-shared-') do |directory|
      @data_dir = File.realpath(directory)
      example.run
    end
  end

  before do
    stub_const("CONFIG", {
      "OPENAI_API_KEY" => "test-openai-key",
      "GEMINI_API_KEY" => "test-gemini-key",
      "EXTRA_LOGGING" => nil
    })
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data_dir)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@data_dir)
    %w[audio.mp3 huge.mp3 audio..final.mp3 test.mp3].each do |name|
      File.binwrite(File.join(@data_dir, name), 'audio bytes')
    end
  end

  describe '#audio_transcription_agent' do
    context 'with valid audio file (OpenAI)' do
      before do
        allow(agent).to receive(:transcribe_openai).and_return("Hello world, this is the transcript.")
      end

      it 'returns transcript text' do
        result = agent.audio_transcription_agent(audio_path: File.join(@data_dir, "audio.mp3"))
        expect(result).to eq("Hello world, this is the transcript.")
      end

      it 'uses default model when none specified' do
        expected_model = Monadic::Utils::ModelSpec.default_audio_model("openai")
        agent.audio_transcription_agent(audio_path: File.join(@data_dir, "audio.mp3"))
        expect(agent).to have_received(:transcribe_openai).with(
          File.join(@data_dir, "audio.mp3"),
          expected_model,
          "test-openai-key",
          "text",
          nil
        )
      end

      it 'passes custom model when specified' do
        agent.audio_transcription_agent(audio_path: File.join(@data_dir, "audio.mp3"), model: "gpt-transcribe")
        expect(agent).to have_received(:transcribe_openai).with(
          File.join(@data_dir, "audio.mp3"),
          "gpt-transcribe",
          "test-openai-key",
          "text",
          nil
        )
      end

      it 'sends the successor when the requested model has been retired' do
        # whisper-1 retires on 2027-02-26. A selection saved before then still
        # arrives here, so the agent resolves it rather than passing on a name
        # the provider has dropped.
        agent.audio_transcription_agent(audio_path: File.join(@data_dir, "audio.mp3"), model: "whisper-1")
        expect(agent).to have_received(:transcribe_openai).with(
          File.join(@data_dir, "audio.mp3"),
          "gpt-transcribe",
          "test-openai-key",
          "text",
          nil
        )
      end
    end

    context 'with Gemini provider' do
      before do
        agent.settings["provider"] = "gemini"
        allow(agent).to receive(:transcribe_gemini).and_return("Gemini transcript")
      end

      it 'uses Gemini for Google provider' do
        result = agent.audio_transcription_agent(audio_path: File.join(@data_dir, "audio.mp3"))
        expect(result).to eq("Gemini transcript")
        expect(agent).to have_received(:transcribe_gemini)
      end
    end

    context 'with missing audio file' do
      it 'returns error for missing file' do
        result = agent.audio_transcription_agent(audio_path: "nonexistent.mp3")
        expect(result).to include("ERROR:")
        expect(result).to include("not found")
      end
    end

    context 'with oversized audio file' do
      before do
        File.truncate(File.join(@data_dir, 'huge.mp3'), 30 * 1024 * 1024)
      end

      it 'returns error for files exceeding 25MB' do
        result = agent.audio_transcription_agent(audio_path: File.join(@data_dir, "huge.mp3"))
        expect(result).to include("ERROR:")
        expect(result).to include("too large")
      end
    end

    context 'with missing API key' do
      before do
        stub_const("CONFIG", {
          "OPENAI_API_KEY" => "",
          "GEMINI_API_KEY" => "",
          "EXTRA_LOGGING" => nil
        })
      end

      it 'returns error when no API key is available' do
        result = agent.audio_transcription_agent(audio_path: File.join(@data_dir, "audio.mp3"))
        expect(result).to include("ERROR:")
        expect(result).to include("needs OPENAI_API_KEY")
      end
    end
  end

  describe '#resolve_audio_path' do
    context 'path traversal prevention' do
      it 'rejects paths with ../ at the start' do
        result = agent.send(:resolve_audio_path, "../etc/passwd")
        expect(result).to include("ERROR:")
        expect(result).to include("path traversal")
      end

      it 'rejects paths with /../ in the middle' do
        result = agent.send(:resolve_audio_path, "/monadic/data/../etc/passwd")
        expect(result).to include("ERROR:")
        expect(result).to include("path traversal")
      end

      it 'rejects standalone ..' do
        result = agent.send(:resolve_audio_path, "..")
        expect(result).to include("ERROR:")
        expect(result).to include("path traversal")
      end

      it 'allows filenames containing double dots' do

        result = agent.send(:resolve_audio_path, "audio..final.mp3")
        expect(result).to eq(File.join(@data_dir, "audio..final.mp3"))
      end
    end

    context 'shared volume resolution' do
      it 'finds files in SHARED_VOL' do

        result = agent.send(:resolve_audio_path, "test.mp3")
        expect(result).to eq(File.join(@data_dir, "test.mp3"))
      end

      it 'strips leading ./ before resolving' do

        result = agent.send(:resolve_audio_path, "./test.mp3")
        expect(result).to eq(File.join(@data_dir, "test.mp3"))
      end
    end
  end

  describe '#resolve_audio_provider' do
    it 'returns openai for OpenAI provider' do
      agent.settings["provider"] = "openai"
      expect(agent.send(:resolve_audio_provider)).to eq("openai")
    end

    it 'returns google for Gemini provider' do
      agent.settings["provider"] = "gemini"
      expect(agent.send(:resolve_audio_provider)).to eq("google")
    end

    # Provider Independence: the audio goes to the app's own provider or
    # nowhere, even when another provider has a key.
    it 'does not fall back to another provider for a provider without speech-to-text' do
      agent.settings["provider"] = "anthropic"
      expect(agent.send(:resolve_audio_provider)).to be_nil
    end

    it 'does not fall back to Gemini when the app is not on Gemini' do
      agent.settings["provider"] = "cohere"
      stub_const("CONFIG", {
        "OPENAI_API_KEY" => "",
        "GEMINI_API_KEY" => "test-gemini-key",
        "EXTRA_LOGGING" => nil
      })
      expect(agent.send(:resolve_audio_provider)).to be_nil
    end
  end

  describe 'constants' do
    it 'defines AUDIO_PROVIDER_MAP as frozen' do
      expect(AudioTranscriptionAgent::AUDIO_PROVIDER_MAP).to be_frozen
    end

    it 'defines AUDIO_API_KEYS as frozen' do
      expect(AudioTranscriptionAgent::AUDIO_API_KEYS).to be_frozen
    end

    it 'defines AUDIO_MIME_TYPES for common formats' do
      expect(AudioTranscriptionAgent::AUDIO_MIME_TYPES).to include("mp3", "wav", "ogg", "m4a")
    end

    it 'enforces 25MB file size limit' do
      expect(AudioTranscriptionAgent::AUDIO_MAX_FILE_SIZE).to eq(25 * 1024 * 1024)
    end
  end
end
