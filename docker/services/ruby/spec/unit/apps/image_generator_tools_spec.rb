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
    around do |example|
      Dir.mktmpdir("grok-tool-") do |directory|
        @grok_root = File.realpath(directory)
        Dir.mkdir(File.join(@grok_root, "state"))
        example.run
      end
    end

    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@grok_root)
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@grok_root)
      allow(Monadic::Workbench::Store).to receive(:default)
        .and_return(Monadic::Workbench::Store.new(File.join(@grok_root, "state", "workbench")))
    end

    # The chat the reply runs for, as the server gives it.
    def grok_workbench
      Monadic::Workbench::Caller.new(chat_id: Monadic::Workspace::Ids.generate(:chat), epoch: 0, request_id: "q1",
                                     session: { messages: [] })
    end

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

    it "refuses without the reply's chat" do
      app = ImageGeneratorGrok.new
      result = app.generate_image_with_grok(operation: "edit", prompt: "make it blue")
      expect(result).to start_with("❌")
      expect(result).to include("could not be identified")
    end

    it "passes quality and an expanded ratio through the app and shell helper" do
      app = ImageGeneratorGrok.new
      command = nil
      allow(app).to receive(:send_command) do |**args|
        command = Shellwords.split(args[:command])
      end
      app.generate_image_with_grok(prompt: "test", quality: "high", aspect_ratio: "21:9", workbench: grok_workbench)
      expect(command).not_to be_nil
      expect(command[command.index("-q") + 1]).to eq("high")
      expect(command[command.index("-a") + 1]).to eq("21:9")
    end

    it "rejects invalid aspect_ratio" do
      app = ImageGeneratorGrok.new
      result = app.generate_image_with_grok(operation: "generate", prompt: "test", aspect_ratio: "99:1",
                                            workbench: grok_workbench)
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

  # Which picture an edit works on. The generator script is replaced by a
  # recorder; the question is which file the app hands it.
  describe "edit target selection" do
    around do |example|
      Dir.mktmpdir("image-edit-target-") do |directory|
        @shared = File.realpath(directory)
        Dir.mkdir(File.join(@shared, "state"))
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
      allow(Monadic::Workbench::Store).to receive(:default)
        .and_return(Monadic::Workbench::Store.new(File.join(@shared, "state", "workbench")))
    end

    {
      "ImageGeneratorOpenAI" => lambda { |app, session|
        app.generate_image_with_openai(operation: "edit", model: "gpt-image-2", prompt: "add a festival", session: session,
                                       # The chat the reply runs for, as the server gives it.
                                       workbench: Monadic::Workbench::Caller.new(
                                         chat_id: Monadic::Workspace::Ids.generate(:chat), epoch: 0,
                                         request_id: "q1", session: session
                                       ))
      },
      "ImageGeneratorGrok" => lambda { |app, session|
        app.generate_image_with_grok(operation: "edit", prompt: "add a festival", session: session,
                                     workbench: Monadic::Workbench::Caller.new(
                                       chat_id: Monadic::Workspace::Ids.generate(:chat), epoch: 0,
                                       request_id: "q1", session: session
                                     ))
      }
    }.each do |app_name, edit|
      context app_name do
        let(:app) { Object.const_get(app_name).new }

        it "edits the photo uploaded in this turn, not the last image it made" do
          session = session_for(app_name)
          files = edited_files(app) { edit.call(app, session) }
          expect(files).to include("my_photo.png")
          expect(files).not_to include("generated_last.png")
        end

      end
    end
  end
end
