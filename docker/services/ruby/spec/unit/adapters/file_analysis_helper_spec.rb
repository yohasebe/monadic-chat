# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'fileutils'
# require 'mini_magick' # Not available in test environment
require_relative '../../../lib/monadic/adapters/file_analysis_helper'

RSpec.describe MonadicHelper do
  # Test class that includes the module
  class TestFileAnalysisHelper
    include MonadicHelper
    
    attr_accessor :settings
    
    def initialize
      @settings = { "model" => "gpt-4.1" }
    end
    
    # Mock check_vision_capability method
    def check_vision_capability(model)
      # Simulate vision capability check
      model&.include?("gpt-4") ? model : nil
    end
    
    # Mock send_command method to capture commands
    def send_command(command:, container:)
      @last_command = command
      @last_container = container
      
      # Return simulated response based on command
      if command.include?("image_query.rb")
        "The image contains text saying 'Hello World' on a white background."
      elsif command.include?("stt_query.rb")
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
    let(:test_image_path) { "/tmp/test_image.png" }
    
    before do
      # Create a simple test image using MiniMagick
      create_test_image(test_image_path)
    end
    
    after do
      File.delete(test_image_path) if File.exist?(test_image_path)
    end
    
    it 'analyzes an image with default model' do
      result = helper.analyze_image(
        message: "What is in this image?",
        image_path: test_image_path
      )
      
      expect(helper.last_command).to include('image_query.rb')
      expect(helper.last_command).to include('What is in this image?')
      expect(helper.last_command).to include(test_image_path)
      expect(helper.last_command).to include('gpt-4.1')
      expect(helper.last_container).to eq('ruby')
      expect(result).to include('Hello World')
    end
    
    it 'analyzes an image with custom model from settings' do
      helper.settings["model"] = "gpt-4o"
      
      result = helper.analyze_image(
        message: "Describe this image",
        image_path: test_image_path,
        model: "gpt-4o"  # This parameter is actually ignored in the implementation
      )
      
      expect(helper.last_command).to include('gpt-4o')
      expect(result).to include('Hello World')
    end
    
    it 'escapes double quotes in message' do
      message_with_quotes = 'What is the "main" content?'
      
      helper.analyze_image(
        message: message_with_quotes,
        image_path: test_image_path
      )
      
      expect(helper.last_command).to include('What is the \\"main\\" content?')
    end
    
    it 'uses check_vision_capability to validate model' do
      # Mock check_vision_capability
      def helper.check_vision_capability(model)
        # Simulate that gpt-3.5 doesn't have vision capability
        model.include?("gpt-4") ? model : nil
      end
      
      helper.settings["model"] = "gpt-3.5-turbo"
      
      helper.analyze_image(
        message: "Test",
        image_path: test_image_path
      )
      
      # Should fall back to gpt-4.1
      expect(helper.last_command).to include('gpt-4.1')
    end
    
    it 'handles empty message' do
      result = helper.analyze_image(
        message: "",
        image_path: test_image_path
      )
      
      expect(helper.last_command).to include('image_query.rb ""')
      expect(result).to be_a(String)
    end
    
    it 'handles special characters in image path' do
      special_path = "/tmp/test image (1).png"
      create_test_image(special_path)
      
      begin
        helper.analyze_image(
          message: "Test",
          image_path: special_path
        )
        
        expect(helper.last_command).to include(special_path)
      ensure
        File.delete(special_path) if File.exist?(special_path)
      end
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
  
  private
  
  def create_test_image(path)
    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(path))
    
    # Create a simple dummy PNG file for testing
    # This is a minimal valid PNG file (1x1 white pixel)
    png_data = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  # PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,  # IDAT chunk
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
      0x00, 0x05, 0xFE, 0x02, 0xFE, 0xDC, 0xCC, 0x59,
      0xE7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,  # IEND chunk
      0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack('C*')
    
    File.binwrite(path, png_data)
  end
end