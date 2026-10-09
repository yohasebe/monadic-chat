require 'tmpdir'
require 'base64'
require 'shellwords'
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

    it "passes quality and an expanded ratio through the app and shell helper" do
      app = ImageGeneratorGrok.new
      command = nil
      allow(app).to receive(:send_command) do |**args|
        command = Shellwords.split(args[:command])
      end
      app.generate_image_with_grok(prompt: "test", quality: "high", aspect_ratio: "21:9")
      expect(command).not_to be_nil
      expect(command[command.index("-q") + 1]).to eq("high")
      expect(command[command.index("-a") + 1]).to eq("21:9")
    end

    it "rejects invalid aspect_ratio" do
      app = ImageGeneratorGrok.new
      result = app.generate_image_with_grok(operation: "generate", prompt: "test", aspect_ratio: "99:1")
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

    it "ImageGeneratorGemini returns error string with ❌ prefix on error" do
      app = ImageGeneratorGemini.new
      # Trigger ArgumentError via empty prompt
      result = app.generate_image_with_gemini(prompt: "")
      expect(result).to be_a(String)
      expect(result).to start_with("❌")
      expect(result).to include("Image generation failed")
    end
  end

  describe "ImageGeneratorGrok auto-attach" do
    let(:app) { ImageGeneratorGrok.new }
    let(:shared_folder) { @shared_folder }

    around do |example|
      Dir.mktmpdir('image-edit-shared-') do |directory|
        @shared_folder = File.realpath(directory)
        example.run
      end
    end

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared_folder)
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared_folder)
      allow(app).to receive(:send_command).and_return('{"success":true,"images":[]}')
    end

    it "auto-attaches last image from monadic_state for edit" do
      # Create a temp image file (the shared folder may not exist on CI)
      FileUtils.mkdir_p(shared_folder)
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

      # Capture the generator command without calling the external image API.
      result = app.generate_image_with_grok(operation: "edit", prompt: "make it blue", session: session)
      # Should NOT contain "Image file not found" since auto-attach should resolve the image
      expect(result).not_to include("Image file not found")
      expect(app).to have_received(:send_command).with(
        hash_including(command: include(Shellwords.escape(test_image)), container: "ruby")
      )
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

  # Which picture an edit works on. The generator script is replaced by a
  # recorder; the question is which file the app hands it.
  describe "edit target selection" do
    around do |example|
      Dir.mktmpdir("image-edit-target-") do |directory|
        @shared = File.realpath(directory)
        example.run
      end
    end

    let(:png_b64) { "data:image/png;base64,#{Base64.strict_encode64("\x89PNG fake upload")}" }

    def session_for(app_name, upload: true, generated: true)
      File.write(File.join(@shared, "generated_last.png"), "made earlier") if generated
      messages = [{ "role" => "user", "text" => "edit this photo" }]
      messages[0]["images"] = [{ "name" => "my_photo.png", "data" => png_b64 }] if upload
      {
        parameters: { "app_name" => app_name },
        messages: messages,
        monadic_state: generated ? { app_name => { "last_images" => { data: ["generated_last.png"], version: 1 } } } : {}
      }
    end

    def edited_files(app)
      commands = []
      allow(app).to receive(:send_command) do |**args|
        commands << Shellwords.split(args[:command])
        '{"success":true,"images":[]}'
      end
      yield
      commands.flatten.select { |arg| arg.end_with?(".png") }.map { |arg| File.basename(arg) }
    end

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@shared)
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@shared)
    end

    {
      "ImageGeneratorOpenAI" => ->(app, session) { app.generate_image_with_openai(operation: "edit", model: "gpt-image-2", prompt: "add a festival", session: session) },
      "ImageGeneratorGrok" => ->(app, session) { app.generate_image_with_grok(operation: "edit", prompt: "add a festival", session: session) }
    }.each do |app_name, edit|
      context app_name do
        let(:app) { Object.const_get(app_name).new }

        it "edits the photo uploaded in this turn, not the last image it made" do
          session = session_for(app_name)
          files = edited_files(app) { edit.call(app, session) }
          expect(files).to include("my_photo.png")
          expect(files).not_to include("generated_last.png")
        end

        it "edits the last image it made when nothing was uploaded" do
          session = session_for(app_name, upload: false)
          result = nil
          files = edited_files(app) { result = edit.call(app, session) }
          expect(result.to_s).not_to include("no implicit conversion")
          expect(files).to include("generated_last.png")
        end

        it "says so when there is nothing to edit" do
          result = edit.call(app, session_for(app_name, upload: false, generated: false))
          expect(result).to start_with("❌")
          expect(result).to include("Image file not found")
        end
      end
    end
  end
end
