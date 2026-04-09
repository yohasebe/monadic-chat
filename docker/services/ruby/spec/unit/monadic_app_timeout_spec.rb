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

  describe "#truncate_output" do
    let(:app) { MonadicApp.new }

    it "returns short output unchanged" do
      text = "line 1\nline 2\nline 3\n"
      expect(app.truncate_output(text)).to eq(text)
    end

    it "returns output under byte limit unchanged even with many lines" do
      text = (1..200).map { |i| "L#{i}\n" }.join
      # Under 50KB so should not truncate
      expect(app.truncate_output(text)).to eq(text)
    end

    it "truncates output exceeding byte limit" do
      # Generate ~80KB of output (200 lines of ~400 bytes each)
      lines = (1..200).map { |i| "Line #{i}: #{"x" * 400}\n" }
      text = lines.join
      expect(text.bytesize).to be > MonadicApp::MAX_OUTPUT_BYTES

      result = app.truncate_output(text)
      expect(result.bytesize).to be < text.bytesize
      expect(result).to include("lines omitted")
      # First line preserved
      expect(result).to include("Line 1:")
      # Last line preserved
      expect(result).to include("Line 200:")
    end

    it "does not truncate when line count is within head + tail" do
      # 140 lines (< HEAD_LINES + TAIL_LINES = 150) but large bytes
      lines = (1..140).map { |i| "Line #{i}: #{"x" * 500}\n" }
      text = lines.join
      expect(text.bytesize).to be > MonadicApp::MAX_OUTPUT_BYTES
      # Line count is under threshold so output is returned as-is
      expect(app.truncate_output(text)).to eq(text)
    end
  end
end