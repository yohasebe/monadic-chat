# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/app'
require_relative '../../lib/monadic/adapters/file_analysis_helper'

RSpec.describe "FileAnalysisHelper without mocks" do
  # Create a minimal test app
  let(:test_app_class) do
    Class.new(MonadicApp) do
      include MonadicHelper
      
      def initialize
        @settings = { "model" => "gpt-4.1" }
        @context = []
      end
    end
  end
  
  let(:helper) { test_app_class.new }
  
  describe "#analyze_image" do
    it "builds correct command for image analysis" do
      # Test the command construction without actually executing it
      # We'll override send_command to capture the command
      
      executed_command = nil
      executed_container = nil
      
      allow(helper).to receive(:send_command) do |args|
        executed_command = args[:command]
        executed_container = args[:container]
        "Mock result"
      end
      
      helper.analyze_image(
        message: "What is this?",
        image_path: "/test/image.jpg",
        model: "gpt-4.1"
      )
      
      expect(executed_command).to include("image_query.rb")
      expect(executed_command).to include("What is this?")
      expect(executed_command).to include("/test/image.jpg")
      expect(executed_command).to include("gpt-4.1")
      expect(executed_container).to eq("ruby")
    end
    
    it "properly escapes special characters in message" do
      executed_command = nil
      
      allow(helper).to receive(:send_command) do |args|
        executed_command = args[:command]
        "Mock result"
      end
      
      helper.analyze_image(
        message: 'Test with "quotes" and $pecial ch@rs!',
        image_path: "/test/image.jpg"
      )
      
      # Check that quotes are properly escaped
      expect(executed_command).to include('\\"quotes\\"')
      # Other special characters should be preserved
      expect(executed_command).to include('$pecial ch@rs!')
    end
    
    it "uses settings model when model parameter is not provided" do
      executed_command = nil
      
      allow(helper).to receive(:send_command) do |args|
        executed_command = args[:command]
        "Mock result"
      end
      
      helper.analyze_image(
        message: "test",
        image_path: "/test/image.jpg"
      )
      
      expect(executed_command).to include("gpt-4.1")
    end
  end
  
  describe "#analyze_audio" do
    it "builds correct command for audio analysis" do
      executed_command = nil
      executed_container = nil
      
      allow(helper).to receive(:send_command) do |args|
        executed_command = args[:command]
        executed_container = args[:container]
        "Mock result"
      end
      
      helper.analyze_audio(
        audio: "/test/audio.mp3",
        model: "whisper-1"
      )
      
      expect(executed_command).to include("stt_query.rb")
      expect(executed_command).to include("/test/audio.mp3")
      expect(executed_command).to include("whisper-1")
      expect(executed_command).to include('"."')  # output directory
      expect(executed_command).to include('"json"')  # format
      expect(executed_container).to eq("ruby")
    end
    
    it "uses default model when not specified" do
      executed_command = nil
      
      allow(helper).to receive(:send_command) do |args|
        executed_command = args[:command]
        "Mock result"
      end
      
      helper.analyze_audio(audio: "/test/audio.mp3")
      
      # Default model is gpt-4o-transcribe
      expect(executed_command).to include("gpt-4o-transcribe")
    end
    
    it "constructs command with correct parameter order" do
      executed_command = nil
      
      allow(helper).to receive(:send_command) do |args|
        executed_command = args[:command]
        "Mock result"
      end
      
      helper.analyze_audio(
        audio: "/path/to/file.wav",
        model: "whisper-1"
      )
      
      # Verify the command has all parameters in correct order
      parts = executed_command.split(/\s+/)
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
      allow(helper).to receive(:send_command).and_return("Error: File not found")
      
      result = helper.analyze_image(
        message: "test",
        image_path: "/nonexistent.jpg"
      )
      
      expect(result).to eq("Error: File not found")
    end
  end
end