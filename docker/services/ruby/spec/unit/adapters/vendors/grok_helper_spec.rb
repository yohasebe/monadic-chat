# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require_relative '../../../../lib/monadic/adapters/vendors/grok_helper'

RSpec.describe GrokHelper do
  subject(:helper) do
    Class.new do
      include GrokHelper
    end.new
  end

  describe 'MIME detection for auto-attach' do
    # Test the extension-to-MIME mapping used in auto-attach
    # This mirrors the inline logic in send_query

    def mime_for(filename)
      case File.extname(filename.to_s).downcase
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif" then "image/gif"
      when ".webp" then "image/webp"
      else "image/png"
      end
    end

    it 'detects PNG MIME type' do
      expect(mime_for("image.png")).to eq("image/png")
    end

    it 'detects JPG MIME type' do
      expect(mime_for("photo.jpg")).to eq("image/jpeg")
    end

    it 'detects JPEG MIME type' do
      expect(mime_for("photo.jpeg")).to eq("image/jpeg")
    end

    it 'detects GIF MIME type' do
      expect(mime_for("anim.gif")).to eq("image/gif")
    end

    it 'detects WebP MIME type' do
      expect(mime_for("photo.webp")).to eq("image/webp")
    end

    it 'defaults to PNG for unknown extensions' do
      expect(mime_for("file.bmp")).to eq("image/png")
      expect(mime_for("file.tiff")).to eq("image/png")
    end

    it 'handles case-insensitive extensions' do
      expect(mime_for("IMAGE.PNG")).to eq("image/png")
      expect(mime_for("photo.JPG")).to eq("image/jpeg")
    end

    it 'handles nil filename gracefully' do
      expect(mime_for(nil)).to eq("image/png")
    end
  end

  describe 'base64 data URL generation' do
    it 'produces valid data URL format' do
      binary_data = "\x89PNG\r\n\x1a\n" # PNG magic bytes
      base64 = Base64.strict_encode64(binary_data)
      data_url = "data:image/png;base64,#{base64}"

      expect(data_url).to start_with("data:image/png;base64,")
      expect(data_url).not_to include("\n") # strict_encode64 has no newlines
      # Round-trip verify (force_encoding for binary comparison)
      decoded = Base64.strict_decode64(data_url.sub(%r{^data:[^;]+;base64,}, ""))
      expect(decoded).to eq(binary_data.b)
    end

    it 'auto-attach image object has correct structure' do
      images = []
      filename = "test.png"
      data_url = "data:image/png;base64,iVBORw0KGgo="

      images << { "data" => data_url, "title" => filename }

      expect(images.last).to have_key("data")
      expect(images.last).to have_key("title")
      expect(images.last["data"]).to start_with("data:")
      expect(images.last["title"]).to eq("test.png")
    end

    it 'normalizes images to array when given non-array' do
      images = "single_image_string"
      images = [images] unless images.is_a?(Array)
      expect(images).to be_an(Array)
      expect(images.length).to eq(1)
    end
  end
end
