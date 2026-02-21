# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/app'
require_relative '../../lib/monadic/adapters/file_analysis_helper'

RSpec.describe "FileAnalysisHelper without mocks" do
  # Create a minimal test app with real MonadicApp class
  # (includes ImageAnalysisAgent and AudioTranscriptionAgent)
  let(:test_app_class) do
    Class.new(MonadicApp) do
      include MonadicHelper

      def initialize
        @settings = { "model" => "gpt-4.1", "provider" => "openai" }
        @context = []
        @image_agent_calls = []
        @audio_agent_calls = []
      end

      attr_reader :image_agent_calls, :audio_agent_calls

      # Override image_analysis_agent to capture calls without making HTTP requests
      def image_analysis_agent(message:, image_path:)
        @image_agent_calls << { message: message, image_path: image_path }
        "Image analysis result for: #{message}"
      end

      # Override audio_transcription_agent to capture calls without making HTTP requests
      def audio_transcription_agent(audio_path:, model: nil, response_format: "text", lang_code: nil)
        @audio_agent_calls << { audio_path: audio_path, model: model, response_format: response_format }
        "Transcription result for: #{audio_path}"
      end
    end
  end

  let(:helper) { test_app_class.new }

  describe "#analyze_image" do
    it "delegates to image_analysis_agent with correct arguments" do
      result = helper.analyze_image(
        message: "What is this?",
        image_path: "/test/image.jpg",
        model: "gpt-4.1"
      )

      expect(helper.image_agent_calls.size).to eq(1)
      call = helper.image_agent_calls.last
      expect(call[:message]).to eq("What is this?")
      expect(call[:image_path]).to eq("/test/image.jpg")
      expect(result).to include("Image analysis result")
    end

    it "properly escapes special characters in message" do
      helper.analyze_image(
        message: 'Test with "quotes" and $pecial ch@rs!',
        image_path: "/test/image.jpg"
      )

      call = helper.image_agent_calls.last
      expect(call[:message]).to include('\\"quotes\\"')
      expect(call[:message]).to include('$pecial ch@rs!')
    end

    it "does not use send_command (uses agent instead)" do
      helper.analyze_image(
        message: "test",
        image_path: "/test/image.jpg"
      )

      expect(helper.image_agent_calls.size).to eq(1)
    end
  end

  describe "#analyze_audio" do
    it "delegates to audio_transcription_agent with correct arguments" do
      result = helper.analyze_audio(
        audio: "/test/audio.mp3",
        model: "whisper-1"
      )

      expect(helper.audio_agent_calls.size).to eq(1)
      call = helper.audio_agent_calls.last
      expect(call[:audio_path]).to eq("/test/audio.mp3")
      expect(call[:model]).to eq("whisper-1")
      expect(result).to include("Transcription result")
    end

    it "uses default model when not specified" do
      helper.analyze_audio(audio: "/test/audio.mp3")

      call = helper.audio_agent_calls.last
      expect(call[:model]).to eq("gpt-4o-mini-transcribe-2025-12-15")
    end

    it "does not use send_command (uses agent instead)" do
      helper.analyze_audio(audio: "/test/audio.mp3")

      # Should use audio_transcription_agent, not send_command
      expect(helper.audio_agent_calls.size).to eq(1)
    end
  end

  describe "error handling" do
    it "returns agent result for analyze_image errors" do
      error_helper_class = Class.new(MonadicApp) do
        include MonadicHelper

        def initialize
          @settings = { "model" => "gpt-4.1", "provider" => "openai" }
          @context = []
        end

        def image_analysis_agent(message:, image_path:)
          "ERROR: Image file not found: #{image_path}"
        end
      end

      error_helper = error_helper_class.new

      result = error_helper.analyze_image(
        message: "test",
        image_path: "/nonexistent.jpg"
      )

      expect(result).to include("ERROR")
      expect(result).to include("/nonexistent.jpg")
    end

    it "returns agent result for analyze_audio errors" do
      error_helper_class = Class.new(MonadicApp) do
        include MonadicHelper

        def initialize
          @settings = { "model" => "gpt-4.1", "provider" => "openai" }
          @context = []
        end

        def audio_transcription_agent(audio_path:, model: nil, response_format: "text", lang_code: nil)
          "ERROR: Audio file not found: #{audio_path}"
        end
      end

      error_helper = error_helper_class.new

      result = error_helper.analyze_audio(audio: "/nonexistent.mp3")

      expect(result).to include("ERROR")
      expect(result).to include("/nonexistent.mp3")
    end
  end
end
