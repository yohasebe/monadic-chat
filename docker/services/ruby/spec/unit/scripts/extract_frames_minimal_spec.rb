require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe "extract_frames.py minimal tests" do
  let(:container_name) { "monadic-chat-python-container" }
  let(:script_path) { "/monadic/scripts/converters/extract_frames.py" }
  
  def run_in_container(script_args)
    command = ["docker", "exec", container_name, "python", script_path] + script_args
    stdout, stderr, status = Open3.capture3(*command)
    { stdout: stdout, stderr: stderr, status: status }
  end
  
  describe "basic functionality" do
    it "shows help with --help flag" do
      result = run_in_container(["--help"])
      expect(result[:stdout]).to include("usage:")
      expect(result[:stdout]).to include("Extract frames and audio from a video file")
      expect(result[:status].success?).to be true
    end
    
    it "shows error when insufficient arguments provided" do
      result = run_in_container([])
      expect(result[:stderr]).to include("usage:")
      expect(result[:stderr]).to include("required")
      expect(result[:status].exitstatus).to eq(2)
    end
    
    it "shows error when only video path provided" do
      result = run_in_container(["test.mp4"])
      expect(result[:stderr]).to include("usage:")
      expect(result[:stderr]).to include("required")
      expect(result[:status].exitstatus).to eq(2)
    end
  end
  
  describe "file validation" do
    it "reports error for non-existent video file" do
      result = run_in_container(["/non/existent/video.mp4", "/monadic/data"])
      expect(result[:stdout]).to include("Error: Could not open video")
      expect(result[:status].success?).to be true
    end
  end
  
  describe "format validation" do
    it "rejects invalid image format" do
      result = run_in_container(["test.mp4", "/output", "--format", "gif"])
      expect(result[:stderr]).to include("invalid choice: 'gif'")
      expect(result[:status].exitstatus).to eq(2)
    end
  end
end