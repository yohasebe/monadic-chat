# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/app'
require_relative '../../lib/monadic/adapters/file_analysis_helper'

RSpec.describe "FileAnalysisHelper without mocks" do
  # Create a minimal test app with real send_command implementation
  let(:test_app_class) do
    Class.new(MonadicApp) do
      include MonadicHelper
      
      def initialize
        @settings = { "model" => "gpt-4.1" }
        @context = []
        @executed_commands = []
      end
      
      attr_reader :executed_commands
      
      # Override send_command to capture commands without executing them
      def send_command(command:, container:, **kwargs)
        @executed_commands << {
          command: command,
          container: container,
          kwargs: kwargs
        }
        # Return a realistic response
        case command
        when /image_query\.rb/
          "Image analysis result"
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
    it "builds correct command for image analysis" do
      # Execute the method
      result = helper.analyze_image(
        message: "What is this?",
        image_path: "/test/image.jpg",
        model: "gpt-4.1"
      )
      
      # Check the captured command
      expect(helper.executed_commands.size).to eq(1)
      executed = helper.executed_commands.last
      
      expect(executed[:command]).to include("image_query.rb")
      expect(executed[:command]).to include("What is this?")
      expect(executed[:command]).to include("/test/image.jpg")
      expect(executed[:command]).to include("gpt-4.1")
      expect(executed[:container]).to eq("ruby")
      expect(result).to eq("Image analysis result")
    end
    
    it "properly escapes special characters in message" do
      # Clear previous commands
      helper.executed_commands.clear
      
      helper.analyze_image(
        message: 'Test with "quotes" and $pecial ch@rs!',
        image_path: "/test/image.jpg"
      )
      
      executed = helper.executed_commands.last
      # Check that quotes are properly escaped
      expect(executed[:command]).to include('\\"quotes\\"')
      # Other special characters should be preserved
      expect(executed[:command]).to include('$pecial ch@rs!')
    end
    
    it "uses settings model when model parameter is not provided" do
      # Clear previous commands
      helper.executed_commands.clear
      
      helper.analyze_image(
        message: "test",
        image_path: "/test/image.jpg"
      )
      
      executed = helper.executed_commands.last
      expect(executed[:command]).to include("gpt-4.1")
    end
  end
  
  describe "#analyze_audio" do
    it "builds correct command for audio analysis" do
      # Clear previous commands
      helper.executed_commands.clear
      
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
      # Clear previous commands
      helper.executed_commands.clear
      
      helper.analyze_audio(audio: "/test/audio.mp3")
      
      executed = helper.executed_commands.last
      # Default model is gpt-4o-transcribe
      expect(executed[:command]).to include("gpt-4o-transcribe")
    end
    
    it "constructs command with correct parameter order" do
      # Clear previous commands
      helper.executed_commands.clear
      
      helper.analyze_audio(
        audio: "/path/to/file.wav",
        model: "whisper-1"
      )
      
      executed = helper.executed_commands.last
      # Verify the command has all parameters in correct order
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
    it "returns send_command result directly" do
      # Create a new helper that returns an error
      error_helper_class = Class.new(MonadicApp) do
        include MonadicHelper
        
        def initialize
          @settings = { "model" => "gpt-4.1" }
          @context = []
        end
        
        def send_command(command:, container:, **kwargs)
          "Error: File not found"
        end
      end
      
      error_helper = error_helper_class.new
      
      result = error_helper.analyze_image(
        message: "test",
        image_path: "/nonexistent.jpg"
      )
      
      expect(result).to eq("Error: File not found")
    end
  end
end