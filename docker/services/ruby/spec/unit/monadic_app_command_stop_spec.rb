# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "securerandom"

# Commands a tool runs (send_command, send_code) go through
# MonadicApp.capture_command and Monadic::Shell: stopped with the thread
# that runs them (Cancel) or once they run over their time, they stop at once
# with all they started, and a timeout comes back as a failed status that
# says so.
RSpec.describe "MonadicApp commands that are stopped" do
  def marked_running?(marker)
    !IO.popen(["pgrep", "-f", marker], &:read).strip.empty?
  end

  def wait_until(limit = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + limit
    until yield
      raise "not in time" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end

  describe ".capture_command on this side" do
    it "stops at once with its children and grandchildren when the thread running it is killed" do
      # Each sleep is told apart by its own length: the child and the grandchild.
      child = 30_000 + rand(10_000)
      grandchild = child + 1
      script = "sh -c 'sleep #{grandchild}' & sleep #{child}"
      runner = Thread.new { MonadicApp.capture_command(["sh", "-c", script], timeout: 60) }
      wait_until { marked_running?("sleep #{child}") && marked_running?("sleep #{grandchild}") }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      runner.kill
      expect(runner.join(10)).not_to be_nil
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
      wait_until(3) { !marked_running?("sleep #{child}") && !marked_running?("sleep #{grandchild}") }
    ensure
      system("pkill", "-f", "sleep #{child}") if child
      system("pkill", "-f", "sleep #{grandchild}") if grandchild
    end

    it "comes back as timed out, at its limit, with nothing left running" do
      marker = "monadic_late_#{SecureRandom.hex(4)}"
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = MonadicApp.capture_command(["sh", "-c", "sleep 30; : #{marker}"], timeout: 1)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 6
      expect(stdout).to eq("")
      expect(stderr).to start_with("Command timed out after 1 seconds")
      expect(status.success?).to be(false)
      expect(status.timed_out?).to be(true)
      wait_until(3) { !marked_running?(marker) }
    ensure
      system("pkill", "-f", marker) if marker
    end

    it "gives back what a command wrote to both of its outputs, and its status" do
      big = 200_000
      stdout, stderr, status = MonadicApp.capture_command(
        ["sh", "-c", "head -c #{big} /dev/zero | tr '\\0' o; head -c #{big} /dev/zero | tr '\\0' e >&2; exit 3"], timeout: 10
      )
      expect(stdout.size).to eq(big)
      expect(stderr.size).to eq(big)
      expect(status.success?).to be(false)
      expect(status.exitstatus).to eq(3)
      expect(status).not_to respond_to(:timed_out?)
    end

    it "runs with the environment and directory it is given" do
      Dir.mktmpdir do |dir|
        stdout, = MonadicApp.capture_command(["sh", "-c", 'printf "%s %s" "$MONADIC_SPEC_VALUE" "$(pwd -P)"'],
                                             timeout: 5, env: { "MONADIC_SPEC_VALUE" => "given" }, chdir: dir)
        expect(stdout).to eq("given #{File.realpath(dir)}")
      end
    end

    it "runs a String through sh" do
      stdout, = MonadicApp.capture_command("echo one && echo two", timeout: 5)
      expect(stdout).to eq("one\ntwo\n")
    end
  end

  describe ".capture_command in a container" do
    it "runs an Array as argv and a String as a bash body, in the shared folder, with the time limit" do
      allow(Monadic::Shell).to receive(:exec).and_return(["", "", double(success?: true)])
      allow(Monadic::Shell).to receive(:bash).and_return(["", "", double(success?: true)])
      MonadicApp.capture_command(%w[python3 code.py], timeout: 180, container: :python)
      MonadicApp.capture_command("echo $PATH", timeout: 30, container: :python)
      expect(Monadic::Shell).to have_received(:exec)
        .with(container: :python, argv: %w[python3 code.py], workdir: "/monadic/data", env: {}, timeout: 180)
      expect(Monadic::Shell).to have_received(:bash)
        .with(container: :python, body: "echo $PATH", workdir: "/monadic/data", env: {}, timeout: 30)
    end
  end

  describe "the command log" do
    it "records a command once, as asked, without the run's mark" do
      Dir.mktmpdir do |dir|
        log = File.join(dir, "command.log")
        allow(Monadic::Shell).to receive(:command_log_file).and_return(log)
        Monadic::Shell.capture(["true", "MONADIC_RUN_ID=abc", "asked"], timeout: 5, log_as: %w[true asked])
        text = File.read(log)
        expect(text.scan("Command:").size).to eq(1)
        expect(text).to include("Command: true asked")
        expect(text).not_to include("MONADIC_RUN_ID")
      end
    end
  end

  describe "send_code" do
    let(:app) { MonadicApp.new }
    let(:calls) { [] }

    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    before do
      stub_const("MonadicApp::LOCAL_SHARED_VOL", @dir)
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@dir)
      allow(Dir).to receive(:home).and_return(@dir)
      FileUtils.mkdir_p(File.join(@dir, "monadic", "data"))
      allow(app).to receive(:sleep)
    end

    it "does not run code again that ran over its time" do
      allow(app).to receive(:capture_command) do |*args, **|
        calls << args
        ["", "Command timed out after 180 seconds.", MonadicApp::TIMED_OUT]
      end
      result = app.send(:send_code, code: "while True: pass", command: "python", extension: "py")
      expect(calls.size).to eq(1)
      expect(result).to include("timed out")
    end

    it "runs code that failed by itself again, up to its retries" do
      allow(app).to receive(:capture_command) do |*args, **|
        calls << args
        ["", "Traceback: boom", OpenStruct.new(success?: false)]
      end
      app.send(:send_code, code: "raise SystemExit(1)", command: "python", extension: "py", max_retries: 2)
      expect(calls.size).to eq(3)
    end
  end

  describe "in the Python container (Docker)" do
    let(:container) { "monadic-chat-python-container" }

    def running?
      `docker inspect -f '{{.State.Running}}' #{container} 2>/dev/null`.strip == "true"
    end

    def marked_in_container?(marker)
      out = `docker exec #{container} sh -c 'cat /proc/[0-9]*/cmdline 2>/dev/null | tr "\\0" " "' 2>/dev/null`
      out.include?(marker)
    end

    it "stops what the code started in the container when the thread running it is killed" do
      skip "the Python container is not running" unless running?

      # The child and its own child in the container, each told apart by its length.
      child = 30_000 + rand(10_000)
      grandchild = child + 1
      script = "sh -c 'sleep #{grandchild}' & sleep #{child}"
      runner = Thread.new { MonadicApp.capture_command(["sh", "-c", script], timeout: 120, container: :python) }
      wait_until(15) { marked_in_container?("sleep #{child}") && marked_in_container?("sleep #{grandchild}") }
      runner.kill
      expect(runner.join(20)).not_to be_nil
      wait_until(10) { !marked_in_container?("sleep #{child}") && !marked_in_container?("sleep #{grandchild}") }
    end
  end
end
