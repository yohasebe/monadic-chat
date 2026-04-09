# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/adapters/file_analysis_helper'
require 'fileutils'

# Test implementation that mimics MonadicApp behavior
# analyze_image delegates to image_analysis_agent (ImageAnalysisAgent)
# analyze_audio delegates to audio_transcription_agent (AudioTranscriptionAgent)
class TestFileAnalysisApp
  include MonadicHelper
  attr_reader :settings

  def initialize
    @settings = {
      "model" => "gpt-4.1",
      "provider" => "openai"
    }
  end

  # Mock image_analysis_agent (called by MonadicHelper#analyze_image)
  def image_analysis_agent(message:, image_path:)
    "Image analysis result for: #{image_path}"
  end

  # Mock audio_transcription_agent (called by MonadicHelper#analyze_audio)
  def audio_transcription_agent(audio_path:, model: nil, response_format: "text", lang_code: nil)
    "Audio transcription result for: #{audio_path}"
  end
end

RSpec.describe "FileAnalysisHelper Integration", type: :integration do
  let(:app_instance) { TestFileAnalysisApp.new }
  
  describe "#analyze_image" do
    context "with a real test image" do
      before do
        # Create a simple test image
        @test_image_path = File.join(Monadic::Utils::Environment.data_path, "test_image.png")
        
        # Create a simple PNG image using ImageMagick if available
        if system("which magick > /dev/null 2>&1")
          system("magick -size 100x100 xc:white -pointsize 20 -draw 'text 10,50 \"TEST\"' #{@test_image_path}")
        else
          # If ImageMagick is not available, create a minimal PNG file
          # PNG header and minimal data
          png_data = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack("C*")
          File.binwrite(@test_image_path, png_data)
        end
      end
      
      after do
        File.delete(@test_image_path) if File.exist?(@test_image_path)
      end
      
      it "analyzes an image with a custom message" do
        result = app_instance.analyze_image(
          message: "What is in this image?",
          image_path: @test_image_path,
          model: "gpt-4.1"
        )
        
        expect(result).to be_a(String)
        expect(result).not_to be_empty
        # The actual result will depend on the model's response
      end
      
      it "uses the model from settings if not provided" do
        result = app_instance.analyze_image(
          message: "Describe this image",
          image_path: @test_image_path
        )
        
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end
      
      it "handles quotes in the message" do
        result = app_instance.analyze_image(
          message: 'Describe this image with "quotes" in the prompt',
          image_path: @test_image_path
        )
        
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end
      
      it "handles special characters in image paths" do
        # Create test image with special characters
        special_path = File.join(Monadic::Utils::Environment.data_path, "test image (special).png")

        # Create a fresh image for this test (source may be cleaned up by after block)
        png_data = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack("C*")
        File.binwrite(special_path, png_data)
        
        result = app_instance.analyze_image(
          message: "Test special path",
          image_path: special_path
        )
        
        expect(result).to be_a(String)
        
        # Cleanup
        File.delete(special_path) if File.exist?(special_path)
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
        @test_audio_path = File.join(Monadic::Utils::Environment.data_path, "test_audio.wav")
        
        # Create a simple WAV file using sox if available
        if system("which sox > /dev/null 2>&1")
          # Generate a 1-second sine wave
          system("sox -n #{@test_audio_path} synth 1 sine 440")
        else
          # Create a minimal WAV file header
          # WAV file with minimal header (44 bytes)
          wav_header = "RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xAC\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00"
          File.binwrite(@test_audio_path, wav_header)
        end
      end
      
      after do
        File.delete(@test_audio_path) if File.exist?(@test_audio_path)
      end
      
      it "analyzes audio files" do
        result = app_instance.analyze_audio(
          audio: @test_audio_path,
          model: "whisper-1"
        )
        
        expect(result).to be_a(String)
        # The result should be a JSON string or transcription
      end
      
      it "uses default audio model when not specified" do
        result = app_instance.analyze_audio(
          audio: @test_audio_path
        )
        
        expect(result).to be_a(String)
      end
      
      it "handles special characters in audio paths" do
        # Create audio file with special characters
        special_audio_path = File.join(Monadic::Utils::Environment.data_path, "test audio (special).wav")
        
        # Copy test audio to special path
        FileUtils.cp(@test_audio_path, special_audio_path)
        
        result = app_instance.analyze_audio(
          audio: special_audio_path
        )
        
        expect(result).to be_a(String)
        
        # Cleanup
        File.delete(special_audio_path) if File.exist?(special_audio_path)
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
  
end