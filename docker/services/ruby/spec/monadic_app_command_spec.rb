# frozen_string_literal: true

require_relative 'spec_helper'
require 'ostruct'
require 'open3'
require 'digest'
require 'tempfile'

# Use our mocked version of MonadicApp instead of the real one
require_relative 'monadic_app_command_mock'

# Common command test helpers
RSpec.shared_examples "command execution" do
  it "returns success message for successful command" do
    allow(subject).to receive(:capture_command).and_return(["", "", mock_status(true)])
    result = subject.send_command(command: "test_command", container: container_type)
    expect(result).to eq("Command has been executed.\n")
  end
  
  it "returns output with success message when command produces output" do
    allow(subject).to receive(:capture_command).and_return(["Command output", "", mock_status(true)])
    result = subject.send_command(
      command: "test_command", 
      container: container_type,
      success: "Success!",
      success_with_output: "Output: "
    )
    expect(result).to eq("Output: Command output")
  end
  
  it "returns error message when command fails" do
    allow(subject).to receive(:capture_command).and_return(["", "Command failed", mock_status(false)])
    result = subject.send_command(command: "test_command", container: container_type)
    expect(result).to include("Error occurred")
  end
  
  it "returns error message when exception occurs" do
    allow(subject).to receive(:capture_command).and_raise(StandardError.new("Test error"))
    result = subject.send_command(command: "test_command", container: container_type)
    expect(result).to include("Error occurred")
  end
  
  it "yields command results to block when block provided" do
    allow(subject).to receive(:capture_command).and_return(["stdout", "stderr", mock_status(true)])
    
    block_result = nil
    subject.send_command(command: "test_command", container: container_type) do |stdout, stderr, status|
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

RSpec.describe MonadicAppTest::MonadicApp do
  # Use the helper from TestHelpers module instead
  
  let(:app) { described_class.new }
  
  describe "#send_command" do
    context "when container is ruby" do
      subject { app }
      let(:container_type) { "ruby" }
      
      it "formats the command for local execution" do
        allow(subject).to receive(:capture_command).and_return(["", "", mock_status(true)])
        
        subject.send_command(command: "echo 'hello'", container: container_type)
        
        expect(subject).to have_received(:capture_command) do |cmd|
          expect(cmd).to include("find")
          expect(cmd).to include("chmod")
          expect(cmd).to include("echo 'hello'")
        end
      end
      
      include_examples "command execution"
    end
    
    context "when container is python" do
      subject { app }
      let(:container_type) { "python" }
      
      it "formats the command for docker execution" do
        allow(subject).to receive(:capture_command).and_return(["", "", mock_status(true)])
        
        subject.send_command(command: "echo 'hello'", container: container_type)
        
        expect(subject).to have_received(:capture_command) do |cmd|
          expect(cmd).to include("docker exec")
          expect(cmd).to include("monadic-chat-python-container")
          expect(cmd).to include("echo 'hello'")
        end
      end
      
      include_examples "command execution"
    end
  end
  
  describe "#run_code and #run_script" do
    before do
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
      allow(Open3).to receive(:capture3).and_return(["command output", "error output", mock_status(true)])
      
      file_double = double('file')
      allow(File).to receive(:open).with(anything, 'a').and_yield(file_double)
      allow(file_double).to receive(:puts)
      
      stdout, stderr, status = described_class.capture_command("echo hello")
      
      expect(Open3).to have_received(:capture3).with("echo hello")
      expect(stdout).to eq("command output")
      expect(stderr).to eq("error output")
      expect(status.success?).to be true
    end
    
    it "returns error when command is nil" do
      stdout, stderr, status = described_class.capture_command(nil)
      
      expect(stdout).to include("Error")
      expect(stderr).to be_nil
      expect(status).to eq(1)
    end
  end
  
  describe ".doc2markdown" do
    before do
      allow(described_class).to receive(:capture_command).and_return(["Markdown content", "", mock_status(true)])
      allow(described_class).to receive(:sleep)
    end
    
    it "converts PDF to markdown" do
      result = described_class.doc2markdown("document.pdf")
      
      expect(described_class).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("pdf2txt.py")
        expect(cmd).to include("document.pdf")
        expect(cmd).to include("--format md")
      end
      expect(result).to eq("Markdown content")
    end
    
    it "handles Office documents by extension" do
      result = described_class.doc2markdown("document.docx")
      
      expect(described_class).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("office2txt.py")
        expect(cmd).to include("document.docx")
      end
      expect(result).to eq("Markdown content")
    end
    
    it "handles other file types" do
      result = described_class.doc2markdown("document.txt")
      
      expect(described_class).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("simple_content_fetcher.py")
        expect(cmd).to include("document.txt")
      end
      expect(result).to eq("Markdown content")
    end
    
    it "returns error message when conversion fails" do
      allow(described_class).to receive(:capture_command).and_return(["", "Conversion failed", mock_status(false)])
      
      result = described_class.doc2markdown("document.pdf")
      
      expect(result).to eq("Conversion failed")
    end
  end
  
  describe ".fetch_webpage" do
    before do
      allow(described_class).to receive(:capture_command).and_return(["Webpage content", "", mock_status(true)])
      allow(described_class).to receive(:sleep)
    end
    
    it "fetches webpage content" do
      result = described_class.fetch_webpage("https://example.com")
      
      expect(described_class).to have_received(:capture_command) do |cmd|
        expect(cmd).to include("webpage_fetcher.py")
        expect(cmd).to include("--url")
        expect(cmd).to include("https://example.com")
      end
      expect(result).to eq("Webpage content")
    end
    
    it "returns error message when fetch fails with output" do
      allow(described_class).to receive(:capture_command).and_return(["Fetch failed", "", mock_status(false)])
      
      result = described_class.fetch_webpage("https://example.com")
      
      expect(result).to eq("Fetch failed")
    end
    
    it "returns error message when fetch fails without output" do
      allow(described_class).to receive(:capture_command).and_return(["", "Error message", mock_status(false)])
      
      result = described_class.fetch_webpage("https://example.com")
      
      expect(result).to eq("Error message")
    end
    
    it "returns message when content is empty" do
      allow(described_class).to receive(:capture_command).and_return(["", "", mock_status(true)])
      
      result = described_class.fetch_webpage("https://example.com")
      
      expect(result).to include("could not be fetched")
    end
  end
end