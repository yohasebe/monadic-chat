# frozen_string_literal: true

require_relative '../spec_helper'
require 'tempfile'
require 'fileutils'
require 'open3'
require 'ostruct'

# Define MonadicApp module with constants before requiring helper
module MonadicApp
  SHARED_VOL = "/monadic/data"
  LOCAL_SHARED_VOL = File.join(Dir.home, "monadic", "data")
end

require_relative '../../lib/monadic/adapters/read_write_helper'

RSpec.describe "ReadWriteHelper with real file operations", type: :integration do
  
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include MonadicHelper
      
      # We'll still need to handle send_command, but we'll use real files
      def send_command(command:, container:, success: "", success_with_output: "")
        # For testing, we'll simulate the command execution
        # In real usage, this would execute actual Python/Ruby scripts
        
        if command.include?("office2txt.py")
          file_path = command.match(/"([^"]+)"/)[1]
          if File.exist?(file_path)
            content = File.read(file_path)
            return content.empty? ? "" : "Converted: #{content}"
          else
            return "Error: File not found"
          end
        elsif command.include?("pdf2txt.py")
          file_path = command.match(/"([^"]+)"/)[1]
          if File.exist?(file_path)
            content = File.read(file_path)
            return content.empty? ? "" : "PDF content: #{content}"
          else
            return "Error: File not found"
          end
        elsif command.include?("content_fetcher.rb")
          file_path = command.match(/"([^"]+)"/)[1]
          if File.exist?(file_path)
            return File.read(file_path)
          else
            return "Error: File not found"
          end
        else
          "Unknown command"
        end
      end
    end
  end
  
  let(:helper) { test_class.new }
  let(:test_dir) do
    dir = if defined?(IN_CONTAINER) && IN_CONTAINER
            # In container, create test directory in /tmp instead of read-only /monadic
            "/tmp/test_#{Time.now.to_i}_#{rand(1000)}"
          else
            File.join(Dir.home, "monadic/data/test_#{Time.now.to_i}_#{rand(1000)}")
          end
    FileUtils.mkdir_p(dir)
    dir
  end
  
  after do
    # Clean up test directory
    FileUtils.rm_rf(test_dir) if Dir.exist?(test_dir)
  end
  
  describe "#fetch_text_from_office" do
    it "returns content from a real office document file" do
      # Create a test file
      test_file = File.join(test_dir, "test.docx")
      File.write(test_file, "This is a test Office document")
      
      result = helper.fetch_text_from_office(file: test_file)
      expect(result).to include("Converted: This is a test Office document")
    end
    
    it "handles empty files correctly" do
      test_file = File.join(test_dir, "empty.docx")
      File.write(test_file, "")
      
      result = helper.fetch_text_from_office(file: test_file)
      expect(result).to include("Error")
      expect(result).to include("empty")
    end
    
    it "handles non-existent files" do
      result = helper.fetch_text_from_office(file: "/nonexistent/file.docx")
      expect(result).to include("Error")
    end
  end
  
  describe "#fetch_text_from_pdf" do
    it "returns content from a real PDF file" do
      test_file = File.join(test_dir, "test.pdf")
      File.write(test_file, "This is a test PDF content")
      
      result = helper.fetch_text_from_pdf(pdf: test_file)
      expect(result).to include("PDF content: This is a test PDF content")
    end
    
    it "handles empty PDF files" do
      test_file = File.join(test_dir, "empty.pdf")
      File.write(test_file, "")
      
      result = helper.fetch_text_from_pdf(pdf: test_file)
      expect(result).to include("Error")
      expect(result).to include("empty")
    end
    
    it "handles missing PDF files" do
      result = helper.fetch_text_from_pdf(pdf: "/nonexistent/file.pdf")
      expect(result).to include("Error")
    end
  end
  
  describe "#fetch_text_from_file" do
    it "returns content from a real text file" do
      test_file = File.join(test_dir, "test.txt")
      content = "Hello, this is a test file!\nWith multiple lines."
      File.write(test_file, content)
      
      result = helper.fetch_text_from_file(file: test_file)
      expect(result).to eq(content)
    end
    
    it "handles empty text files" do
      test_file = File.join(test_dir, "empty.txt")
      File.write(test_file, "")
      
      result = helper.fetch_text_from_file(file: test_file)
      expect(result).to include("Error")
      expect(result).to include("empty")
    end
    
    it "handles various file encodings" do
      test_file = File.join(test_dir, "unicode.txt")
      content = "Hello 世界! 🌍 Café résumé"
      File.write(test_file, content, encoding: 'UTF-8')
      
      result = helper.fetch_text_from_file(file: test_file)
      expect(result).to eq(content)
    end
  end
  
  describe "#write_to_file" do
    context "when not in container" do
      before do
        # Save original value if it exists
        @original_in_container = Object.const_defined?(:IN_CONTAINER) ? IN_CONTAINER : nil
        # Remove and redefine constant
        Object.send(:remove_const, :IN_CONTAINER) if Object.const_defined?(:IN_CONTAINER)
        Object.const_set(:IN_CONTAINER, false)
      end
      
      after do
        # Restore original value
        Object.send(:remove_const, :IN_CONTAINER) if Object.const_defined?(:IN_CONTAINER)
        Object.const_set(:IN_CONTAINER, @original_in_container) if @original_in_container != nil
      end
      
      it "writes content to a real file" do
        filename = "test_write_#{Time.now.to_i}"
        content = "This is test content\nWith multiple lines"
        
        result = helper.write_to_file(
          filename: filename,
          extension: "txt",
          text: content
        )
        
        expect(result).to include("has been written successfully")
        
        # Verify the file was actually created
        expected_path = File.join(Dir.home, "monadic/data", "#{filename}.txt")
        expect(File.exist?(expected_path)).to be true
        expect(File.read(expected_path)).to eq(content)
        
        # Clean up
        File.delete(expected_path)
      end
      
      it "handles special characters in content" do
        filename = "special_chars_#{Time.now.to_i}"
        content = "Special chars: @#$%^&*() 日本語 émojis 🎉"
        
        result = helper.write_to_file(
          filename: filename,
          extension: "txt",
          text: content
        )
        
        expect(result).to include("has been written successfully")
        
        expected_path = File.join(Dir.home, "monadic/data", "#{filename}.txt")
        expect(File.read(expected_path, encoding: 'UTF-8')).to eq(content)
        
        # Clean up
        File.delete(expected_path)
      end
      
      it "handles non-existent directory" do
        # Test with a filename that includes a non-existent subdirectory path
        # This simulates trying to write to a subdirectory that doesn't exist
        filename_with_path = "nonexistent_#{Time.now.to_i}/subdir/test"
        
        result = helper.write_to_file(
          filename: filename_with_path,
          extension: "txt",
          text: "Test content"
        )
        
        # The implementation should handle this gracefully
        expect(result).to include("Error")
      end
      
      it "handles file write permissions errors gracefully" do
        if Process.uid == 0
          skip "Cannot test permission errors as root"
        end
        
        # Try to write a file with a filename that would cause permission issues
        # Use a system directory name that would fail
        filename = "/root/test_#{Time.now.to_i}"
        
        result = helper.write_to_file(
          filename: filename,
          extension: "txt",
          text: "This should fail"
        )
        
        expect(result).to include("Error")
      end
    end
    
    context "when in container" do
      it "creates file and attempts docker copy" do
        # Skip this test if not running in a container
        skip "This test is for container environment only" unless defined?(IN_CONTAINER) && IN_CONTAINER
        
        filename = "container_test_#{Time.now.to_i}"
        content = "Container test content"
        
        result = helper.write_to_file(
          filename: filename,
          extension: "txt",
          text: content
        )
        
        # In container, it should still return success
        expect(result).to include("has been written successfully")
        
        # Verify file exists in the shared volume
        expected_file = File.join(MonadicApp::SHARED_VOL, "#{filename}.txt")
        if File.exist?(expected_file)
          expect(File.read(expected_file)).to eq(content)
          # Clean up
          File.delete(expected_file)
        end
      end
    end
  end
  
  describe "error handling with real files" do
    it "handles various file system errors" do
      # Test with a file that doesn't exist
      result = helper.fetch_text_from_file(file: "/definitely/not/a/real/path.txt")
      expect(result).to include("Error")
      
      # Test with invalid filename characters (if applicable to the OS)
      if RUBY_PLATFORM !~ /mswin|mingw|cygwin/
        result = helper.write_to_file(
          filename: "invalid\0name",
          extension: "txt",
          text: "test"
        )
        expect(result).to include("Error")
      end
    end
  end
end