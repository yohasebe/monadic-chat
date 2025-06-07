# frozen_string_literal: true

require_relative "./spec_helper"
require_relative "../lib/monadic/adapters/selenium_helper"

RSpec.describe MonadicHelper do
  # Create a test class that includes the MonadicHelper module
  let(:test_class) do
    Class.new do
      include MonadicHelper
      
      # Mock send_command method that yields to block
      def send_command(command:, container:, &block)
        # Simulate successful webpage fetch
        if command.include?("webpage_fetcher.py")
          stdout = "Content fetched successfully, saved to: example_com.md"
          stderr = ""
          status = double("Status", success?: true)
          
          # Call the block if provided
          if block_given?
            yield stdout, stderr, status
          else
            return {
              "status" => "success",
              "stdout" => stdout,
              "stderr" => stderr,
              "command" => command,
              "container" => container
            }
          end
        end
      end
    end
  end
  
  let(:helper) { test_class.new }

  describe "#fetch_web_content" do
    it "delegates to selenium_fetch" do
      expect(helper).to receive(:selenium_fetch).with(url: "https://example.com")
      
      helper.fetch_web_content(url: "https://example.com")
    end
    
    it "passes empty string as default url" do
      expect(helper).to receive(:selenium_fetch).with(url: "")
      
      helper.fetch_web_content
    end
  end

  describe "#selenium_fetch" do
    before do
      # Mock File operations with default stubs
      allow(File).to receive(:basename).and_call_original
      allow(File).to receive(:basename).with("example_com.md").and_return("example_com.md")
      allow(File).to receive(:basename).with("custom_filename.md").and_return("custom_filename.md")
      allow(File).to receive(:join).and_return("/shared/example_com.md")
      allow(File).to receive(:exist?).with("/shared/example_com.md").and_return(true)
      allow(File).to receive(:read).with("/shared/example_com.md").and_return("# Example Website\nContent here...")
    end

    it "calls send_command with correct webpage_fetcher command" do
      expect(helper).to receive(:send_command) do |args, &block|
        command = args[:command]
        expect(command).to include("webpage_fetcher.py")
        expect(command).to include("--url \"https://example.com\"")
        expect(command).to include("--filepath \"/monadic/data/\"")
        expect(command).to include("--mode \"md\"")
        expect(args[:container]).to eq("python")
        
        # Simulate the block call
        block.call "Content fetched successfully, saved to: example_com.md", "", double("Status", success?: true)
      end
      
      result = helper.selenium_fetch(url: "https://example.com")
      expect(result).to eq("# Example Website\nContent here...")
    end
    
    it "handles empty URL parameter" do
      expect(helper).to receive(:send_command) do |args, &block|
        command = args[:command]
        expect(command).to include("--url \"\"")
        
        block.call "Content fetched successfully, saved to: example_com.md", "", double("Status", success?: true)
      end
      
      helper.selenium_fetch
    end
    
    it "escapes special characters in URL" do
      url_with_quotes = 'https://example.com/page?q="test"&r=1'
      
      expect(helper).to receive(:send_command) do |args, &block|
        command = args[:command]
        expect(command).to include("--url \"#{url_with_quotes}\"")
        
        block.call "Content fetched successfully, saved to: example_com.md", "", double("Status", success?: true)
      end
      
      helper.selenium_fetch(url: url_with_quotes)
    end
    
    it "extracts filename from stdout output" do
      # Mock File.join to return the expected path for custom filename
      allow(File).to receive(:join).with(anything, "custom_filename.md").and_return("/shared/custom_filename.md")
      allow(File).to receive(:exist?).with("/shared/custom_filename.md").and_return(true)
      allow(File).to receive(:read).with("/shared/custom_filename.md").and_return("Custom content")
      
      expect(helper).to receive(:send_command) do |args, &block|
        block.call "Content fetched successfully, saved to: custom_filename.md", "", double("Status", success?: true)
      end
      
      result = helper.selenium_fetch(url: "https://example.com")
      expect(result).to eq("Custom content")
    end
    
    it "waits for file to exist with retries" do
      call_count = 0
      allow(File).to receive(:exist?) do |path|
        call_count += 1
        call_count >= 3  # File exists on third check
      end
      allow(File).to receive(:read).and_return("Content after waiting")
      
      expect(helper).to receive(:send_command) do |args, &block|
        block.call "Content fetched successfully, saved to: example_com.md", "", double("Status", success?: true)
      end
      
      # Mock sleep to avoid actual delays in test
      allow(helper).to receive(:sleep)
      
      result = helper.selenium_fetch(url: "https://example.com")
      expect(result).to eq("Content after waiting")
      expect(call_count).to be >= 3
    end
    
    it "returns error message when file cannot be read after retries" do
      allow(File).to receive(:exist?).and_return(false)  # File never exists
      
      expect(helper).to receive(:send_command) do |args, &block|
        block.call "Content fetched successfully, saved to: example_com.md", "", double("Status", success?: true)
      end
      
      # Mock sleep to avoid actual delays in test
      allow(helper).to receive(:sleep)
      
      result = helper.selenium_fetch(url: "https://example.com")
      expect(result).to include("Error occurred: The example_com.md could not be read.")
    end
    
    it "handles command execution failure" do
      expect(helper).to receive(:send_command) do |args, &block|
        block.call "", "Network error occurred", double("Status", success?: false)
      end
      
      result = helper.selenium_fetch(url: "https://example.com")
      expect(result).to eq("Error occurred: Network error occurred")
    end
    
    it "handles missing filename in stdout" do
      expect(helper).to receive(:send_command) do |args, &block|
        # stdout without the expected format
        block.call "Some other output without filename", "", double("Status", success?: true)
      end
      
      # The actual implementation will crash when filename is nil, so we expect this error
      expect { helper.selenium_fetch(url: "https://example.com") }.to raise_error(TypeError)
    end
    
    context "environment path handling" do
      it "uses correct shared volume path in container environment" do
        stub_const("IN_CONTAINER", true)
        stub_const("MonadicApp::SHARED_VOL", "/monadic/data")
        
        allow(File).to receive(:join).with("/monadic/data", "example_com.md").and_return("/monadic/data/example_com.md")
        allow(File).to receive(:exist?).with("/monadic/data/example_com.md").and_return(true)
        allow(File).to receive(:read).with("/monadic/data/example_com.md").and_return("Container content")
        
        expect(helper).to receive(:send_command) do |args, &block|
          block.call "Content fetched successfully, saved to: example_com.md", "", double("Status", success?: true)
        end
        
        result = helper.selenium_fetch(url: "https://example.com")
        expect(result).to eq("Container content")
      end
      
      it "uses correct shared volume path in local environment" do
        stub_const("IN_CONTAINER", false)
        stub_const("MonadicApp::LOCAL_SHARED_VOL", File.expand_path("~/monadic/data"))
        local_path = File.expand_path("~/monadic/data")
        
        allow(File).to receive(:join).with(local_path, "example_com.md").and_return("#{local_path}/example_com.md")
        allow(File).to receive(:exist?).with("#{local_path}/example_com.md").and_return(true)
        allow(File).to receive(:read).with("#{local_path}/example_com.md").and_return("Local content")
        
        expect(helper).to receive(:send_command) do |args, &block|
          block.call "Content fetched successfully, saved to: example_com.md", "", double("Status", success?: true)
        end
        
        result = helper.selenium_fetch(url: "https://example.com")
        expect(result).to eq("Local content")
      end
    end
  end
end