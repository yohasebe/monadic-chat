# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
require_relative '../../../lib/monadic/adapters/file_analysis_helper'

RSpec.describe MonadicHelper do
  # Test class that includes the module
  class TestFileAnalysisHelper
    include MonadicHelper

    attr_accessor :settings

    def initialize
      @settings = { "model" => "gpt-4.1" }
      @image_agent_calls = []
      @audio_agent_calls = []
    end

    # Mock image_analysis_agent method
    def image_analysis_agent(message:, image_path:)
      @image_agent_calls << { message: message, image_path: image_path }
      "Image analysis result: #{message}"
    end

    # Mock audio_transcription_agent method
    def audio_transcription_agent(audio_path:, model: nil, response_format: "text", lang_code: nil)
      @audio_agent_calls << { audio_path: audio_path, model: model, response_format: response_format }
      "Transcription result for: #{audio_path}"
    end

    def image_agent_calls
      @image_agent_calls
    end

    def audio_agent_calls
      @audio_agent_calls
    end
  end

  let(:helper) { TestFileAnalysisHelper.new }

  describe '#analyze_image' do
    it 'delegates to image_analysis_agent' do
      result = helper.analyze_image(
        message: "What is in this image?",
        image_path: "/tmp/test_image.png"
      )

      expect(helper.image_agent_calls.size).to eq(1)
      call = helper.image_agent_calls.last
      expect(call[:message]).to eq("What is in this image?")
      expect(call[:image_path]).to eq("/tmp/test_image.png")
      expect(result).to include("Image analysis result")
    end

    it 'escapes double quotes in message' do
      helper.analyze_image(
        message: 'What is the "main" content?',
        image_path: "/tmp/test_image.png"
      )

      call = helper.image_agent_calls.last
      expect(call[:message]).to include('\\"main\\"')
    end

    it 'handles empty message' do
      result = helper.analyze_image(
        message: "",
        image_path: "/tmp/test_image.png"
      )

      expect(result).to be_a(String)
      call = helper.image_agent_calls.last
      expect(call[:message]).to eq("")
    end

    it 'passes image_path through to agent' do
      special_path = "/tmp/test image (1).png"

      helper.analyze_image(
        message: "Test",
        image_path: special_path
      )

      call = helper.image_agent_calls.last
      expect(call[:image_path]).to eq(special_path)
    end

    it 'ignores model parameter (provider-auto-selected)' do
      helper.analyze_image(
        message: "Test",
        image_path: "/tmp/test.png",
        model: "gpt-5"
      )

      expect(helper.image_agent_calls.size).to eq(1)
    end
  end

  describe '#analyze_audio' do
    it 'delegates to audio_transcription_agent' do
      result = helper.analyze_audio(
        audio: "/tmp/test_audio.mp3",
        model: "gpt-4o-transcribe"
      )

      expect(helper.audio_agent_calls.size).to eq(1)
      call = helper.audio_agent_calls.last
      expect(call[:audio_path]).to eq("/tmp/test_audio.mp3")
      expect(call[:model]).to eq("gpt-4o-transcribe")
      expect(result).to include("Transcription result")
    end

    it 'uses STT model from settings when available' do
      helper.settings["stt_model"] = "gpt-4o-transcribe-diarize"

      helper.analyze_audio(audio: "/tmp/test_audio.mp3")

      call = helper.audio_agent_calls.last
      expect(call[:model]).to eq("gpt-4o-transcribe-diarize")
    end

    it 'falls back to nil when STT model not in settings (SSOT resolves downstream)' do
      helper.settings.delete("stt_model")

      helper.analyze_audio(audio: "/tmp/test_audio.mp3")

      call = helper.audio_agent_calls.last
      expect(call[:model]).to be_nil
    end

    it 'handles different audio formats' do
      formats = %w[mp3 wav m4a webm ogg]

      formats.each do |format|
        helper.analyze_audio(audio: "/tmp/test_audio.#{format}")
      end

      expect(helper.audio_agent_calls.size).to eq(formats.size)
      helper.audio_agent_calls.each_with_index do |call, i|
        expect(call[:audio_path]).to include(formats[i])
      end
    end

    it 'passes model parameter through to agent' do
      helper.analyze_audio(
        audio: "/tmp/test.mp3",
        model: "whisper-1"
      )

      call = helper.audio_agent_calls.last
      expect(call[:model]).to eq("whisper-1")
    end
  end
end
