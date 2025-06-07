# frozen_string_literal: true

require_relative "./spec_helper"
require_relative "../lib/monadic/adapters/image_generation_helper"

RSpec.describe MonadicHelper do
  # Create a test class that includes the MonadicHelper module
  let(:test_class) do
    Class.new do
      include MonadicHelper
      
      # Mock send_command method
      def send_command(command:, container:)
        {
          "status" => "success",
          "response" => "Mock image generation result",
          "command" => command,
          "container" => container
        }
      end
    end
  end
  
  let(:helper) { test_class.new }

  describe "#generate_image_with_openai" do
    it "builds basic command with required parameters" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("image_generator_openai.rb")
        expect(command).to include("-o create")
        expect(command).to include("-m dall-e-3")
        expect(command).to include("-p \"test prompt\"")
        expect(command).to include("-n 1")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_openai(
        operation: "create",
        model: "dall-e-3",
        prompt: "test prompt"
      )
    end
    
    it "includes optional parameters when provided" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("-s \"512x512\"")
        expect(command).to include("-q high")
        expect(command).to include("-f png")
        expect(command).to include("-b white")
        expect(command).to include("--compression 80")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_openai(
        operation: "create",
        model: "dall-e-3",
        prompt: "test prompt",
        size: "512x512",
        quality: "high",
        output_format: "png",
        background: "white",
        output_compression: 80
      )
    end
    
    it "handles single image input" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("-i \"/path/to/image.jpg\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_openai(
        operation: "edit",
        model: "dall-e-2",
        images: "/path/to/image.jpg"
      )
    end
    
    it "handles multiple images" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("-i \"/path/to/image1.jpg\"")
        expect(command).to include("-i \"/path/to/image2.jpg\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_openai(
        operation: "edit",
        model: "dall-e-2",
        images: ["/path/to/image1.jpg", "/path/to/image2.jpg"]
      )
    end
    
    it "includes explicit mask when provided" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("--mask \"/path/to/mask.png\"")
        expect(command).to include("--original-name \"mask.png\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_openai(
        operation: "edit",
        model: "dall-e-2",
        images: "/path/to/image.jpg",
        mask: "/path/to/mask.png"
      )
    end
    
    it "handles edit operation without explicit mask when no mask files found" do
      # Mock constants and file operations for mask detection
      stub_const("IN_CONTAINER", false)
      stub_const("MonadicApp::LOCAL_SHARED_VOL", "/local/shared")
      
      # Mock File and Dir operations to return no mask files
      allow(File).to receive(:basename).with("/path/to/image.jpg").and_return("image.jpg")
      allow(File).to receive(:join).and_call_original
      allow(Dir).to receive(:glob).and_return([])  # No mask files found
      
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        # Should not include mask parameters when no mask files are found
        expect(command).not_to include("--mask")
        expect(command).not_to include("--original-name")
        expect(command).to include("-o edit")
        expect(command).to include("-i \"/path/to/image.jpg\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_openai(
        operation: "edit",
        model: "dall-e-2",
        images: "/path/to/image.jpg"
      )
    end
    
    it "includes quotes in prompt as-is" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("-p \"prompt with \"quotes\"\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_openai(
        operation: "create",
        model: "dall-e-3",
        prompt: 'prompt with "quotes"'
      )
    end
    
    it "calls send_command with ruby container" do
      expect(helper).to receive(:send_command).with(
        command: anything,
        container: "ruby"
      )
      
      helper.generate_image_with_openai(
        operation: "create",
        model: "dall-e-3"
      )
    end
    
    it "returns the result from send_command" do
      result = helper.generate_image_with_openai(
        operation: "create",
        model: "dall-e-3",
        prompt: "test prompt"
      )
      
      expect(result).to be_a(Hash)
      expect(result["status"]).to eq("success")
      expect(result["container"]).to eq("ruby")
    end
  end

  describe "#generate_image_with_grok" do
    it "builds command with prompt" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("image_generator_grok.rb")
        expect(command).to include("-p \"test prompt\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_grok(prompt: "test prompt")
    end
    
    it "handles empty prompt" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("-p \"\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_grok
    end
    
    it "includes quotes in prompt as-is" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("-p \"prompt with \"quotes\"\"")
        
        { "status" => "success" }
      end
      
      helper.generate_image_with_grok(prompt: 'prompt with "quotes"')
    end
    
    it "calls send_command with ruby container" do
      expect(helper).to receive(:send_command).with(
        command: anything,
        container: "ruby"
      )
      
      helper.generate_image_with_grok(prompt: "test prompt")
    end
    
    it "returns the result from send_command directly" do
      result = helper.generate_image_with_grok(prompt: "test prompt")
      
      expect(result).to be_a(Hash)
      expect(result["status"]).to eq("success")
      expect(result["container"]).to eq("ruby")
    end
  end
end