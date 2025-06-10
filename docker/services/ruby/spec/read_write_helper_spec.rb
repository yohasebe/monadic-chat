# frozen_string_literal: true

require_relative 'spec_helper'
require 'open3'

# Include the module to test
require_relative '../lib/monadic/adapters/read_write_helper'

# Create a test class that includes the module
module ReadWriteHelperTest
  class TestHelper
    include MonadicHelper
    
    # Mock send_command to avoid actual command execution
    def send_command(command:, container:, success: "", success_with_output: "")
      case command
      when /office2txt\.py/
        if command.include?("empty.docx")
          ""
        elsif command.include?("error.docx")
          "Error message from office2txt"
        else
          "Office document content"
        end
      when /pdf2txt\.py/
        if command.include?("empty.pdf")
          ""
        elsif command.include?("error.pdf")
          "Error message from pdf2txt"
        else
          "PDF document content"
        end
      when /content_fetcher\.rb/
        if command.include?("empty.txt")
          ""
        elsif command.include?("error.txt")
          "Error message from content_fetcher"
        else
          "Text file content"
        end
      else
        "Unknown command"
      end
    end
  end
end

RSpec.describe MonadicHelper do
  # Set up the test environment
  before(:all) do
    # Create data directory if it doesn't exist
    data_dir = File.expand_path(File.join(Dir.home, "monadic", "data"))
    FileUtils.mkdir_p(data_dir) unless Dir.exist?(data_dir)
  end
  
  let(:helper) { ReadWriteHelperTest::TestHelper.new }
  
  describe "#fetch_text_from_office" do
    it "returns content from an office document" do
      result = helper.fetch_text_from_office(file: "test.docx")
      expect(result).to eq("Office document content")
    end
    
    it "returns error message for empty files" do
      result = helper.fetch_text_from_office(file: "empty.docx")
      expect(result).to include("Error")
      expect(result).to include("empty")
    end
    
    it "handles error messages from command execution" do
      result = helper.fetch_text_from_office(file: "error.docx")
      expect(result).to eq("Error message from office2txt")
    end
  end
  
  describe "#fetch_text_from_pdf" do
    it "returns content from a PDF document" do
      result = helper.fetch_text_from_pdf(pdf: "test.pdf")
      expect(result).to eq("PDF document content")
    end
    
    it "returns error message for empty files" do
      result = helper.fetch_text_from_pdf(pdf: "empty.pdf")
      expect(result).to include("Error")
      expect(result).to include("empty")
    end
    
    it "handles error messages from command execution" do
      result = helper.fetch_text_from_pdf(pdf: "error.pdf")
      expect(result).to eq("Error message from pdf2txt")
    end
  end
  
  describe "#fetch_text_from_file" do
    it "returns content from a text file" do
      result = helper.fetch_text_from_file(file: "test.txt")
      expect(result).to eq("Text file content")
    end
    
    it "returns error message for empty files" do
      result = helper.fetch_text_from_file(file: "empty.txt")
      expect(result).to include("Error")
      expect(result).to include("empty")
    end
    
    it "handles error messages from command execution" do
      result = helper.fetch_text_from_file(file: "error.txt")
      expect(result).to eq("Error message from content_fetcher")
    end
  end
  
  describe "#write_to_file" do
    before do
      # Mock File operations
      allow(File).to receive(:join).and_call_original
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:open).and_yield(StringIO.new)
      
      # Mock Sleep to speed up tests
      allow_any_instance_of(ReadWriteHelperTest::TestHelper).to receive(:sleep)
    end
    
    context "when not in container" do
      before do
        stub_const("IN_CONTAINER", false)
      end
      
      it "writes content to a file" do
        result = helper.write_to_file(
          filename: "test",
          extension: "txt",
          text: "Hello, world!"
        )
        
        expect(result).to include("has been written successfully")
        expect(result).to include("test.txt")
      end
      
      it "handles file access errors" do
        allow(File).to receive(:open).and_raise(StandardError.new("Permission denied"))
        
        result = helper.write_to_file(
          filename: "error",
          extension: "txt",
          text: "This will fail"
        )
        
        expect(result).to include("Error")
        expect(result).to include("could not be executed")
        expect(result).to include("Permission denied")
      end
      
      it "handles file existence check failures" do
        allow(File).to receive(:exist?).and_return(false)
        
        result = helper.write_to_file(
          filename: "missing",
          extension: "txt",
          text: "This will not be found"
        )
        
        expect(result).to include("Error")
        expect(result).to include("could not be written")
      end
    end
    
    context "when in container" do
      before do
        stub_const("IN_CONTAINER", true)
        
        # Mock Open3.capture3
        allow(Open3).to receive(:capture3).and_return(["", "", OpenStruct.new(exitstatus: 0)])
      end
      
      it "copies the file to the container" do
        result = helper.write_to_file(
          filename: "container_test",
          extension: "txt",
          text: "Hello from container!"
        )
        
        expect(Open3).to have_received(:capture3) do |cmd|
          expect(cmd).to include("docker cp")
          expect(cmd).to include("container_test.txt")
          expect(cmd).to include("monadic-chat-python-container")
        end
        
        expect(result).to include("has been written successfully")
        expect(result).to include("container_test.txt")
      end
      
      it "handles docker copy errors" do
        allow(Open3).to receive(:capture3).and_return(["", "Docker error", OpenStruct.new(exitstatus: 1)])
        
        result = helper.write_to_file(
          filename: "docker_error",
          extension: "txt",
          text: "This will fail"
        )
        
        expect(result).to include("Error")
        expect(result).to include("Docker error")
      end
    end
  end
end