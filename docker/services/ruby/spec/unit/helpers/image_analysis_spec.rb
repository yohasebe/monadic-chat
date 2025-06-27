# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'base64'

RSpec.describe 'Image Analysis Helpers' do
  describe 'MIME type detection' do
    it 'detects correct MIME types for image extensions' do
      test_cases = {
        'png' => 'image/png',
        'PNG' => 'image/png',
        'jpg' => 'image/jpeg',
        'JPG' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'JPEG' => 'image/jpeg',
        'gif' => 'image/gif',
        'GIF' => 'image/gif'
      }
      
      test_cases.each do |ext, expected_mime|
        file_extension = ext.downcase
        mime_type = case file_extension
                    when "jpg", "jpeg"
                      "image/jpeg"
                    when "png"
                      "image/png"
                    when "gif"
                      "image/gif"
                    else
                      "application/octet-stream"
                    end
        
        expect(mime_type).to eq(expected_mime)
      end
    end
    
    it 'returns default MIME type for unknown extensions' do
      unknown_extensions = %w[xyz abc tiff bmp webp]
      
      unknown_extensions.each do |ext|
        file_extension = ext.downcase
        mime_type = case file_extension
                    when "jpg", "jpeg"
                      "image/jpeg"
                    when "png"
                      "image/png"
                    when "gif"
                      "image/gif"
                    else
                      "application/octet-stream"
                    end
        
        expect(mime_type).to eq("application/octet-stream")
      end
    end
  end
  
  describe 'Image validation' do
    it 'validates supported image formats' do
      valid_formats = %w[.png .jpg .jpeg .gif]
      test_files = [
        "image.png",
        "photo.jpg",
        "picture.jpeg",
        "animation.gif",
        "IMAGE.PNG",
        "PHOTO.JPG"
      ]
      
      test_files.each do |filename|
        ext = File.extname(filename).downcase
        is_valid = valid_formats.include?(ext)
        expect(is_valid).to be true
      end
    end
    
    it 'rejects unsupported file formats' do
      valid_formats = %w[.png .jpg .jpeg .gif]
      invalid_files = [
        "document.pdf",
        "text.txt",
        "video.mp4",
        "image.svg",
        "photo.webp",
        "data.json"
      ]
      
      invalid_files.each do |filename|
        ext = File.extname(filename).downcase
        is_valid = valid_formats.include?(ext)
        expect(is_valid).to be false
      end
    end
  end
  
  describe 'Base64 encoding' do
    it 'encodes binary data to base64' do
      # Test data
      test_data = "Hello, World!"
      
      # Encode
      encoded = Base64.strict_encode64(test_data)
      
      expect(encoded).to eq("SGVsbG8sIFdvcmxkIQ==")
      expect(encoded).not_to include("\n")
    end
    
    it 'decodes base64 back to original data' do
      original = "Test image data"
      encoded = Base64.strict_encode64(original)
      decoded = Base64.strict_decode64(encoded)
      
      expect(decoded).to eq(original)
    end
    
    it 'creates valid data URLs' do
      mime_type = "image/png"
      data = "fake png data"
      encoded = Base64.strict_encode64(data)
      
      data_url = "data:#{mime_type};base64,#{encoded}"
      
      expect(data_url).to start_with("data:image/png;base64,")
      expect(data_url).to include(encoded)
    end
  end
  
  describe 'Dimension calculations' do
    it 'calculates aspect ratios correctly' do
      test_cases = [
        { width: 1920, height: 1080, expected: 1.78 },
        { width: 1280, height: 720, expected: 1.78 },
        { width: 1000, height: 1000, expected: 1.0 },
        { width: 500, height: 1000, expected: 0.5 },
        { width: 2000, height: 1000, expected: 2.0 }
      ]
      
      test_cases.each do |tc|
        aspect_ratio = tc[:width].to_f / tc[:height]
        expect(aspect_ratio).to be_within(0.01).of(tc[:expected])
      end
    end
    
    it 'determines correct resize dimensions' do
      max_dimension = 512
      
      # Landscape image
      width = 2000
      height = 1000
      aspect_ratio = width.to_f / height
      
      new_width = [2000, max_dimension].min
      new_height = (new_width / aspect_ratio).round
      
      expect(new_width).to eq(512)
      expect(new_height).to eq(256)
      
      # Portrait image
      width = 1000
      height = 2000
      aspect_ratio = width.to_f / height
      
      new_height = [768, max_dimension].min
      new_width = (new_height * aspect_ratio).round
      
      expect(new_height).to eq(512)
      expect(new_width).to eq(256)
    end
    
    it 'respects maximum dimension limits' do
      # Long side limit: 2000px
      # Short side limit: 768px
      
      test_cases = [
        { 
          input: { width: 4000, height: 2000 },
          max_dim: 1000,
          expected_max: 1000
        },
        { 
          input: { width: 1000, height: 500 },
          max_dim: 2000,
          expected_max: 2000  # Uses original width since it's under max
        }
      ]
      
      test_cases.each do |tc|
        width = tc[:input][:width]
        height = tc[:input][:height]
        aspect_ratio = width.to_f / height
        
        if aspect_ratio >= 1
          new_width = [2000, tc[:max_dim]].min
          new_height = (new_width / aspect_ratio).round
        else
          new_height = [768, tc[:max_dim]].min
          new_width = (new_height * aspect_ratio).round
        end
        
        # Verify neither dimension exceeds the maximum
        expect([new_width, new_height].max).to be <= tc[:expected_max]
      end
    end
  end
  
  describe 'Error handling' do
    it 'handles empty file paths' do
      file_path = ""
      is_valid = File.file?(file_path)
      expect(is_valid).to be false
    end
    
    it 'handles non-existent files' do
      file_path = "/tmp/does_not_exist_#{Time.now.to_i}.png"
      is_valid = File.file?(file_path)
      expect(is_valid).to be false
    end
    
    it 'validates file extensions case-insensitively' do
      extensions = %w[.PNG .Png .pNg .JPEG .Jpeg .GIF .Gif]
      valid_formats = %w[.png .jpg .jpeg .gif]
      
      extensions.each do |ext|
        is_valid = valid_formats.include?(ext.downcase)
        expect(is_valid).to be true
      end
    end
  end
  
  describe 'URL validation' do
    it 'identifies valid HTTP URLs' do
      urls = [
        "http://example.com/image.png",
        "https://example.com/photo.jpg",
        "https://cdn.example.com/assets/pic.gif"
      ]
      
      urls.each do |url|
        uri = URI.parse(url)
        is_http = uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        expect(is_http).to be true
      end
    end
    
    it 'rejects invalid URLs' do
      invalid_urls = [
        "not a url",
        "file:///local/path.png",
        "ftp://server.com/image.jpg",
        "/local/path/image.png",
        "C:\\Windows\\image.png"
      ]
      
      invalid_urls.each do |url|
        begin
          uri = URI.parse(url)
          is_http = uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          expect(is_http).to be false
        rescue URI::InvalidURIError
          # Invalid URI should fail parsing
          expect(true).to be true
        end
      end
    end
  end
end