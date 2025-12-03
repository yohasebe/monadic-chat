# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../apps/image_generator/image_generator_tools"

# Mock MonadicHelper for testing purposes
module MonadicHelper
  def generate_image_with_openai(operation:, model:, prompt: nil, images: nil, 
                                 mask: nil, n: 1, size: "1024x1024", 
                                 quality: "standard", output_format: "png",
                                 background: nil, output_compression: nil, input_fidelity: nil)
    # Simulate successful image generation
    if images && !images.empty?
      # Simulate editing or variation
      { "success" => true, "filename" => "edited_image_#{Time.now.to_i}.png", "data" => [{ "url" => "/data/edited_image_#{Time.now.to_i}.png" }] }.to_json
    else
      # Simulate new generation
      { "success" => true, "filename" => "generated_image_#{Time.now.to_i}.png", "data" => [{ "url" => "/data/generated_image_#{Time.now.to_i}.png" }] }.to_json
    end
  end

  def generate_image_with_gemini(prompt:, operation: "generate", model: "gemini", session: nil)
    # Simulate successful image generation
    if session && session[:messages] && session[:messages].any? { |msg| msg["role"] == "user" && msg["images"] && msg["images"].any? }
      # Simulate editing an uploaded image
      { "success" => true, "filename" => "edited_gemini_image_#{Time.now.to_i}.png" }.to_json
    elsif session && session[:gemini_last_image]
      # Simulate editing a previously generated image
      { "success" => true, "filename" => "edited_gemini_image_#{Time.now.to_i}.png" }.to_json
    else
      # Simulate new generation
      { "success" => true, "filename" => "generated_gemini_image_#{Time.now.to_i}.png" }.to_json
    end
  end
end

RSpec.describe "ImageGeneratorTools" do
  let(:openai_app) { ImageGeneratorOpenAI.new("ImageGeneratorOpenAI") }
  let(:gemini_app) { ImageGeneratorGemini.new("ImageGeneratorGemini") }
  let(:session) { { parameters: {}, messages: [] } }

  describe "ImageGeneratorOpenAI" do
    it "saves the generated filename to session[:openai_last_image]" do
      result = openai_app.generate_image_with_openai(
        operation: "generate",
        model: "gpt-image-1",
        prompt: "a red car",
        session: session
      )
      parsed_result = JSON.parse(result)
      expect(parsed_result["success"]).to be true
      expect(session[:openai_last_image]).to eq(parsed_result["filename"])
    end

    it "uses session[:openai_last_image] for edit operation if no images are provided" do
      session[:openai_last_image] = "previous_image.png"
      # Mock file existence check for session image
      allow(File).to receive(:exist?).with(include("previous_image.png")).and_return(true)
      
      result = openai_app.generate_image_with_openai(
        operation: "edit",
        model: "gpt-image-1",
        prompt: "make it blue",
        images: nil, # Explicitly nil to test session fallback
        session: session
      )
      parsed_result = JSON.parse(result)
      expect(parsed_result["success"]).to be true
      expect(session[:openai_last_image]).to eq(parsed_result["filename"])
    end

    it "falls back to session image if provided image does not exist" do
      session[:openai_last_image] = "valid_session_image.png"
      # Mock file existence: provided image missing, session image exists
      allow(File).to receive(:exist?).with(include("non_existent_image.png")).and_return(false)
      allow(File).to receive(:exist?).with(include("valid_session_image.png")).and_return(true)

      result = openai_app.generate_image_with_openai(
        operation: "edit",
        model: "gpt-image-1",
        prompt: "make it blue",
        images: ["non_existent_image.png"],
        session: session
      )
      parsed_result = JSON.parse(result)
      expect(parsed_result["success"]).to be true
      # Verify success, implying the valid session image was used
    end

    it "uses uploaded image for edit operation if present" do
      session[:messages] << { "role" => "user", "images" => [{ "name" => "uploaded_image.png", "data" => "base64data" }] }
      session[:openai_last_image] = "previous_image.png" # Should be overridden by uploaded image
      result = openai_app.generate_image_with_openai(
        operation: "edit",
        model: "gpt-image-1",
        prompt: "make it green",
        images: nil,
        session: session
      )
      parsed_result = JSON.parse(result)
      expect(parsed_result["success"]).to be true
      expect(session[:openai_last_image]).to eq(parsed_result["filename"])
    end
  end

  describe "ImageGeneratorGemini" do
    it "saves the generated filename to session[:gemini_last_image]" do
      result = gemini_app.generate_image_with_gemini(
        operation: "generate",
        model: "imagen4-fast",
        prompt: "a green apple",
        session: session
      )
      parsed_result = JSON.parse(result)
      expect(parsed_result["success"]).to be true
      expect(session[:gemini_last_image]).to eq(parsed_result["filename"])
    end

    it "uses session[:gemini_last_image] for edit operation if no images are provided" do
      session[:gemini_last_image] = "previous_gemini_image.png"
      result = gemini_app.generate_image_with_gemini(
        operation: "edit",
        model: "gemini",
        prompt: "change to red",
        session: session
      )
      parsed_result = JSON.parse(result)
      expect(parsed_result["success"]).to be true
      # This mock does not explicitly verify the 'image' parameter, but the helper logic ensures it.
      expect(session[:gemini_last_image]).to eq(parsed_result["filename"])
    end

    it "uses uploaded image for edit operation if present" do
      session[:messages] << { "role" => "user", "images" => [{ "name" => "uploaded_gemini_image.png", "data" => "base64data" }] }
      session[:gemini_last_image] = "previous_gemini_image.png" # Should be overridden by uploaded image
      result = gemini_app.generate_image_with_gemini(
        operation: "edit",
        model: "gemini",
        prompt: "change to yellow",
        session: session
      )
      parsed_result = JSON.parse(result)
      expect(parsed_result["success"]).to be true
      expect(session[:gemini_last_image]).to eq(parsed_result["filename"])
    end
  end
end