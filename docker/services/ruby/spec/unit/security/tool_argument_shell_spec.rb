# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "open3"
require_relative "../../../lib/monadic/app"
require_relative "../../../lib/monadic/adapters/text_to_speech_helper"

# Tool arguments are written by the model, and a document or web page the
# model reads can steer them. None of them may reach a shell on the host or
# in the Ruby container.
RSpec.describe "tool arguments never reach a shell" do
  HOSTILE = [
    "$(touch PWNED)",
    "`touch PWNED`",
    "a; touch PWNED",
    "a\ntouch PWNED",
    "a\" ; touch PWNED; \"",
    "a' ; touch PWNED; '"
  ].freeze

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  def pwned?
    File.exist?(File.join(@dir, "PWNED"))
  end

  describe "MonadicApp.capture_command with an Array" do
    it "passes each element as one argument, without a shell" do
      HOSTILE.each do |value|
        stdout, _stderr, status = MonadicApp.capture_command(["printf", "%s", value], timeout: 5)
        expect(status.success?).to be true
        expect(stdout).to eq(value)
      end
      expect(pwned?).to be false
    end
  end

  describe "#send_code (run_code)" do
    let(:app) { MonadicApp.new }
    let(:calls) { [] }

    before do
      stub_const("MonadicApp::LOCAL_SHARED_VOL", @dir)
      allow(Dir).to receive(:home).and_return(@dir)
      FileUtils.mkdir_p(File.join(@dir, "monadic", "data"))
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@dir)
      recorded = calls
      data = @dir
      allow(app).to receive(:capture_command) do |command, **|
        # The code file is in the shared folder while it runs
        recorded << [command, File.exist?(File.join(data, command.last.to_s))]
        ["", "stop here", OpenStruct.new(success?: false)]
      end
    end

    it "refuses an execution command that is not an interpreter name" do
      ["python; touch PWNED", "$(touch PWNED)", "`touch PWNED`", "/bin/sh -c x; y", ""].each do |command|
        result = app.send(:send_code, code: "print(1)", command: command, extension: "py", max_retries: 0)
        expect(result).to start_with("Error: Invalid execution command")
      end
      expect(calls).to be_empty
    end

    it "refuses an extension that is not letters and digits" do
      ["py; touch PWNED", "py $(touch PWNED)", "../x", "py\nx"].each do |extension|
        result = app.send(:send_code, code: "print(1)", command: "python", extension: extension, max_retries: 0)
        expect(result).to start_with("Error: Invalid file extension")
      end
      expect(calls).to be_empty
    end

    it "runs docker with an argv array, the command split into its own arguments" do
      result = app.send(:send_code, code: "print(1)", command: "python3 -u", extension: "py", max_retries: 0)
      expect(calls.size).to eq(1), "send_code returned #{result.inspect} before running docker"
      exec, present = calls.first
      expect(exec).to be_an(Array)
      expect(exec[0..4]).to eq(["docker", "exec", "-w", "/monadic/data", "monadic-chat-python-container"])
      expect(exec[5..6]).to eq(%w[python3 -u])
      expect(exec.last).to match(/\Acode_\d{8}_\d{6}_[0-9a-f]{8}\.py\z/)
      expect(present).to be(true)
      expect(Dir.glob(File.join(@dir, "code_*"))).to be_empty
    end

    it "leaves a file already at the code file's name alone" do
      allow(SecureRandom).to receive(:hex).and_return("deadbeef")
      allow(Time).to receive(:now).and_return(Time.at(0))
      taken = File.join(@dir, "code_#{Time.at(0).strftime('%Y%m%d_%H%M%S')}_deadbeef.py")
      File.write(taken, "existing user data")
      result = app.send(:send_code, code: "print(1)", command: "python", extension: "py", max_retries: 0)
      expect(result).to start_with("Error executing code")
      expect(calls).to be_empty
      expect(File.read(taken)).to eq("existing user data")
    end

    it "keeps each attempt's code file when asked to" do
      app.send(:send_code, code: "print(1)", command: "python", extension: "py", max_retries: 1, retry_delay: 0, keep_file: true)
      expect(calls.size).to eq(2)
      expect(Dir.glob(File.join(@dir, "code_*.py")).size).to eq(2)
    end
  end

  describe "#text_to_speech" do
    let(:helper) do
      Class.new do
        include MonadicHelper
        attr_reader :command
        def send_command(command:, container:)
          @command = command
        end
      end.new
    end

    before do
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@dir)
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@dir)
      stub_const("CONFIG", {})
    end

    it "keeps every option one argument" do
      HOSTILE.each do |value|
        helper.text_to_speech(provider: value, speed: value, voice_id: value, language: value, instructions: value, text: "hi")
        # Run the built command with the script replaced by printf
        script = helper.command.sub(/\Atts_query\.rb/, "printf '%s\\n'")
        stdout, _stderr, status = Open3.capture3("/bin/sh", "-c", script)
        expect(status.success?).to be true
        args = stdout.split("\n", -1)
        expect(args).to include("--voice=#{value.split("\n").first}") unless value.include?("\n")
        expect(helper.command).to start_with("tts_query.rb ")
      end
      expect(pwned?).to be false
    end
  end
end
