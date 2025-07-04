require 'spec_helper'
require 'tempfile'
require 'open3'

RSpec.describe "content_fetcher.rb" do
  let(:script_path) { File.expand_path("../../../scripts/cli_tools/content_fetcher.rb", __dir__) }
  
  def run_script(args)
    stdout, stderr, status = Open3.capture3("ruby", script_path, *args)
    { stdout: stdout, stderr: stderr, status: status }
  end
  
  describe "argument handling" do
    it "returns error when no filepath is provided" do
      result = run_script([])
      expect(result[:stdout]).to include("ERROR: No filepath provided.")
      expect(result[:status].exitstatus).to eq(1)
    end
    
    it "accepts sizecap as second argument" do
      # Create a temporary file with content larger than the sizecap
      Tempfile.create(['test', '.txt']) do |file|
        content = "a" * 100
        file.write(content)
        file.flush
        
        result = run_script([file.path, "50"])
        expect(result[:stdout]).to include("WARNING: File size exceeds sizecap")
        expect(result[:stdout]).to include("a" * 50)
        expect(result[:stdout]).not_to include("a" * 51)
        expect(result[:status].success?).to be true
      end
    end
  end
  
  describe "file validation" do
    it "returns error for non-existent file" do
      result = run_script(["/non/existent/file.txt"])
      expect(result[:stdout]).to include("ERROR: File /non/existent/file.txt does not exist or is not readable.")
      expect(result[:status].exitstatus).to eq(1)
    end
    
    it "returns error for binary files" do
      Tempfile.create(['binary', '.bin']) do |file|
        # Write binary content with null bytes
        file.write("\x00\x01\x02\x03\x04")
        file.flush
        
        result = run_script([file.path])
        expect(result[:stdout]).to include("ERROR: The file appears to be binary.")
        expect(result[:status].exitstatus).to eq(1)
      end
    end
  end
  
  describe "text file handling" do
    it "reads plain text files successfully" do
      Tempfile.create(['test', '.txt']) do |file|
        content = "Hello, World!\nThis is a test file."
        file.write(content)
        file.flush
        
        result = run_script([file.path])
        expect(result[:stdout].chomp).to eq(content)
        expect(result[:status].success?).to be true
      end
    end
    
    it "handles UTF-8 content correctly" do
      Tempfile.create(['utf8', '.txt']) do |file|
        content = "こんにちは世界！ 🌍 Ñoño"
        file.write(content)
        file.flush
        
        result = run_script([file.path])
        expect(result[:stdout].chomp).to eq(content)
        expect(result[:status].success?).to be true
      end
    end
    
    it "handles files with invalid UTF-8 sequences" do
      Tempfile.create(['invalid', '.txt']) do |file|
        # Write some valid text followed by invalid UTF-8
        file.write("Valid text ")
        file.write("\xFF\xFE")  # Invalid UTF-8 sequence
        file.write(" more text")
        file.flush
        
        result = run_script([file.path])
        # Should replace invalid sequences
        expect(result[:stdout]).to include("Valid text")
        expect(result[:stdout]).to include("more text")
        expect(result[:status].success?).to be true
      end
    end
    
    it "handles empty files" do
      Tempfile.create(['empty', '.txt']) do |file|
        # Don't write anything to the file
        file.flush
        
        result = run_script([file.path])
        expect(result[:stdout]).to eq("")
        expect(result[:status].success?).to be true
      end
    end
  end
  
  describe "sizecap functionality" do
    it "reads entire file when under sizecap" do
      Tempfile.create(['small', '.txt']) do |file|
        content = "Small file content"
        file.write(content)
        file.flush
        
        result = run_script([file.path, "1000"])
        expect(result[:stdout].chomp).to eq(content)
        expect(result[:status].success?).to be true
      end
    end
    
    it "truncates file when over sizecap" do
      Tempfile.create(['large', '.txt']) do |file|
        content = "X" * 1000
        file.write(content)
        file.flush
        
        result = run_script([file.path, "100"])
        expect(result[:stdout]).to include("WARNING: File size exceeds sizecap")
        # Check that only 100 bytes were read (plus the warning message)
        output_lines = result[:stdout].split("\n")
        expect(output_lines.last).to eq("X" * 100)
        expect(result[:status].success?).to be true
      end
    end
    
    it "uses default sizecap of 10MB when not specified" do
      Tempfile.create(['default', '.txt']) do |file|
        # Create a file just over 10MB
        content = "A" * (10_000_001)
        file.write(content)
        file.flush
        
        result = run_script([file.path])
        expect(result[:stdout]).to include("WARNING: File size exceeds sizecap")
        expect(result[:stdout]).to include("10000001 bytes > 10000000 bytes")
        expect(result[:status].success?).to be true
      end
    end
  end
  
  describe "error handling" do
    it "handles file permission errors gracefully" do
      if Process.uid == 0
        skip "Cannot test permission errors as root"
      end
      
      Tempfile.create(['readonly', '.txt']) do |file|
        file.write("test content")
        file.flush
        # Make file unreadable
        File.chmod(0000, file.path)
        
        begin
          result = run_script([file.path])
          expect(result[:stdout]).to include("ERROR: File")
          expect(result[:stdout]).to include("does not exist or is not readable")
          expect(result[:status].exitstatus).to eq(1)
        ensure
          # Restore permissions for cleanup
          File.chmod(0644, file.path)
        end
      end
    end
  end
end