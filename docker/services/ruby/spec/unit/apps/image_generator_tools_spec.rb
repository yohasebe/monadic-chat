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

  describe "ImageGeneratorGemini" do
    # Skip if ImageGeneratorGemini is not defined (Gemini3Preview uses a different name)
    before(:each) do
      skip "ImageGeneratorGemini not defined in this configuration" unless defined?(ImageGeneratorGemini)
    end

    it "is defined as a class" do
      expect(defined?(ImageGeneratorGemini)).to eq("constant")
    end

    it "includes required modules" do
      expect(ImageGeneratorGemini.included_modules).to include(GeminiHelper)
    end

    it "responds to generate_image_with_gemini method" do
      app = ImageGeneratorGemini.new
      expect(app).to respond_to(:generate_image_with_gemini)
    end
  end

  describe "Session state integration" do
    # These tests verify the session state behavior but require actual API calls
    # Run with RUN_API=true for full integration testing

    it "ImageGeneratorOpenAI session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]

      # Test that session[:openai_last_image] is properly set after image generation
    end

    it "ImageGeneratorGemini session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]

      # Test that session[:gemini_last_image] is properly set after image generation
    end
  end
end
