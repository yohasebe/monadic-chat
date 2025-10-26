# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/agents/video_analyze_agent'

RSpec.describe VideoAnalyzeAgent do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include VideoAnalyzeAgent
      
      attr_accessor :settings

      def initialize
        @settings = { "model" => "gpt-4.1" }
      end

      # Add session method for testing
      def session
        @session ||= { parameters: {} }
      end

      # Mock methods that would normally come from MonadicApp
      def send_command(command:, container:)
        # Return mock output based on the command
        if command.include?("extract_frames.py")
          <<~OUTPUT
            13 frames extracted
            Base64-encoded frames saved to ./frames_20250629_154801.json
            Audio extracted to ./audio_20250629_154802.mp3
          OUTPUT
        elsif command.include?("video_query.rb")
          "This is a video showing a deer crossing the road."
        elsif command.include?("stt_query.rb")
          <<~OUTPUT
            1
            00:00:00,000 --> 00:00:02,000
            Hello world
          OUTPUT
        end
      end
      
      def check_vision_capability(model)
        model
      end
    end
  end
  
  let(:agent) { test_class.new }
  
  describe '#analyze_video' do
    context 'when video processing is successful' do
      it 'extracts frames and returns video description with audio transcript' do
        result = agent.analyze_video(file: "test.mp4", fps: 1, query: "What is happening?")
        
        expect(result).to include("This is a video showing a deer crossing the road")
        expect(result).to include("Audio Transcript:")
        expect(result).to include("Hello world")
      end
      
      it 'handles video without query parameter' do
        result = agent.analyze_video(file: "test.mp4", fps: 1)
        
        expect(result).to include("This is a video showing a deer crossing the road")
      end
    end
    
    context 'when frame extraction fails' do
      it 'returns error message when no JSON file is found' do
        allow(agent).to receive(:send_command).and_return("Error: Failed to extract frames")
        
        result = agent.analyze_video(file: "test.mp4")
        
        expect(result).to include("Error: Failed to extract frames from video")
      end
    end
    
    context 'when file parameter is missing' do
      it 'returns error message' do
        result = agent.analyze_video(file: nil)
        
        expect(result).to eq("Error: file is required.")
      end
      
      it 'returns error message for empty string' do
        result = agent.analyze_video(file: "")
        
        expect(result).to eq("Error: file is required.")
      end
    end
    
    context 'output parsing' do
      it 'correctly parses JSON and audio file paths from extract_frames output' do
        output = <<~OUTPUT
          15 frames extracted
          Base64-encoded frames saved to ./my_frames_123.json
          Audio extracted to ./my_audio_456.mp3
        OUTPUT
        
        allow(agent).to receive(:send_command).and_return(output, "Video description", "Audio transcript")
        
        result = agent.analyze_video(file: "test.mp4")
        
        # Verify that the correct files were parsed
        expect(agent).to have_received(:send_command)
          .with(hash_including(command: /video_query\.rb "\.\/my_frames_123\.json"/))
        expect(agent).to have_received(:send_command)
          .with(hash_including(command: /stt_query\.rb "\.\/my_audio_456\.mp3"/))
      end
      
      it 'handles output without audio file' do
        output = <<~OUTPUT
          15 frames extracted
          Base64-encoded frames saved to ./frames_only.json
        OUTPUT
        
        allow(agent).to receive(:send_command).and_return(output, "Video description")
        
        result = agent.analyze_video(file: "test.mp4")
        
        expect(result).to include("Video description")
        expect(result).not_to include("Audio Transcript:")
      end
    end
    
    context 'error handling' do
      it 'returns video analysis error when video_query fails' do
        allow(agent).to receive(:send_command).and_return(
          "Base64-encoded frames saved to ./frames.json\nAudio extracted to ./audio.mp3",
          "ERROR: Failed to analyze video"
        )
        
        result = agent.analyze_video(file: "test.mp4")
        
        expect(result).to eq("Video analysis failed: ERROR: Failed to analyze video")
      end
      
      it 'includes audio error in output when stt_query fails' do
        allow(agent).to receive(:send_command).and_return(
          "Base64-encoded frames saved to ./frames.json\nAudio extracted to ./audio.mp3",
          "Video description",
          "An error occurred: Failed to transcribe audio"
        )
        
        result = agent.analyze_video(file: "test.mp4")
        
        expect(result).to include("Video description")
        expect(result).to include("Audio transcription failed:")
      end
    end
  end
end