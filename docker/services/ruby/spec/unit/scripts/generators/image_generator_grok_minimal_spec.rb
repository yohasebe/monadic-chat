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
      expect(result[:status].exitstatus).to eq(1)  # Script exits with error status
    end
    
    it "accepts prompt with -p flag" do
      # Will fail with API error or succeed with real config, but validates argument parsing
      result = run_script(["-p", "test prompt"])
      # The important thing is that it doesn't show the "prompt required" error
      expect(result[:stdout]).not_to include("ERROR: A prompt is required")
      # The script should at least try to run (may succeed or fail depending on config)
      expect(result[:status].success?).to be true
    end
  end

  # The xAI error text names the account's team UUID when a model is not
  # enabled for it, and that text is surfaced in the chat and saved with the
  # conversation. Load just the scrubber out of the script (running the file
  # would parse ARGV and exit) and pin that identifiers do not survive.
  describe "account id scrubbing" do
    let(:scrubber) do
      src = File.read(script_path)[/def scrub_account_ids.*?^end/m]
      raise "scrub_account_ids not found in script" unless src

      Class.new { class_eval(src) }.new
    end

    it "replaces a team UUID in an API error message" do
      msg = "The model foo does not exist or your team " \
            "00000000-1111-2222-3333-444444444444 does not have access to it."
      out = scrubber.scrub_account_ids(msg)
      expect(out).not_to include("00000000-1111-2222-3333-444444444444")
      expect(out).to include("[id]")
      # The rest of the message still explains what went wrong.
      expect(out).to include("does not have access")
    end

    it "leaves messages without identifiers untouched" do
      expect(scrubber.scrub_account_ids("Rate limit exceeded")).to eq("Rate limit exceeded")
    end
  end
end
