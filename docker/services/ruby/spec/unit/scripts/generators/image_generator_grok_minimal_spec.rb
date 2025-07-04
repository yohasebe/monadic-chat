require 'spec_helper'
require 'open3'

RSpec.describe "image_generator_grok.rb minimal tests" do
  let(:script_path) { File.expand_path("../../../../scripts/generators/image_generator_grok.rb", __dir__) }
  
  def run_script(args)
    command = ["ruby", script_path] + args
    stdout, stderr, status = Open3.capture3(*command)
    { stdout: stdout, stderr: stderr, status: status }
  end
  
  describe "argument handling" do
    it "shows error when no prompt provided" do
      result = run_script([])
      expect(result[:stdout]).to include("ERROR: A prompt is required")
      expect(result[:status].success?).to be true  # Script exits normally
    end
    
    it "accepts prompt with -p flag" do
      # Set environment variable instead of creating config file
      original_xai_key = ENV['XAI_API_KEY']
      ENV['XAI_API_KEY'] = 'test-key-123'
      
      begin
        # Will fail with API error or config file error, but validates argument parsing
        result = run_script(["-p", "test prompt"])
        # The important thing is that it doesn't show the "prompt required" error
        expect(result[:stdout]).not_to include("ERROR: A prompt is required")
        # It should either show API error or config file error
        expect(result[:stdout]).to match(/ERROR:|No such file or directory/)
      ensure
        if original_xai_key
          ENV['XAI_API_KEY'] = original_xai_key
        else
          ENV.delete('XAI_API_KEY')
        end
      end
    end
  end
end