# frozen_string_literal: true

require 'spec_helper'
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

  before do
    stub_const("CONFIG", {
      "OPENAI_API_KEY" => "test-openai-key",
      "GEMINI_API_KEY" => "test-gemini-key",
      "EXTRA_LOGGING" => nil
    })
    stub_const("SHARED_VOL", "/monadic/data")
    stub_const("LOCAL_SHARED_VOL", File.expand_path(File.join(Dir.home, "monadic", "data")))
  end

  describe '#audio_transcription_agent' do
    context 'with valid audio file (OpenAI)' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/audio.mp3").and_return(true)
        allow(File).to receive(:size).with("/test/audio.mp3").and_return(5 * 1024 * 1024)
        allow(agent).to receive(:transcribe_openai).and_return("Hello world, this is the transcript.")
      end

      it 'returns transcript text' do
        result = agent.audio_transcription_agent(audio_path: "/test/audio.mp3")
        expect(result).to eq("Hello world, this is the transcript.")
      end

      it 'uses default model when none specified' do
        agent.audio_transcription_agent(audio_path: "/test/audio.mp3")
        expect(agent).to have_received(:transcribe_openai).with(
          "/test/audio.mp3",
          "gpt-4o-mini-transcribe-2025-12-15",
          "test-openai-key",
          "text",
          nil
        )
      end

      it 'passes custom model when specified' do
        agent.audio_transcription_agent(audio_path: "/test/audio.mp3", model: "whisper-1")
        expect(agent).to have_received(:transcribe_openai).with(
          "/test/audio.mp3",
          "whisper-1",
          "test-openai-key",
          "text",
          nil
        )
      end
    end

    context 'with Gemini provider' do
      before do
        agent.settings["provider"] = "gemini"
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/audio.mp3").and_return(true)
        allow(File).to receive(:size).with("/test/audio.mp3").and_return(1024)
        allow(agent).to receive(:transcribe_gemini).and_return("Gemini transcript")
      end

      it 'uses Gemini for Google provider' do
        result = agent.audio_transcription_agent(audio_path: "/test/audio.mp3")
        expect(result).to eq("Gemini transcript")
        expect(agent).to have_received(:transcribe_gemini)
      end
    end

    context 'with missing audio file' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/nonexistent.mp3").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/nonexistent.mp3").and_return(false)
        local_path = File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "nonexistent.mp3")
        allow(File).to receive(:exist?).with(local_path).and_return(false)
      end

      it 'returns error for missing file' do
        result = agent.audio_transcription_agent(audio_path: "/nonexistent.mp3")
        expect(result).to include("ERROR:")
        expect(result).to include("not found")
      end
    end

    context 'with oversized audio file' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/huge.mp3").and_return(true)
        allow(File).to receive(:size).with("/test/huge.mp3").and_return(30 * 1024 * 1024)
      end

      it 'returns error for files exceeding 25MB' do
        result = agent.audio_transcription_agent(audio_path: "/test/huge.mp3")
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
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/test/audio.mp3").and_return(true)
        allow(File).to receive(:size).with("/test/audio.mp3").and_return(1024)
      end

      it 'returns error when no API key is available' do
        result = agent.audio_transcription_agent(audio_path: "/test/audio.mp3")
        expect(result).to include("ERROR:")
        expect(result).to include("No API key")
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
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("audio..final.mp3").and_return(true)

        result = agent.send(:resolve_audio_path, "audio..final.mp3")
        expect(result).to eq("audio..final.mp3")
      end
    end

    context 'shared volume resolution' do
      before do
        allow(File).to receive(:exist?).and_call_original
      end

      it 'finds files in SHARED_VOL' do
        allow(File).to receive(:exist?).with("test.mp3").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/test.mp3").and_return(true)

        result = agent.send(:resolve_audio_path, "test.mp3")
        expect(result).to eq("/monadic/data/test.mp3")
      end

      it 'strips leading ./ before resolving' do
        allow(File).to receive(:exist?).with("./test.mp3").and_return(false)
        allow(File).to receive(:exist?).with("/monadic/data/test.mp3").and_return(true)

        result = agent.send(:resolve_audio_path, "./test.mp3")
        expect(result).to eq("/monadic/data/test.mp3")
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

    it 'falls back to openai for non-audio provider' do
      agent.settings["provider"] = "anthropic"
      expect(agent.send(:resolve_audio_provider)).to eq("openai")
    end

    it 'falls back to gemini when OpenAI key is missing' do
      agent.settings["provider"] = "cohere"
      stub_const("CONFIG", {
        "OPENAI_API_KEY" => "",
        "GEMINI_API_KEY" => "test-gemini-key",
        "EXTRA_LOGGING" => nil
      })
      expect(agent.send(:resolve_audio_provider)).to eq("google")
    end
  end

  describe 'constants' do
    it 'defines AUDIO_MODELS as frozen' do
      expect(AudioTranscriptionAgent::AUDIO_MODELS).to be_frozen
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
