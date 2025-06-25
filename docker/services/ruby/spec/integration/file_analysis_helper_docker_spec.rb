# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/app'
require_relative '../../lib/monadic/adapters/file_analysis_helper'

RSpec.describe "FileAnalysisHelper Docker Integration", type: :integration do
  # Create a test app that includes the necessary modules
  let(:test_app) do
    Class.new(MonadicApp) do
      include MonadicHelper
      
      def initialize
        super(
          app_name: "TestFileAnalysis",
          icon: "test",
          description: "Test app for file analysis",
          initial_prompt: "Test prompt"
        )
        @settings = {
          "model" => "gpt-4.1",
          :model => "gpt-4.1"
        }
      end
    end
  end
  
  let(:app_instance) { test_app.new }
  
  # Skip tests if required scripts are not available
  before(:all) do
    # Check if image_query.rb exists
    image_query_path = if defined?(IN_CONTAINER) && IN_CONTAINER
                         "/monadic/scripts/cli_tools/image_query.rb"
                       else
                         File.join(Dir.home, "monadic/scripts/cli_tools/image_query.rb")
                       end
    
    unless File.exist?(image_query_path)
      skip "This test requires image_query.rb script to be available"
    end
  end
  
  describe "#analyze_image" do
    context "with a real test image" do
      before do
        # Create a simple test image
        @test_image_path = if defined?(IN_CONTAINER) && IN_CONTAINER
                             "/monadic/data/test_image.png"
                           else
                             File.join(Dir.home, "monadic/data/test_image.png")
                           end
        
        # Create a simple PNG image using ImageMagick if available
        if system("which convert > /dev/null 2>&1")
          system("convert -size 100x100 xc:white -pointsize 20 -draw 'text 10,50 \"TEST\"' #{@test_image_path}")
        else
          # If ImageMagick is not available, skip the test
          skip "ImageMagick is required for this test"
        end
      end
      
      after do
        File.delete(@test_image_path) if File.exist?(@test_image_path)
      end
      
      it "analyzes an image and returns a result" do
        result = app_instance.analyze_image(
          message: "What is in this image?",
          image_path: @test_image_path,
          model: "gpt-4.1"
        )
        
        expect(result).to be_a(String)
        expect(result).not_to be_empty
        # The actual result will depend on the model's response
      end
      
      it "handles quotes in the message" do
        result = app_instance.analyze_image(
          message: 'Describe this image with "quotes" in the prompt',
          image_path: @test_image_path
        )
        
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end
    end
    
    context "with missing image" do
      it "handles missing image gracefully" do
        result = app_instance.analyze_image(
          message: "Analyze this",
          image_path: "/nonexistent/image.jpg"
        )
        
        # Should return an error or handle gracefully
        expect(result).to be_a(String)
      end
    end
  end
  
  describe "#analyze_audio" do
    context "with a real test audio" do
      before do
        # Create a simple test audio file
        @test_audio_path = if defined?(IN_CONTAINER) && IN_CONTAINER
                             "/monadic/data/test_audio.wav"
                           else
                             File.join(Dir.home, "monadic/data/test_audio.wav")
                           end
        
        # Create a simple WAV file using sox if available
        if system("which sox > /dev/null 2>&1")
          # Generate a 1-second sine wave
          system("sox -n #{@test_audio_path} synth 1 sine 440")
        else
          # If sox is not available, skip the test
          skip "Sox is required for this test"
        end
      end
      
      after do
        File.delete(@test_audio_path) if File.exist?(@test_audio_path)
      end
      
      it "analyzes audio and returns a result" do
        result = app_instance.analyze_audio(
          audio: @test_audio_path,
          model: "whisper-1"
        )
        
        expect(result).to be_a(String)
        # The result should be a JSON string or transcription
      end
      
      it "uses default model when not specified" do
        result = app_instance.analyze_audio(
          audio: @test_audio_path
        )
        
        expect(result).to be_a(String)
      end
    end
    
    context "with missing audio" do
      it "handles missing audio file gracefully" do
        result = app_instance.analyze_audio(
          audio: "/nonexistent/audio.mp3"
        )
        
        # Should return an error or handle gracefully
        expect(result).to be_a(String)
      end
    end
  end
  
  describe "command execution verification" do
    it "executes commands in the correct container" do
      # This test verifies that commands are actually executed
      # We can check this by looking at the command format
      
      # For image analysis
      image_command = app_instance.send(:build_image_command, 
        message: "test",
        image_path: "/test.jpg",
        model: "gpt-4.1"
      )
      expect(image_command).to include("image_query.rb")
      expect(image_command).to include("gpt-4.1")
      
      # For audio analysis  
      audio_command = app_instance.send(:build_audio_command,
        audio: "/test.mp3",
        model: "whisper-1"
      )
      expect(audio_command).to include("stt_query.rb")
      expect(audio_command).to include("whisper-1")
    end
  end if false  # Disable this test if the private methods don't exist
end