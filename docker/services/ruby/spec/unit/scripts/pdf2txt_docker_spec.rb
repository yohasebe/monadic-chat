require 'spec_helper'
require 'tempfile'
require 'open3'
require 'json'
require 'fileutils'

RSpec.describe "pdf2txt.py in Docker" do
  let(:container_name) { "monadic-chat-python-container" }
  let(:script_path) { "/monadic/scripts/converters/pdf2txt.py" }
  let(:data_dir) { File.expand_path("~/monadic/data") }
  
  # Helper to run script in Docker container
  def run_in_container(script_args)
    command = ["docker", "exec", container_name, "python", script_path] + script_args
    stdout, stderr, status = Open3.capture3(*command)
    { stdout: stdout, stderr: stderr, status: status }
  end
  
  # Helper to create test file in shared volume
  def create_test_file(filename, content)
    filepath = File.join(data_dir, filename)
    File.write(filepath, content)
    filepath
  end
  
  # Helper to cleanup test files
  def cleanup_test_file(filename)
    filepath = File.join(data_dir, filename)
    FileUtils.rm_f(filepath)
  end
  
  describe "basic functionality" do
    it "shows help with --help flag" do
      result = run_in_container(["--help"])
      expect(result[:stdout]).to include("usage:")
      expect(result[:stdout]).to include("Extract text from a PDF file and output as JSON")
      expect(result[:status].success?).to be true
    end
    
    it "shows error when no arguments provided" do
      result = run_in_container([])
      expect(result[:stderr]).to include("usage:")
      expect(result[:stderr]).to include("required")
      expect(result[:status].exitstatus).to eq(2)
    end
  end
  
  describe "file validation" do
    it "reports error for non-existent file" do
      result = run_in_container(["/non/existent/file.pdf"])
      expect(result[:stdout]).to include("PDF file not found: /non/existent/file.pdf")
      expect(result[:status].exitstatus).to eq(1)
    end
    
    it "reports error for non-PDF file" do
      test_file = "test_not_pdf_#{Time.now.to_i}.txt"
      create_test_file(test_file, "This is not a PDF")
      
      begin
        result = run_in_container(["/monadic/data/#{test_file}"])
        expect(result[:stdout]).to include("Error processing PDF:")
        expect(result[:status].exitstatus).to eq(1)
      ensure
        cleanup_test_file(test_file)
      end
    end
  end
  
  describe "output format validation" do
    let(:minimal_pdf_content) do
      # Create a minimal valid PDF
      content = "%PDF-1.4\n"
      content += "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
      content += "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
      content += "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Resources<<>>>>endobj\n"
      content += "xref\n0 4\n0000000000 65535 f\n0000000009 00000 n\n0000000058 00000 n\n0000000117 00000 n\n"
      content += "trailer<</Size 4/Root 1 0 R>>\nstartxref\n203\n%%EOF"
      content
    end
    
    it "accepts various output formats" do
      test_file = "test_formats_#{Time.now.to_i}.pdf"
      create_test_file(test_file, minimal_pdf_content)
      
      begin
        # Test each format
        %w[md txt html xml].each do |format|
          result = run_in_container(["/monadic/data/#{test_file}", "--format", format])
          if !result[:status].success?
            puts "Format #{format} failed with stdout: #{result[:stdout]}"
            puts "stderr: #{result[:stderr]}"
          end
          expect(result[:status].success?).to be(true), "Failed for format: #{format}"
        end
      ensure
        cleanup_test_file(test_file)
      end
    end
    
    it "rejects invalid format" do
      test_file = "test_invalid_format_#{Time.now.to_i}.pdf"
      create_test_file(test_file, minimal_pdf_content)
      
      begin
        result = run_in_container(["/monadic/data/#{test_file}", "--format", "invalid"])
        # argparse will show error in stderr for invalid choices
        expect(result[:stderr]).to include("invalid choice: 'invalid'")
        expect(result[:status].exitstatus).to eq(2)  # argparse exits with 2 for argument errors
      ensure
        cleanup_test_file(test_file)
      end
    end
  end
  
  describe "PDF processing" do
    let(:test_pdf_content) do
      # More complete PDF with actual text content
      content = "%PDF-1.4\n"
      content += "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
      content += "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
      content += "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj\n"
      content += "4 0 obj<</Length 44>>stream\nBT /F1 12 Tf 100 700 Td (Test PDF Content) Tj ET\nendstream\nendobj\n"
      content += "5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n"
      content += "xref\n0 6\n0000000000 65535 f\n0000000009 00000 n\n0000000058 00000 n\n0000000117 00000 n\n0000000229 00000 n\n0000000328 00000 n\n"
      content += "trailer<</Size 6/Root 1 0 R>>\nstartxref\n406\n%%EOF"
      content
    end
    
    it "processes PDF with --all-pages flag" do
      test_file = "test_all_pages_#{Time.now.to_i}.pdf"
      create_test_file(test_file, test_pdf_content)
      
      begin
        result = run_in_container(["/monadic/data/#{test_file}", "--all-pages"])
        expect(result[:status].success?).to be true
        expect(result[:stdout]).not_to be_empty
      ensure
        cleanup_test_file(test_file)
      end
    end
    
    it "outputs JSON with --json flag" do
      test_file = "test_json_#{Time.now.to_i}.pdf"
      create_test_file(test_file, test_pdf_content)
      
      begin
        result = run_in_container(["/monadic/data/#{test_file}", "--json"])
        expect(result[:status].success?).to be true
        
        # Should be valid JSON
        parsed = JSON.parse(result[:stdout])
        expect(parsed).to have_key("pages")
        expect(parsed["pages"]).to be_an(Array)
        expect(parsed["pages"]).not_to be_empty
      ensure
        cleanup_test_file(test_file)
        # Also cleanup the generated JSON file
        cleanup_test_file("#{File.basename(test_file, '.pdf')}.txt.json")
      end
    end
    
    it "shows progress with --show-progress flag for markdown" do
      test_file = "test_progress_#{Time.now.to_i}.pdf"
      create_test_file(test_file, test_pdf_content)
      
      begin
        result = run_in_container(["/monadic/data/#{test_file}", "--format", "md", "--show-progress"])
        expect(result[:status].success?).to be true
        # Progress might be minimal for single-page PDFs
      ensure
        cleanup_test_file(test_file)
      end
    end
  end
  
  describe "error handling" do
    it "handles corrupted PDF files" do
      test_file = "test_corrupted_#{Time.now.to_i}.pdf"
      create_test_file(test_file, "%PDF-1.4\nThis is corrupted")
      
      begin
        result = run_in_container(["/monadic/data/#{test_file}"])
        expect(result[:stdout]).to include("Error processing PDF:")
        expect(result[:status].exitstatus).to eq(1)
      ensure
        cleanup_test_file(test_file)
      end
    end
    
    it "handles empty files" do
      test_file = "test_empty_#{Time.now.to_i}.pdf"
      create_test_file(test_file, "")
      
      begin
        result = run_in_container(["/monadic/data/#{test_file}"])
        expect(result[:stdout]).to include("Error processing PDF:")
        expect(result[:status].exitstatus).to eq(1)
      ensure
        cleanup_test_file(test_file)
      end
    end
  end
end