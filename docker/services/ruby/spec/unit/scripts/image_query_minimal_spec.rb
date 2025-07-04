require 'spec_helper'
require 'open3'

RSpec.describe "image_query.rb minimal tests" do
  let(:script_path) { File.join(File.dirname(__dir__), "..", "..", "scripts", "cli_tools", "image_query.rb") }
  
  def run_script(args)
    command = ["ruby", script_path] + args
    stdout, stderr, status = Open3.capture3(*command)
    { stdout: stdout, stderr: stderr, status: status }
  end
  
  describe "argument handling" do
    it "shows usage when no arguments provided" do
      result = run_script([])
      # Script prints to stdout and exits normally
      expect(result[:stdout]).to include("Usage:")
      expect(result[:stdout]).to include("message")
      expect(result[:stdout]).to include("image_path_or_url")
      expect(result[:status].success?).to be true  # Script exits normally
    end
    
    it "shows usage when only message provided" do
      result = run_script(["test message"])
      expect(result[:stdout]).to include("Usage:")
      expect(result[:status].success?).to be true  # Script exits normally
    end
  end
end