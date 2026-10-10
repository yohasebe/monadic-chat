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
      "XAI_API_KEY" => "test-xai-key",
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


    context 'with Grok provider' do
      before { agent.settings["provider"] = "grok" }

      it "sends the file to xAI's own speech-to-text" do
        allow(agent).to receive(:transcribe_xai).and_return("Grok transcript")
        result = agent.audio_transcription_agent(audio_path: File.join(@data_dir, "audio.mp3"))
        expect(result).to eq("Grok transcript")
        expect(agent).to have_received(:transcribe_xai).with("audio bytes", "mp3", "xai-stt", "test-xai-key", nil)
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

    it 'returns xai for Grok provider' do
      agent.settings["provider"] = "grok"
      expect(agent.send(:resolve_audio_provider)).to eq("xai")
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


  describe 'xAI and in-memory requests' do
    let(:posted) { {} }

    def answer(status, body)
      response = double(status: double(success?: status == 200, to_s: status.to_s), body: body)
      timed = double
      allow(timed).to receive(:post) do |url, body:|
        posted.merge!(url: url, body: body)
        response
      end
      allow(HTTP).to receive(:headers) do |headers|
        posted[:headers] = headers
        double(timeout: timed)
      end
    end

    it 'posts the audio as a multipart file, with the language when one is given' do
      answer(200, { text: "こんにちは" }.to_json)
      expect(agent.send(:transcribe_xai, "RIFFwav", "wav", "xai-stt", "test-xai-key", "ja")).to eq("こんにちは")
      expect(posted[:url]).to eq("https://api.x.ai/v1/stt")
      expect(posted[:headers]["Authorization"]).to eq("Bearer test-xai-key")
      expect(posted[:body]).to include('filename="audio.wav"', "RIFFwav", 'name="language"', "ja")
    end

    it 'lets the service detect the language when none is given' do
      answer(200, { text: "hi" }.to_json)
      agent.send(:transcribe_xai, "RIFFwav", "wav", "xai-stt", "test-xai-key", "auto")
      expect(posted[:body]).not_to include('name="language"')
    end

    it 'returns an error string for a failed request' do
      answer(500, { error: "busy" }.to_json)
      expect(agent.send(:transcribe_xai, "x", "wav", "xai-stt", "k", nil)).to eq("ERROR: xAI STT API error (500): busy")
    end

    it 'transcribes audio held in memory with the provider that owns it' do
      allow(agent).to receive(:gemini_transcription_request).and_return("gemini text")
      allow(agent).to receive(:transcribe_xai).and_return("xai text")
      expect(agent.transcribe_audio_bytes("google", "RIFF", "wav", "gemini-3.8-flash")).to eq("gemini text")
      expect(agent).to have_received(:gemini_transcription_request).with("RIFF", "audio/wav", "gemini-3.8-flash", "test-gemini-key", nil)
      expect(agent.transcribe_audio_bytes("xai", "RIFF", "wav", "xai-stt", "ja")).to eq("xai text")
      expect(agent.transcribe_audio_bytes("openai", "RIFF", "wav", "gpt-transcribe")).to start_with("ERROR:")
    end

    it 'says which key is missing instead of sending' do
      CONFIG["XAI_API_KEY"] = ""
      expect(agent.transcribe_audio_bytes("xai", "RIFF", "wav", "xai-stt")).to eq("ERROR: XAI_API_KEY is not set")
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
