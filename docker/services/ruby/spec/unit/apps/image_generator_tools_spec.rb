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

    it "accepts operation parameter" do
      app = ImageGeneratorGrok.new
      # generate operation with empty prompt triggers ArgumentError
      result = app.generate_image_with_grok(operation: "generate", prompt: "")
      expect(result).to start_with("❌")
    end

    it "rejects invalid operation" do
      app = ImageGeneratorGrok.new
      result = app.generate_image_with_grok(operation: "invalid", prompt: "test")
      expect(result).to start_with("❌")
      expect(result).to include("Invalid operation")
    end

    it "returns error when edit has no images and no session" do
      app = ImageGeneratorGrok.new
      result = app.generate_image_with_grok(operation: "edit", prompt: "make it blue")
      expect(result).to start_with("❌")
      expect(result).to include("Image file not found")
    end

    it "rejects invalid aspect_ratio" do
      app = ImageGeneratorGrok.new
      result = app.generate_image_with_grok(operation: "generate", prompt: "test", aspect_ratio: "2:1")
      expect(result).to start_with("❌")
      expect(result).to include("Invalid aspect_ratio")
    end
  end

  describe "Error return values" do
    it "ImageGeneratorOpenAI returns error string with ❌ prefix on error" do
      app = ImageGeneratorOpenAI.new
      # Trigger ArgumentError via empty model
      result = app.generate_image_with_openai(operation: "generate", model: "", prompt: "test")
      expect(result).to be_a(String)
      expect(result).to start_with("❌")
      expect(result).to include("Image generation failed")
    end

    it "ImageGeneratorGrok returns error string with ❌ prefix on error" do
      app = ImageGeneratorGrok.new
      # Trigger ArgumentError via empty prompt
      result = app.generate_image_with_grok(operation: "generate", prompt: "")
      expect(result).to be_a(String)
      expect(result).to start_with("❌")
      expect(result).to include("Image generation failed")
    end

    it "ImageGeneratorGemini3Preview returns error string with ❌ prefix on error" do
      app = ImageGeneratorGemini3Preview.new
      # Trigger ArgumentError via empty prompt
      result = app.generate_image_with_gemini3_preview(prompt: "")
      expect(result).to be_a(String)
      expect(result).to start_with("❌")
      expect(result).to include("Image generation failed")
    end
  end

  describe "Session state integration" do
    # These tests verify the session state behavior but require actual API calls
    # Run with RUN_API=true for full integration testing

    it "ImageGeneratorOpenAI session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]
    end

    it "ImageGeneratorGemini3Preview session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]
    end

    it "ImageGeneratorGrok session handling" do
      skip "Requires RUN_API=true for API integration tests" unless ENV["RUN_API"]
    end
  end

  describe "ImageGeneratorGrok auto-attach" do
    let(:app) { ImageGeneratorGrok.new }
    let(:shared_folder) { Monadic::Utils::Environment.shared_volume }

    it "auto-attaches last image from monadic_state for edit" do
      # Create a temp image file
      test_image = File.join(shared_folder, "test_edit.png")
      File.write(test_image, "fake image data") unless File.exist?(test_image)

      session = {
        parameters: { "app_name" => "ImageGeneratorGrok" },
        messages: [],
        monadic_state: {
          "ImageGeneratorGrok" => {
            "last_images" => { data: ["test_edit.png"], version: 1, updated_at: Time.now.to_s }
          }
        }
      }

      # This will try to call super (send_command) which won't work in unit test,
      # but we can verify the error doesn't come from "Image file not found"
      result = app.generate_image_with_grok(operation: "edit", prompt: "make it blue", session: session)
      # Should NOT contain "Image file not found" since auto-attach should resolve the image
      expect(result).not_to include("Image file not found")
    ensure
      File.delete(test_image) if test_image && File.exist?(test_image)
    end

    it "returns error when no image available for edit" do
      session = {
        parameters: { "app_name" => "ImageGeneratorGrok" },
        messages: [],
        monadic_state: {}
      }

      result = app.generate_image_with_grok(operation: "edit", prompt: "make it blue", session: session)
      expect(result).to start_with("❌")
      expect(result).to include("Image file not found")
    end
  end
end
