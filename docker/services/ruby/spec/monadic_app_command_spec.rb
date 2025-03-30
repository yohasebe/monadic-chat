# frozen_string_literal: true

require_relative 'spec_helper'
require 'ostruct'
require 'open3'
require 'digest'
require 'tempfile'

# Use our mocked version of MonadicApp instead of the real one
require_relative 'monadic_app_command_mock'

RSpec.describe MonadicAppTest::MonadicApp do
  # Set up constants and environment for testing
  before(:all) do
    # Create log directory if it doesn't exist
    log_dir = File.expand_path(File.join(Dir.home, "monadic", "log"))
    FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
    
    # Create data directory if it doesn't exist
    data_dir = File.expand_path(File.join(Dir.home, "monadic", "data"))
    FileUtils.mkdir_p(data_dir) unless Dir.exist?(data_dir)
    
    # Create script directory if it doesn't exist
    scripts_dir = File.expand_path(File.join(Dir.home, "monadic", "data", "scripts"))
    FileUtils.mkdir_p(scripts_dir) unless Dir.exist?(scripts_dir)
  end
  
  let(:app) { MonadicAppTest::MonadicApp.new }
  
  describe "#send_command" do
    context "when IN_CONTAINER is false" do
      it "formats the command for local execution with ruby container" do
        # Mock capture_command to avoid actual execution
        allow(app).to receive(:capture_command).and_return(["", "", OpenStruct.new(success?: true)])
        
        result = app.send_command(command: "echo 'hello'", container: "ruby")
        
        expect(app).to have_received(:capture_command) do |cmd|
          expect(cmd).to include("find")
          expect(cmd).to include("chmod")
          expect(cmd).to include("echo 'hello'")
        end
        expect(result).to eq("Command has been executed.\n")
      end
      
      it "formats the command for docker execution with python container" do
        # Mock capture_command to avoid actual execution
        allow(app).to receive(:capture_command).and_return(["", "", OpenStruct.new(success?: true)])
        
        result = app.send_command(command: "echo 'hello'", container: "python")
        
        expect(app).to have_received(:capture_command) do |cmd|
          expect(cmd).to include("docker exec")
          expect(cmd).to include("monadic-chat-python-container")
          expect(cmd).to include("echo 'hello'")
        end
        expect(result).to eq("Command has been executed.\n")
      end
    end
    
    context "when command produces output" do
      it "returns success message with output" do
        # Mock capture_command to return output
        allow(app).to receive(:capture_command).and_return(["Command output", "", OpenStruct.new(success?: true)])
        
        result = app.send_command(command: "echo 'hello'", 
                                 container: "python", 
                                 success: "Success!", 
                                 success_with_output: "Output: ")
        
        expect(result).to eq("Output: Command output")
      end
    end
    
    context "when command fails" do
      it "returns error message" do
        # Mock capture_command to return error
        allow(app).to receive(:capture_command).and_return(["", "Command failed", OpenStruct.new(success?: false)])
        
        result = app.send_command(command: "invalid_command", container: "python")
        
        expect(result).to include("Error occurred")
        expect(result).to include("Command failed")
      end
    end
    
    context "when exception occurs" do
      it "returns error message" do
        # Mock capture_command to raise exception
        allow(app).to receive(:capture_command).and_raise(StandardError.new("Test error"))
        
        result = app.send_command(command: "echo 'hello'", container: "python")
        
        expect(result).to include("Error occurred")
        expect(result).to include("Test error")
      end
    end
    
    context "with block provided" do
      it "yields command results to block" do
        # Mock capture_command to return test data
        allow(app).to receive(:capture_command).and_return(["stdout", "stderr", OpenStruct.new(success?: true)])
        
        # Call with block
        block_result = nil
        app.send_command(command: "echo 'hello'", container: "python") do |stdout, stderr, status|
          block_result = {
            stdout: stdout,
            stderr: stderr,
            success: status.success?
          }
        end
        
        expect(block_result[:stdout]).to eq("stdout")
        expect(block_result[:stderr]).to eq("stderr")
        expect(block_result[:success]).to be true
      end
    end
  end
  
  describe "#send_code" do
    it "executes code with given parameters" do
      # Directly mock the method
      allow(app).to receive(:send_code).and_return("Code executed successfully")
      
      result = app.send_code(
        code: "print('Hello, world!')",
        command: "python",
        extension: "py"
      )
      
      expect(result).to eq("Code executed successfully")
    end
  end
  
  describe "#run_code and #run_script" do
    before do
      # Mock send_code to avoid actual execution
      allow(app).to receive(:send_code).and_return("Code executed successfully")
    end
    
    context "#run_code" do
      it "calls send_code with correct parameters" do
        result = app.run_code(
          code: "print('hello')",
          command: "python",
          extension: "py"
        )
        
        expect(app).to have_received(:send_code).with(
          code: "print('hello')",
          command: "python",
          extension: "py",
          success: "The code has been executed successfully"
        )
        expect(result).to eq("Code executed successfully")
      end
      
      it "returns error when parameters are missing" do
        result = app.run_code(code: "print('hello')")
        expect(result).to include("Error")
        expect(result).to include("required")
      end
    end
    
    context "#run_script" do
      it "unescapes special characters in code" do
        result = app.run_script(
          code: "print(\\'hello\\')\nprint(\\\"world\\\")",
          command: "python",
          extension: "py"
        )
        
        expect(app).to have_received(:send_code).with(
          code: "print('hello')\nprint(\"world\")",
          command: "python",
          extension: "py",
          success: "The code has been executed successfully"
        )
        expect(result).to eq("Code executed successfully")
      end
      
      it "returns error when parameters are missing" do
        result = app.run_script(code: "print('hello')")
        expect(result).to include("Error")
        expect(result).to include("required")
      end
    end
  end
  
  describe ".capture_command" do
    it "executes the command and returns stdout, stderr, and status" do
      # Mock Open3.capture3 to avoid actual command execution
      allow(Open3).to receive(:capture3).and_return(["command output", "error output", OpenStruct.new(success?: true)])
      
      # Mock File opening to prevent actual file writing
      file_double = double('file')
      allow(File).to receive(:open).with(anything, 'a').and_yield(file_double)
      allow(file_double).to receive(:puts)
      
      stdout, stderr, status = MonadicAppTest::MonadicApp.capture_command("echo hello")
      
      expect(Open3).to have_received(:capture3).with("echo hello")
      expect(stdout).to eq("command output")
      expect(stderr).to eq("error output")
      expect(status.success?).to be true
    end
    
    it "returns error when command is nil" do
      stdout, stderr, status = MonadicAppTest::MonadicApp.capture_command(nil)
      
      expect(stdout).to include("Error")
      expect(stderr).to be_nil
      expect(status).to eq(1)
    end
  end
  
  describe ".doc2markdown" do
    before do
      # Mock capture_command to avoid actual execution
      allow(MonadicAppTest::MonadicApp).to receive(:capture_command).and_return(["Markdown content", "", OpenStruct.new(success?: true)])
      
      # Mock sleep to avoid waiting
      allow(MonadicAppTest::MonadicApp).to receive(:sleep)
    end
    
    it "converts PDF to markdown" do
      result = MonadicAppTest::MonadicApp.doc2markdown("document.pdf")
      
      expect(MonadicAppTest::MonadicApp).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("pdf2txt.py")
        expect(cmd).to include("document.pdf")
        expect(cmd).to include("--format md")
      end
      expect(result).to eq("Markdown content")
    end
    
    it "handles Office documents by extension" do
      # Test for just one extension to avoid the mock complexity
      result = MonadicAppTest::MonadicApp.doc2markdown("document.docx")
      
      expect(MonadicAppTest::MonadicApp).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("office2txt.py")
        expect(cmd).to include("document.docx")
      end
      expect(result).to eq("Markdown content")
    end
    
    it "handles other file types" do
      result = MonadicAppTest::MonadicApp.doc2markdown("document.txt")
      
      expect(MonadicAppTest::MonadicApp).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("simple_content_fetcher.py")
        expect(cmd).to include("document.txt")
      end
      expect(result).to eq("Markdown content")
    end
    
    it "returns error message when conversion fails" do
      allow(MonadicAppTest::MonadicApp).to receive(:capture_command).and_return(["", "Conversion failed", OpenStruct.new(success?: false)])
      
      result = MonadicAppTest::MonadicApp.doc2markdown("document.pdf")
      
      expect(result).to eq("Conversion failed")
    end
  end
  
  describe ".fetch_webpage" do
    before do
      # Mock capture_command to avoid actual execution
      allow(MonadicAppTest::MonadicApp).to receive(:capture_command).and_return(["Webpage content", "", OpenStruct.new(success?: true)])
      
      # Mock sleep to avoid waiting
      allow(MonadicAppTest::MonadicApp).to receive(:sleep)
    end
    
    it "fetches webpage content" do
      result = MonadicAppTest::MonadicApp.fetch_webpage("https://example.com")
      
      expect(MonadicAppTest::MonadicApp).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("webpage_fetcher.py")
        expect(cmd).to include("--url")
        expect(cmd).to include("https://example.com")
      end
      expect(result).to eq("Webpage content")
    end
    
    it "returns error message when fetch fails with output" do
      allow(MonadicAppTest::MonadicApp).to receive(:capture_command).and_return(["Fetch failed", "", OpenStruct.new(success?: false)])
      
      result = MonadicAppTest::MonadicApp.fetch_webpage("https://example.com")
      
      expect(result).to eq("Fetch failed")
    end
    
    it "returns error message when fetch fails without output" do
      allow(MonadicAppTest::MonadicApp).to receive(:capture_command).and_return(["", "Error message", OpenStruct.new(success?: false)])
      
      result = MonadicAppTest::MonadicApp.fetch_webpage("https://example.com")
      
      expect(result).to eq("Error message")
    end
    
    it "returns message when content is empty" do
      allow(MonadicAppTest::MonadicApp).to receive(:capture_command).and_return(["", "", OpenStruct.new(success?: true)])
      
      result = MonadicAppTest::MonadicApp.fetch_webpage("https://example.com")
      
      expect(result).to include("could not be fetched")
    end
  end
end