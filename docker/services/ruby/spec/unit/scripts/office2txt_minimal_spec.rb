require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe "office2txt.py minimal tests", :integration do
  let(:container_name) { "monadic-chat-python-container" }
  let(:script_path) { "/monadic/scripts/converters/office2txt.py" }
  
  def run_in_container(script_args)
    command = ["docker", "exec", container_name, "python", script_path] + script_args
    stdout, stderr, status = Open3.capture3(*command)
    { stdout: stdout, stderr: stderr, status: status }
  end
  
  describe "basic functionality" do
    it "shows help with --help flag" do
      result = run_in_container(["--help"])
      expect(result[:stdout]).to include("usage:")
      expect(result[:stdout]).to include("Extract text from Office files")
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
      result = run_in_container(["/non/existent/file.docx"])
      expect(result[:stdout]).to include("The specified file could not be found")
      expect(result[:status].success?).to be true
    end
  end
end