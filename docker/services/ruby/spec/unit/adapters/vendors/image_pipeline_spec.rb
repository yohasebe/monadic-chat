# frozen_string_literal: true

require_relative "../../../spec_helper"
require_relative "../../../../lib/monadic/utils/tool_image_utils"
require "base64"

# Unit tests for _image pipeline in Mistral and Cohere vendor adapters.
# Tests that tool-generated images are correctly collected and formatted
# for injection into the LLM context.
#
# Uses a real (programmatically generated) PNG image to verify Base64 encoding
# and ToolImageUtils integration.

RSpec.describe "Vendor adapter _image pipeline" do
  let(:data_path) { Dir.mktmpdir("monadic_image_pipeline_test") }
  let(:test_png_path) { File.join(data_path, "test_chart.png") }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_path)

    # Create a minimal valid 8x8 red PNG in the test data path
    png_data = create_minimal_png(8, 8, 255, 0, 0)
    File.binwrite(test_png_path, png_data)
  end

  after do
    FileUtils.rm_rf(data_path)
  end

  # Generate a minimal valid PNG file
  def create_minimal_png(width, height, r, g, b)
    require "zlib"
    signature = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*")

    ihdr_data = [width, height, 8, 2, 0, 0, 0].pack("NNC5")
    ihdr_crc = [Zlib.crc32("IHDR" + ihdr_data)].pack("N")
    ihdr = [13].pack("N") + "IHDR" + ihdr_data + ihdr_crc

    raw_data = String.new("", encoding: "BINARY")
    height.times do
      raw_data << "\x00".b
      width.times { raw_data << [r, g, b].pack("CCC") }
    end
    compressed = Zlib::Deflate.deflate(raw_data)
    idat_crc = [Zlib.crc32("IDAT" + compressed)].pack("N")
    idat = [compressed.length].pack("N") + "IDAT" + compressed + idat_crc

    iend_crc = [Zlib.crc32("IEND")].pack("N")
    iend = [0].pack("N") + "IEND" + iend_crc

    signature + ihdr + idat + iend
  end

  describe "ToolImageUtils.encode_image_for_api with real PNG" do
    it "returns valid base64 data for existing PNG" do
      result = Monadic::Utils::ToolImageUtils.encode_image_for_api("test_chart.png")
      expect(result).not_to be_nil
      expect(result[:media_type]).to eq("image/png")
      expect(result[:base64_data]).not_to be_empty

      # Verify round-trip: decode base64 and check PNG signature
      decoded = Base64.strict_decode64(result[:base64_data])
      expect(decoded.bytes[0..3]).to eq([137, 80, 78, 71])
    end

    it "returns nil for non-existent file" do
      result = Monadic::Utils::ToolImageUtils.encode_image_for_api("nonexistent.png")
      expect(result).to be_nil
    end

    it "returns nil for files exceeding size limit" do
      large_path = File.join(data_path, "huge.png")
      File.binwrite(large_path, "x" * (6 * 1024 * 1024))
      result = Monadic::Utils::ToolImageUtils.encode_image_for_api("huge.png")
      expect(result).to be_nil
    end
  end

  describe "Mistral _image message format" do
    it "builds OpenAI-compatible image_url message from _image" do
      # Simulate what Mistral adapter does with pending_tool_images
      pending_tool_images = ["test_chart.png"]

      image_parts = pending_tool_images.filter_map do |img_filename|
        img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
        next unless img
        { "type" => "image_url", "image_url" => { "url" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" } }
      end

      expect(image_parts.size).to eq(1)
      expect(image_parts[0]["type"]).to eq("image_url")

      url = image_parts[0]["image_url"]["url"]
      expect(url).to start_with("data:image/png;base64,")

      # Full user message structure
      user_msg = {
        "role" => "user",
        "content" => [
          { "type" => "text", "text" => "[Tool-generated image. Verify the visual output before presenting results.]" },
          *image_parts
        ]
      }
      expect(user_msg["role"]).to eq("user")
      expect(user_msg["content"].size).to eq(2)
      expect(user_msg["content"][0]["type"]).to eq("text")
      expect(user_msg["content"][1]["type"]).to eq("image_url")
    end

    it "handles multiple images" do
      File.binwrite(File.join(data_path, "chart2.png"), create_minimal_png(4, 4, 0, 255, 0))
      pending_tool_images = ["test_chart.png", "chart2.png"]

      image_parts = pending_tool_images.filter_map do |img_filename|
        img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
        next unless img
        { "type" => "image_url", "image_url" => { "url" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" } }
      end

      expect(image_parts.size).to eq(2)
    end

    it "skips non-existent images gracefully" do
      pending_tool_images = ["test_chart.png", "missing.png"]

      image_parts = pending_tool_images.filter_map do |img_filename|
        img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
        next unless img
        { "type" => "image_url", "image_url" => { "url" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" } }
      end

      expect(image_parts.size).to eq(1)
    end
  end

  describe "Cohere _image message format" do
    it "builds Cohere v2 image message from _image" do
      # Simulate what Cohere adapter does with pending_tool_images
      pending_tool_images = ["test_chart.png"]

      image_parts = pending_tool_images.filter_map do |img_filename|
        img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
        next unless img
        { "type" => "image", "image" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" }
      end

      expect(image_parts.size).to eq(1)
      expect(image_parts[0]["type"]).to eq("image")
      expect(image_parts[0]["image"]).to start_with("data:image/png;base64,")

      # Full user message structure (Cohere v2 format)
      user_msg = {
        "role" => "user",
        "content" => [
          { "type" => "text", "text" => "[Tool-generated image. Verify the visual output before presenting results.]" },
          *image_parts
        ]
      }
      expect(user_msg["role"]).to eq("user")
      expect(user_msg["content"].size).to eq(2)
      expect(user_msg["content"][0]["type"]).to eq("text")
      expect(user_msg["content"][1]["type"]).to eq("image")
    end

    it "produces different format from Mistral (image vs image_url)" do
      img = Monadic::Utils::ToolImageUtils.encode_image_for_api("test_chart.png")

      mistral_part = { "type" => "image_url", "image_url" => { "url" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" } }
      cohere_part = { "type" => "image", "image" => "data:#{img[:media_type]};base64,#{img[:base64_data]}" }

      # Mistral uses nested image_url.url, Cohere uses flat image string
      expect(mistral_part["type"]).to eq("image_url")
      expect(cohere_part["type"]).to eq("image")
      expect(mistral_part).to have_key("image_url")
      expect(cohere_part).not_to have_key("image_url")
    end
  end

  describe "_image collection from function_return" do
    let(:function_return_with_image) do
      { text: "Code executed successfully\n/data/test_chart.png", _image: ["test_chart.png"] }
    end

    let(:function_return_without_image) do
      "Code executed successfully. No images."
    end

    it "extracts _image from Hash return and cleans underscore keys" do
      fr = function_return_with_image
      expect(fr[:_image]).to eq(["test_chart.png"])

      clean_return = fr.reject { |k, _| k.to_s.start_with?("_") }
      expect(clean_return).to eq({ text: "Code executed successfully\n/data/test_chart.png" })
      expect(clean_return).not_to have_key(:_image)
    end

    it "does not modify String return" do
      fr = function_return_without_image
      expect(fr).to be_a(String)
      # No _image extraction from strings
    end

    it "handles Array of images in _image" do
      fr = { text: "Generated plots", _image: ["test_chart.png", "chart2.png"] }
      images = Array(fr[:_image])
      expect(images.size).to eq(2)
    end

    it "handles single String in _image" do
      fr = { text: "Generated plot", _image: "test_chart.png" }
      images = Array(fr[:_image])
      expect(images).to eq(["test_chart.png"])
    end
  end
end
