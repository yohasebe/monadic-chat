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
      @agent_calls = []
    end

    # Mock image_analysis_agent method
    def image_analysis_agent(message:, image_path:)
      @agent_calls << { message: message, image_path: image_path }
      "Image analysis result: #{message}"
    end

    def agent_calls
      @agent_calls
    end

    # Mock send_command method for analyze_audio tests
    def send_command(command:, container:)
      @last_command = command
      @last_container = container

      if command.include?("stt_query.rb")
        '{"text": "This is a test audio transcription."}'
      else
        "Command executed: #{command}"
      end
    end

    def last_command
      @last_command
    end

    def last_container
      @last_container
    end
  end

  let(:helper) { TestFileAnalysisHelper.new }

  describe '#analyze_image' do
    it 'delegates to image_analysis_agent' do
      result = helper.analyze_image(
        message: "What is in this image?",
        image_path: "/tmp/test_image.png"
      )

      expect(helper.agent_calls.size).to eq(1)
      call = helper.agent_calls.last
      expect(call[:message]).to eq("What is in this image?")
      expect(call[:image_path]).to eq("/tmp/test_image.png")
      expect(result).to include("Image analysis result")
    end

    it 'escapes double quotes in message' do
      helper.analyze_image(
        message: 'What is the "main" content?',
        image_path: "/tmp/test_image.png"
      )

      call = helper.agent_calls.last
      expect(call[:message]).to include('\\"main\\"')
    end

    it 'handles empty message' do
      result = helper.analyze_image(
        message: "",
        image_path: "/tmp/test_image.png"
      )

      expect(result).to be_a(String)
      call = helper.agent_calls.last
      expect(call[:message]).to eq("")
    end

    it 'passes image_path through to agent' do
      special_path = "/tmp/test image (1).png"

      helper.analyze_image(
        message: "Test",
        image_path: special_path
      )

      call = helper.agent_calls.last
      expect(call[:image_path]).to eq(special_path)
    end

    it 'ignores model parameter (provider-auto-selected)' do
      helper.analyze_image(
        message: "Test",
        image_path: "/tmp/test.png",
        model: "gpt-5"
      )

      expect(helper.agent_calls.size).to eq(1)
    end
  end

  describe '#analyze_audio' do
    it 'analyzes audio with default model' do
      audio_path = "/tmp/test_audio.mp3"

      result = helper.analyze_audio(
        audio: audio_path,
        model: "gpt-4o-transcribe"
      )

      expect(helper.last_command).to include('stt_query.rb')
      expect(helper.last_command).to include(audio_path)
      expect(helper.last_command).to include('gpt-4o-transcribe')
      expect(helper.last_command).to include('"." "json" ""')  # output dir, format, lang
      expect(helper.last_container).to eq('ruby')
      expect(result).to include('test audio transcription')
    end

    it 'uses STT model from settings when available' do
      audio_path = "/tmp/test_audio.mp3"
      helper.settings["stt_model"] = "gpt-4o-transcribe-diarize"

      result = helper.analyze_audio(
        audio: audio_path
      )

      expect(helper.last_command).to include('stt_query.rb')
      expect(helper.last_command).to include('gpt-4o-transcribe-diarize')
      expect(result).to include('test audio transcription')
    end

    it 'falls back to default when STT model not in settings' do
      audio_path = "/tmp/test_audio.mp3"
      # Ensure stt_model is not in settings
      helper.settings.delete("stt_model")

      result = helper.analyze_audio(
        audio: audio_path
      )

      expect(helper.last_command).to include('stt_query.rb')
      expect(helper.last_command).to include('gpt-4o-mini-transcribe')
      expect(result).to include('test audio transcription')
    end

    it 'handles different audio formats' do
      formats = %w[mp3 wav m4a webm ogg]

      formats.each do |format|
        audio_path = "/tmp/test_audio.#{format}"

        helper.analyze_audio(audio: audio_path)

        expect(helper.last_command).to include(audio_path)
      end
    end

    it 'uses whisper model' do
      result = helper.analyze_audio(
        audio: "/tmp/test.mp3",
        model: "whisper-1"
      )

      expect(helper.last_command).to include('whisper-1')
      expect(result).to be_a(String)
    end
  end
end
