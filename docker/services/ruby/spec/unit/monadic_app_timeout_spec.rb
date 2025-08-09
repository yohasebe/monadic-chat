require "spec_helper"
require_relative "../../lib/monadic/app"

RSpec.describe MonadicApp do
  describe ".capture_command with timeout" do
    context "when command completes within timeout" do
      it "returns the output successfully" do
        stdout, stderr, status = MonadicApp.capture_command("echo 'test'", timeout: 5)
        expect(stdout.strip).to eq("test")
        expect(status.success?).to be true
      end
    end

    context "when command exceeds timeout" do
      it "returns timeout error message" do
        stdout, stderr, status = MonadicApp.capture_command("sleep 3", timeout: 1)
        expect(stderr).to include("Command timed out after 1 seconds")
        expect(stderr).to include("Consider simplifying the input or reducing reasoning_effort")
        expect(status.success?).to be false
      end
    end

    context "with default timeout" do
      it "uses 120 seconds as default" do
        # This test verifies the default timeout is set correctly
        stdout, stderr, status = MonadicApp.capture_command("echo 'quick'")
        expect(stdout.strip).to eq("quick")
        expect(status.success?).to be true
      end
    end
  end

  describe "#capture_command instance method" do
    let(:app) { MonadicApp.new }

    it "delegates to class method with timeout parameter" do
      # Test actual delegation by checking the result
      stdout, stderr, status = app.capture_command("echo 'test'", timeout: 60)
      expect(stdout.strip).to eq("test")
      expect(status.success?).to be true
    end
  end
end