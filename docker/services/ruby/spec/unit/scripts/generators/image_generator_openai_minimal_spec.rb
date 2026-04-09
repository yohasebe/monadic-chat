require 'spec_helper'
require 'open3'

RSpec.describe "image_generator_openai.rb minimal tests" do
  let(:script_path) { File.expand_path("../../../../scripts/generators/image_generator_openai.rb", __dir__) }

  def run_script(args)
    command = ["ruby", script_path] + args
    stdout, stderr, status = Open3.capture3(*command)
    { stdout: stdout, stderr: stderr, status: status }
  end

  describe "argument handling" do
    it "shows error when no prompt provided for generate" do
      result = run_script(["-o", "generate"])
      expect(result[:stdout]).to include("ERROR")
      expect(result[:stdout]).to include("prompt")
    end

    it "shows error when no prompt/image provided for edit" do
      result = run_script(["-o", "edit"])
      expect(result[:stdout]).to include("ERROR")
    end

    it "rejects invalid operation" do
      result = run_script(["-o", "invalid"])
      expect(result[:stdout]).to include("Invalid operation")
    end
  end

  describe "JSON mode for image edits" do
    it "accepts --image-url option without requiring local files" do
      result = run_script(["-o", "edit", "-p", "test", "--image-url", "https://example.com/img.png"])
      # Should not fail on argument parsing (no OptionParser::InvalidOption)
      expect(result[:stderr]).not_to include("invalid option: --image-url")
      # Should pass validation (image_url counts as image input)
      expect(result[:stdout]).not_to include("at least one input image are required")
    end

    it "accepts --image-file-id option without requiring local files" do
      result = run_script(["-o", "edit", "-p", "test", "--image-file-id", "file-abc123"])
      # Should not fail on argument parsing
      expect(result[:stderr]).not_to include("invalid option: --image-file-id")
      # Should pass validation (file_id counts as image input)
      expect(result[:stdout]).not_to include("at least one input image are required")
    end

    it "accepts multiple --image-url options" do
      result = run_script([
        "-o", "edit", "-p", "test",
        "--image-url", "https://example.com/img1.png",
        "--image-url", "https://example.com/img2.png"
      ])
      expect(result[:stderr]).not_to include("invalid option")
      expect(result[:stdout]).not_to include("at least one input image are required")
    end

    it "accepts multiple --image-file-id options" do
      result = run_script([
        "-o", "edit", "-p", "test",
        "--image-file-id", "file-abc1",
        "--image-file-id", "file-abc2"
      ])
      expect(result[:stderr]).not_to include("invalid option")
      expect(result[:stdout]).not_to include("at least one input image are required")
    end
  end
end
