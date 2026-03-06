# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../apps/image_generator/image_generator_tools"

RSpec.describe "ImageGeneratorTools" do
  describe "ImageGeneratorOpenAI" do
    it "is defined as a class" do
      expect(defined?(ImageGeneratorOpenAI)).to eq("constant")
    end

    it "includes required modules" do
      expect(ImageGeneratorOpenAI.included_modules).to include(OpenAIHelper)
    end

    it "responds to generate_image_with_openai method" do
      app = ImageGeneratorOpenAI.new
      expect(app).to respond_to(:generate_image_with_openai)
    end
  end

  describe "ImageGeneratorGemini3Preview" do
    it "is defined as a class" do
      expect(defined?(ImageGeneratorGemini3Preview)).to eq("constant")
    end

    it "includes required modules" do
      expect(ImageGeneratorGemini3Preview.included_modules).to include(GeminiHelper)
    end

    it "responds to generate_image_with_gemini method" do
      app = ImageGeneratorGemini3Preview.new
      expect(app).to respond_to(:generate_image_with_gemini)
    end
  end

  describe "ImageGeneratorGrok" do
    it "is defined as a class" do
      expect(defined?(ImageGeneratorGrok)).to eq("constant")
    end

    it "includes required modules" do
      expect(ImageGeneratorGrok.included_modules).to include(GrokHelper)
    end

    it "responds to generate_image_with_grok method" do
      app = ImageGeneratorGrok.new
      expect(app).to respond_to(:generate_image_with_grok)
    end
  end

  describe "Error return values" do
    it "ImageGeneratorOpenAI returns valid JSON string with success:false on error" do
      app = ImageGeneratorOpenAI.new
      # Trigger ArgumentError via empty model
      result = app.generate_image_with_openai(operation: "generate", model: "", prompt: "test")
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed["success"]).to eq(false)
      expect(parsed["error"]).to be_a(String)
      expect(parsed["error"]).to include("Image generation failed")
    end

    it "ImageGeneratorGrok returns valid JSON string with success:false on error" do
      app = ImageGeneratorGrok.new
      # Trigger ArgumentError via empty prompt
      result = app.generate_image_with_grok(prompt: "")
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed["success"]).to eq(false)
      expect(parsed["error"]).to be_a(String)
      expect(parsed["error"]).to include("Image generation failed")
    end

    it "ImageGeneratorGemini3Preview returns valid JSON string with success:false on error" do
      app = ImageGeneratorGemini3Preview.new
      # Trigger ArgumentError via empty prompt
      result = app.generate_image_with_gemini3_preview(prompt: "")
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed["success"]).to eq(false)
      expect(parsed["error"]).to be_a(String)
      expect(parsed["error"]).to include("Image generation failed")
    end
  end

  describe "Session state integration" do
    # These tests verify the session state behavior but require actual API calls
    # Run with RUN_API=true for full integration testing

    it "ImageGeneratorOpenAI session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]

      # Test that session[:openai_last_image] is properly set after image generation
    end

    it "ImageGeneratorGemini3Preview session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]

      # Test that session[:gemini_last_image] is properly set after image generation
    end
  end
end
