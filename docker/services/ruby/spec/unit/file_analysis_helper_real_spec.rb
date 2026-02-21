# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/app'
require_relative '../../lib/monadic/adapters/file_analysis_helper'

RSpec.describe "FileAnalysisHelper without mocks" do
  # Create a minimal test app with real MonadicApp class (includes ImageAnalysisAgent)
  let(:test_app_class) do
    Class.new(MonadicApp) do
      include MonadicHelper

      def initialize
        @settings = { "model" => "gpt-4.1", "provider" => "openai" }
        @context = []
        @agent_calls = []
        @executed_commands = []
      end

      attr_reader :agent_calls, :executed_commands

      # Override image_analysis_agent to capture calls without making HTTP requests
      def image_analysis_agent(message:, image_path:)
        @agent_calls << { message: message, image_path: image_path }
        "Image analysis result for: #{message}"
      end

      # Override send_command for analyze_audio tests
      def send_command(command:, container:, **kwargs)
        @executed_commands << {
          command: command,
          container: container,
          kwargs: kwargs
        }
        case command
        when /stt_query\.rb/
          '{"text": "Transcribed audio"}'
        else
          "Command executed"
        end
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

      expect(helper.agent_calls.size).to eq(1)
      call = helper.agent_calls.last
      expect(call[:message]).to eq("What is this?")
      expect(call[:image_path]).to eq("/test/image.jpg")
      expect(result).to include("Image analysis result")
    end

    it "properly escapes special characters in message" do
      helper.analyze_image(
        message: 'Test with "quotes" and $pecial ch@rs!',
        image_path: "/test/image.jpg"
      )

      call = helper.agent_calls.last
      # Double quotes should be escaped
      expect(call[:message]).to include('\\"quotes\\"')
      # Other special characters should be preserved
      expect(call[:message]).to include('$pecial ch@rs!')
    end

    it "does not use send_command (uses agent instead)" do
      helper.analyze_image(
        message: "test",
        image_path: "/test/image.jpg"
      )

      # No send_command calls should be made
      expect(helper.executed_commands).to be_empty
      # Instead, image_analysis_agent should be called
      expect(helper.agent_calls.size).to eq(1)
    end
  end

  describe "#analyze_audio" do
    it "builds correct command for audio analysis" do
      helper.analyze_audio(
        audio: "/test/audio.mp3",
        model: "whisper-1"
      )

      executed = helper.executed_commands.last
      expect(executed[:command]).to include("stt_query.rb")
      expect(executed[:command]).to include("/test/audio.mp3")
      expect(executed[:command]).to include("whisper-1")
      expect(executed[:command]).to include('"."')  # output directory
      expect(executed[:command]).to include('"json"')  # format
      expect(executed[:container]).to eq("ruby")
    end

    it "uses default model when not specified" do
      helper.analyze_audio(audio: "/test/audio.mp3")

      executed = helper.executed_commands.last
      # Default model is gpt-4o-mini-transcribe
      expect(executed[:command]).to include("gpt-4o-mini-transcribe")
    end

    it "constructs command with correct parameter order" do
      helper.analyze_audio(
        audio: "/path/to/file.wav",
        model: "whisper-1"
      )

      executed = helper.executed_commands.last
      parts = executed[:command].split(/\s+/)
      expect(parts[0]).to include("stt_query.rb")
      expect(parts[1]).to eq('"/path/to/file.wav"')
      expect(parts[2]).to eq('"."')
      expect(parts[3]).to eq('"json"')
      expect(parts[4]).to eq('""')
      expect(parts[5]).to eq('"whisper-1"')
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
  end
end
