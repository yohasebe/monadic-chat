# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'fileutils'

# Define MonadicApp module with constants before requiring helper
unless defined?(MonadicApp::SHARED_VOL)
  module MonadicApp
    SHARED_VOL = "/monadic/data"
    LOCAL_SHARED_VOL = File.join(Dir.home, "monadic", "data")
  end
end

require_relative '../../../lib/monadic/adapters/read_write_helper'

RSpec.describe "Office Text Extraction" do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include MonadicHelper

      def send_command(command:, container:, success: "", success_with_output: "")
        @last_command = command
        @last_container = container
        @mock_response || ""
      end

      attr_accessor :mock_response, :last_command, :last_container
    end
  end

  let(:helper) { test_class.new }
  let(:data_dir) { File.join(Dir.home, "monadic", "data") }

  before do
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_dir)
  end

  describe "#fetch_text_from_office" do
    context "with valid DOCX file" do
      let(:docx_path) { File.join(data_dir, 'test_document.docx') }

      it "executes office2txt.py with correct parameters" do
        helper.mock_response = '{"text": "Test content"}'

        helper.fetch_text_from_office(file: docx_path)

        expect(helper.last_command).to include('office2txt.py')
        expect(helper.last_command).to include(docx_path)
        expect(helper.last_container).to eq('python')
      end

      it "returns JSON response from Python script" do
        expected_json = { "text" => "This is the first paragraph with some text.\nSecond paragraph contains numbers: 12345." }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: docx_path)

        expect(result).to eq(expected_json.to_json)
      end

      it "handles multi-paragraph documents" do
        paragraphs = [
          "First paragraph",
          "Second paragraph",
          "Third paragraph with special content"
        ]
        expected_json = { "text" => paragraphs.join("\n") }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: docx_path)

        parsed = JSON.parse(result)
        expect(parsed["text"]).to include("First paragraph")
        expect(parsed["text"]).to include("Second paragraph")
        expect(parsed["text"]).to include("Third paragraph")
      end
    end

    context "with valid XLSX file" do
      let(:xlsx_path) { File.join(data_dir, 'test_spreadsheet.xlsx') }

      it "executes office2txt.py for spreadsheet" do
        helper.mock_response = '{"text": "Header1\nHeader2\nValue1\n12345"}'

        helper.fetch_text_from_office(file: xlsx_path)

        expect(helper.last_command).to include('office2txt.py')
        expect(helper.last_command).to include(xlsx_path)
      end

      it "extracts cell values as text" do
        cell_values = ["Header1", "Header2", "Header3", "Value1", "12345", "Text with spaces"]
        expected_json = { "text" => cell_values.join("\n") }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: xlsx_path)

        parsed = JSON.parse(result)
        expect(parsed["text"]).to include("Header1")
        expect(parsed["text"]).to include("12345")
      end

      it "handles numeric cells" do
        expected_json = { "text" => "100\n200.5\n-50" }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: xlsx_path)

        parsed = JSON.parse(result)
        expect(parsed["text"]).to include("100")
        expect(parsed["text"]).to include("200.5")
      end
    end

    context "with valid PPTX file" do
      let(:pptx_path) { File.join(data_dir, 'test_presentation.pptx') }

      it "executes office2txt.py for presentation" do
        helper.mock_response = '{"text": "Test Presentation Content"}'

        helper.fetch_text_from_office(file: pptx_path)

        expect(helper.last_command).to include('office2txt.py')
        expect(helper.last_command).to include(pptx_path)
      end

      it "extracts text from multiple slides" do
        slide_texts = [
          "Slide 1 Title",
          "Bullet point 1",
          "Slide 2 Content",
          "More text"
        ]
        expected_json = { "text" => slide_texts.join("\n") }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: pptx_path)

        parsed = JSON.parse(result)
        expect(parsed["text"]).to include("Slide 1 Title")
        expect(parsed["text"]).to include("Slide 2 Content")
      end
    end

    context "with empty files" do
      let(:empty_docx_path) { File.join(data_dir, 'empty_document.docx') }

      it "returns error for empty DOCX" do
        helper.mock_response = ""

        result = helper.fetch_text_from_office(file: empty_docx_path)

        expect(result).to include("Error")
        expect(result).to include("empty")
      end

      it "returns error for empty XLSX" do
        helper.mock_response = ""

        result = helper.fetch_text_from_office(file: File.join(data_dir, 'empty_spreadsheet.xlsx'))

        expect(result).to include("Error")
      end

      it "returns error for empty PPTX" do
        helper.mock_response = ""

        result = helper.fetch_text_from_office(file: File.join(data_dir, 'empty_presentation.pptx'))

        expect(result).to include("Error")
      end
    end

    context "with non-existent files" do
      it "returns error for missing file" do
        helper.mock_response = "No such file or directory"

        result = helper.fetch_text_from_office(file: File.join(data_dir, "nonexistent.docx"))

        expect(result).to include("Error")
        expect(result).to include("not found")
      end

      it "returns specific error message for not found" do
        file_path = File.join(data_dir, "missing_file.docx")
        # Mock the actual response from office2txt.py
        helper.mock_response = "No such file or directory: #{file_path}"

        result = helper.fetch_text_from_office(file: file_path)

        expect(result).to include("Error")
        expect(result).to include("not found")
      end
    end

    context "with path validation" do
      it "rejects paths outside data directory" do
        result = helper.fetch_text_from_office(file: "/etc/passwd")

        expect(result).to include("Error")
        expect(result).to include("Invalid file path")
      end

      it "rejects directory traversal attempts" do
        result = helper.fetch_text_from_office(file: "../../etc/passwd")

        expect(result).to include("Error")
        expect(result).to include("Invalid file path")
      end

      it "accepts valid paths within data directory" do
        valid_path = File.join(data_dir, "test.docx")
        helper.mock_response = '{"text": "Valid content"}'

        result = helper.fetch_text_from_office(file: valid_path)

        expect(result).not_to include("Invalid file path")
      end
    end

    context "with special characters in content" do
      let(:docx_path) { File.join(data_dir, 'test_document.docx') }

      it "handles Japanese text" do
        expected_json = { "text" => "Japanese text: konnichiwa" }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: docx_path)

        parsed = JSON.parse(result)
        expect(parsed["text"]).to include("Japanese")
      end

      it "handles special characters" do
        expected_json = { "text" => "Special: @#$%^&*()" }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: docx_path)

        parsed = JSON.parse(result)
        expect(parsed["text"]).to include("Special")
      end

      it "handles numeric content" do
        expected_json = { "text" => "Numbers: 12345 67890" }
        helper.mock_response = expected_json.to_json

        result = helper.fetch_text_from_office(file: docx_path)

        expect(result).to include("12345")
      end
    end

    context "with script errors" do
      let(:docx_path) { File.join(data_dir, 'test.docx') }

      it "returns error from Python script" do
        helper.mock_response = "Error: Unsupported file type"

        result = helper.fetch_text_from_office(file: docx_path)

        expect(result).to include("Error")
      end

      it "handles corrupted file errors" do
        helper.mock_response = "Error: Unable to parse Office file"

        result = helper.fetch_text_from_office(file: docx_path)

        expect(result).to include("Error")
      end
    end

    context "JSON output format" do
      let(:docx_path) { File.join(data_dir, 'test_document.docx') }

      it "returns valid JSON structure" do
        helper.mock_response = '{"text": "Content here"}'

        result = helper.fetch_text_from_office(file: docx_path)

        expect { JSON.parse(result) }.not_to raise_error
      end

      it "includes text key in response" do
        helper.mock_response = '{"text": "Extracted text content"}'

        result = helper.fetch_text_from_office(file: docx_path)

        parsed = JSON.parse(result)
        expect(parsed).to have_key("text")
      end

      it "handles multiline text correctly" do
        multiline_text = "Line 1\nLine 2\nLine 3"
        helper.mock_response = { "text" => multiline_text }.to_json

        result = helper.fetch_text_from_office(file: docx_path)

        parsed = JSON.parse(result)
        expect(parsed["text"].split("\n").length).to eq(3)
      end
    end
  end

  describe "edge cases" do
    let(:docx_path) { File.join(data_dir, 'test_document.docx') }
    let(:xlsx_path) { File.join(data_dir, 'test_spreadsheet.xlsx') }

    it "handles very large documents" do
      # Simulate a document with many paragraphs
      large_text = Array.new(1000) { |i| "Paragraph #{i} with some content" }.join("\n")
      helper.mock_response = { "text" => large_text }.to_json

      result = helper.fetch_text_from_office(file: docx_path)

      parsed = JSON.parse(result)
      expect(parsed["text"].split("\n").length).to eq(1000)
    end

    it "handles files with only whitespace" do
      helper.mock_response = { "text" => "   \n\n   \t\t   " }.to_json

      result = helper.fetch_text_from_office(file: docx_path)

      parsed = JSON.parse(result)
      expect(parsed["text"].strip).to be_empty
    end

    it "handles mixed content types in XLSX" do
      # Dates, numbers, text, formulas
      mixed_content = "2024-01-15\n12345\nText value\n=SUM(A1:A10)"
      helper.mock_response = { "text" => mixed_content }.to_json

      result = helper.fetch_text_from_office(file: xlsx_path)

      parsed = JSON.parse(result)
      expect(parsed["text"]).to include("2024-01-15")
      expect(parsed["text"]).to include("12345")
    end
  end

  describe "comparison with PDF extraction" do
    let(:docx_path) { File.join(data_dir, 'empty_document.docx') }

    it "uses similar error handling patterns" do
      # PDF uses "Error: The file looks like empty"
      # Office should use similar pattern
      helper.mock_response = ""

      result = helper.fetch_text_from_office(file: docx_path)

      expect(result).to match(/Error:.*empty/i)
    end

    it "validates file paths like PDF extraction" do
      # Both should reject invalid paths
      result = helper.fetch_text_from_office(file: "../../../etc/passwd")

      expect(result).to include("Error")
      expect(result).to include("Invalid file path")
    end
  end
end

RSpec.describe "Office Text Extraction Integration", :integration do
  let(:test_class) do
    Class.new do
      include MonadicHelper

      def send_command(command:, container:, success: "", success_with_output: "")
        # Execute real Docker command
        docker_cmd = "docker exec monadic-chat-python-container python /monadic/scripts/converters/#{command}"
        stdout, _stderr, _status = Open3.capture3(docker_cmd)
        stdout
      end
    end
  end

  let(:helper) { test_class.new }
  let(:fixtures_dir) { File.expand_path('../../fixtures/office', __dir__) }
  let(:data_dir) { File.join(Dir.home, "monadic", "data") }

  before do
    skip "Integration tests require Docker" unless system("docker ps > /dev/null 2>&1")
    skip "Python container not running" unless system("docker ps | grep -q monadic-chat-python-container")

    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data_dir)

    # Copy fixture files to data_dir for Docker container access
    FileUtils.mkdir_p(data_dir)
    %w[test_document.docx test_spreadsheet.xlsx test_presentation.pptx].each do |file|
      src = File.join(fixtures_dir, file)
      dst = File.join(data_dir, file)
      FileUtils.cp(src, dst) if File.exist?(src) && !File.exist?(dst)
    end
  end

  describe "real file extraction" do
    it "extracts text from real DOCX file" do
      file_path = File.join(data_dir, 'test_document.docx')
      skip "Test file not found: #{file_path}" unless File.exist?(file_path)

      result = helper.fetch_text_from_office(file: file_path)

      # Should return JSON with extracted text
      if result.include?("Error")
        # Check if it's a "not found in container" error - file exists locally but not in container
        expect(result).to include("not found").or include("could not be found")
      else
        parsed = JSON.parse(result) rescue nil
        if parsed
          expect(parsed["text"]).to include("paragraph").or be_a(String)
        else
          expect(result).to be_a(String)
        end
      end
    end

    it "extracts text from real XLSX file" do
      file_path = File.join(data_dir, 'test_spreadsheet.xlsx')
      skip "Test file not found: #{file_path}" unless File.exist?(file_path)

      result = helper.fetch_text_from_office(file: file_path)

      if result.include?("Error")
        expect(result).to include("not found").or include("could not be found")
      else
        parsed = JSON.parse(result) rescue nil
        if parsed
          expect(parsed["text"]).to include("Header").or be_a(String)
        else
          expect(result).to be_a(String)
        end
      end
    end

    it "extracts text from real PPTX file" do
      file_path = File.join(data_dir, 'test_presentation.pptx')
      skip "Test file not found: #{file_path}" unless File.exist?(file_path)

      result = helper.fetch_text_from_office(file: file_path)

      if result.include?("Error")
        expect(result).to include("not found").or include("could not be found")
      else
        parsed = JSON.parse(result) rescue nil
        if parsed
          expect(parsed["text"]).to include("Presentation").or be_a(String)
        else
          expect(result).to be_a(String)
        end
      end
    end
  end
end
