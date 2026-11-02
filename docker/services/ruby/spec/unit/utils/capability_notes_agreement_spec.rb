# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"
require "shellwords"

# The capability note and the tools it reports on agree. For each setup the
# note is built the way the app builds it, and each tool is then called
# through its real code: the speech command as the child process it is, the
# document readers through docker, image analysis in the server's process.
#
# The check runs in a process of its own, started with only the variables
# Ruby and Bundler need, a HOME and config file of its own, a fake docker on
# PATH and Ruby's network connections stopped once its gems are set up
# (spec/support/capability_agreement). This file
# does not load spec_helper, which reads a config file when it loads.
#
# The expectations come from where each tool reads what it needs: the speech
# command reads the config file (its environment has no credentials), image
# analysis reads the server's settings, the readers need the Python
# container. A request is stopped where it would leave the process, so
# "reached the network" is as far as a call can get here. "Ready" in the
# note means its checks passed, not that the call works: a reader can still
# fail after a "ready".
RSpec.describe "Capability note and tools agree" do
  support = File.expand_path("../../support/capability_agreement", __dir__)
  time_limit = 300 # seconds for the whole check

  # What the check's process needs to find its gems. It reads no Bundler
  # config file (BUNDLE_IGNORE_CONFIG): the settings that place and select
  # the gems are passed as they stand in this process.
  bundler_env = lambda do
    env = ENV.to_h.slice("BUNDLE_GEMFILE", "GEM_HOME", "GEM_PATH")
    if defined?(Bundler)
      { path: "BUNDLE_PATH", without: "BUNDLE_WITHOUT", with: "BUNDLE_WITH", deployment: "BUNDLE_DEPLOYMENT" }
        .each do |setting, name|
          value = Bundler.settings[setting]
          value = File.expand_path(value, Bundler.root) if setting == :path && value
          value = Array(value).join(":") if value.is_a?(Array)
          env[name] = value.to_s unless value.nil? || value.to_s.empty?
        end
    end
    env.merge("BUNDLE_IGNORE_CONFIG" => "1")
  end

  running_ok = { "container" => "running", "reader" => { "status" => 0, "stdout" => "Document body" } }
  file_keys = { "OPENAI_API_KEY" => "fake-openai", "GEMINI_API_KEY" => "fake-gemini",
                "ELEVENLABS_API_KEY" => "fake-elevenlabs" }
  reference = { "OPENAI_API_KEY" => "op://Vault/Item/field" }

  cases = [
    { "name" => "keys in the config file", "file" => file_keys, "config" => file_keys, "docker" => running_ok },
    { "name" => "keys only in the server", "file" => {}, "config" => file_keys, "docker" => running_ok },
    { "name" => "no keys", "file" => {}, "config" => {}, "docker" => running_ok },
    { "name" => "blank key in the config file", "file" => { "OPENAI_API_KEY" => "   " }, "config" => {},
      "docker" => running_ok },
    { "name" => "reference that resolves", "file" => reference, "config" => { "OPENAI_API_KEY" => "fake-resolved" },
      "op" => :fake_op, "docker" => running_ok },
    { "name" => "reference that does not resolve", "file" => reference, "config" => {}, "docker" => running_ok },
    { "name" => "converter fails", "file" => file_keys, "config" => file_keys,
      "docker" => { "container" => "running", "reader" => { "status" => 1, "stdout" => "" } } },
    { "name" => "converter reports an error on stdout", "file" => file_keys, "config" => file_keys,
      "docker" => { "container" => "running", "reader" => { "status" => 0, "stdout" => "Error: cannot parse" } } },
    { "name" => "container stopped", "file" => file_keys, "config" => file_keys,
      "docker" => running_ok.merge("container" => "stopped") },
    { "name" => "container missing", "file" => file_keys, "config" => file_keys,
      "docker" => running_ok.merge("container" => "missing") },
    { "name" => "container restarting", "file" => file_keys, "config" => file_keys,
      "docker" => running_ok.merge("container" => "restarting") },
    { "name" => "docker not answering", "file" => file_keys, "config" => file_keys,
      "docker" => running_ok.merge("container" => "no_daemon") }
  ]

  let(:hosts) do
    { "openai" => "api.openai.com", "gemini" => "generativelanguage.googleapis.com",
      "elevenlabs" => "api.elevenlabs.io" }
  end
  let(:key_names) do
    { "openai" => "OPENAI_API_KEY", "gemini" => "GEMINI_API_KEY", "elevenlabs" => "ELEVENLABS_API_KEY" }
  end
  # The commands the readers run in the Python container, for the files above.
  let(:reader_contract) do
    ["pdf2txt.py /monadic/data/doc.pdf --format md --all-pages", "office2txt.py /monadic/data/doc.docx"]
  end

  before(:all) do
    @dir = File.realpath(Dir.mktmpdir("capability-agreement-"))
    home = File.join(@dir, "home")
    data = File.join(home, "monadic", "data")
    config_dir = File.join(home, "monadic", "config")
    bin = File.join(@dir, "bin")
    FileUtils.mkdir_p([data, config_dir, bin])
    File.write(File.join(config_dir, "env"), "")
    File.write(File.join(data, "doc.pdf"), "%PDF-1.4\n")
    File.write(File.join(data, "doc.docx"), "PK")
    # A 1x1 PNG
    File.binwrite(File.join(data, "pic.png"), ["89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489" \
                                                 "0000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082"].pack("H*"))

    docker = File.join(bin, "docker")
    File.write(docker, "#!/bin/sh\nexec env -u RUBYOPT -u RUBYLIB #{Shellwords.escape(RbConfig.ruby)} --disable-gems " \
                       "#{Shellwords.escape(File.join(support, 'fake_docker.rb'))} \"$@\"\n")
    # Answers `op inject` with a fixed value for every reference.
    fake_op = File.join(bin, "fake-op")
    File.write(fake_op, "#!/bin/sh\nsed -E 's/[{][{] op:[^}]* [}][}]/fake-resolved/'\n")
    [docker, fake_op].each { |f| File.chmod(0o755, f) }

    with_op = cases.map { |c| c.merge("op" => c["op"] == :fake_op ? fake_op : "/usr/bin/false") }
    File.write(File.join(@dir, "cases.json"), JSON.generate(with_op))

    env = bundler_env.call.merge(
      "HOME" => home,
      "PATH" => [bin, RbConfig::CONFIG["bindir"], "/usr/bin", "/bin"].join(":"),
      "LANG" => "C.UTF-8",
      "IN_CONTAINER" => "false",
      "RUBYLIB" => File.dirname(support),
      "RUBYOPT" => "-rbundler/setup -rcapability_agreement/no_network",
      "MONADIC_TEST_NET_EVENTS" => File.join(@dir, "events"),
      "MONADIC_TEST_DOCKER_LOG" => File.join(@dir, "docker.log"),
      "MONADIC_TEST_DOCKER_STATE" => File.join(@dir, "docker.json")
    )
    results = File.join(@dir, "results.json")
    argv = [RbConfig.ruby, File.join(support, "driver.rb"), File.join(@dir, "cases.json"), results]
    service_root = File.expand_path("../../..", __dir__)
    # Set here, outside: the check's process must start without it, and
    # without the credentials of the shell that runs the specs.
    outer = "MONADIC_TEST_OUTER_MARKER"
    marker_before = ENV[outer]
    ENV[outer] = "outside"
    clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    deadline = clock.call + time_limit
    begin
      Open3.popen3(env, *argv, unsetenv_others: true, pgroup: true, chdir: service_root) do |stdin, out, err, wait|
        stdin.close
        output = [out, err].map { |io| Thread.new { io.read } }
        stop = lambda do
          Process.kill("KILL", -wait.pid)
        rescue Errno::ESRCH
          nil
        end
        finished = wait.join(time_limit)
        stop.call && wait.join(5) unless finished
        # The output is read until the same deadline, then a short grace: a
        # process the check started can hold it open after the check ends.
        # Output still open then counts as not finished.
        read = output.map { |t| t.join([deadline - clock.call, 5].max) ? t.value.to_s : nil }
        unless read.all?
          finished = false
          stop.call
          output.each(&:kill)
        end
        error = read.last.to_s
        error = error[-3000..] || error
        raise "the agreement check did not finish within #{time_limit} seconds:\n#{error}" unless finished
        raise "the agreement check failed (exit #{wait.value.exitstatus}):\n#{error}" unless wait.value.success?
      end
    ensure
      ENV[outer] = marker_before
    end

    @results = JSON.parse(File.read(results))
  end

  after(:all) { FileUtils.rm_rf(@dir) if @dir }

  def result(name)
    @results.fetch("cases").find { |c| c["name"] == name } || raise("no result for #{name}")
  end

  def note_line(name, start)
    result(name)["note"].lines(chomp: true).find { |l| l.start_with?("- #{start}") }
  end

  # The speech command found its key: it got as far as the network.
  def expect_speech_reached_network(name, provider)
    call = result(name).dig("speech", provider)
    expect(call["loaded"]).to eq(["tts_query.rb"])
    expect(call["request"]).to eq([hosts.fetch(provider)])
    expect(call["text"]).not_to include("is not set")
  end

  # The speech command found no key: it said so and sent nothing.
  def expect_speech_refused(name, provider)
    call = result(name).dig("speech", provider)
    expect(call["loaded"]).to eq(["tts_query.rb"])
    expect(call["request"]).to be_empty
    expect(call["text"]).to include("#{key_names.fetch(provider)} is not set")
  end

  describe "the check itself" do
    it "started with only the environment it was given" do
      expect(@results["leaked_env"]).to be_empty
    end

    it "ran every case, with the network stopped from the start" do
      expect(@results["cases"].map { |c| c["name"] }).to eq(cases.map { |c| c["name"] })
      expect(@results.dig("startup", "loaded")).to eq(["driver.rb"])
    end

    it "saw no connection get past the stops, in any case" do
      phases = @results["cases"].flat_map do |c|
        [c["setup_events"], c["note_events"], c["reader_events"], c["image"], *c["speech"].values]
      end
      expect([@results["startup"], *phases].flat_map { |events| events["socket"] }).to be_empty
    end

    it "sent nothing while building the note" do
      expect(@results["cases"].flat_map { |c| c.dig("note_events", "request") }).to be_empty
    end

    it "gave docker only the commands the readers should send" do
      @results["cases"].each do |c|
        bodies = c["reader_calls"].map do |argv|
          expect(argv.first(6)).to eq(["exec", "-w", "/monadic/data", "monadic-chat-python-container", "bash", "-c"])
          argv[6].split("; ").last
        end
        expect(bodies).to eq(reader_contract), c["name"]
      end
    end
  end

  describe "speech" do
    it "is ready, and reaches the network, for each provider whose key is in the config file" do
      %w[openai elevenlabs gemini].each do |provider|
        expect(note_line("keys in the config file", "Speech")).to include("#{provider} ready")
        expect_speech_reached_network("keys in the config file", provider)
      end
    end

    it "is not available, and refuses, when only the server has the keys, or no one does" do
      ["keys only in the server", "no keys"].each do |name|
        %w[openai elevenlabs gemini].each do |provider|
          expect(note_line(name, "Speech")).to include("#{provider} not available (#{key_names[provider]} is not set)")
          expect_speech_refused(name, provider)
        end
      end
    end

    it "takes a blank key in the config file for no key" do
      expect(note_line("blank key in the config file", "Speech")).to include("openai not available")
      expect_speech_refused("blank key in the config file", "openai")
    end

    it "follows a 1Password reference the same way in the note and the command" do
      line = note_line("reference that resolves", "Speech")
      expect(line).to include("openai ready", "gemini not available", "elevenlabs not available")
      expect_speech_reached_network("reference that resolves", "openai")
      expect_speech_refused("reference that resolves", "gemini")

      expect(note_line("reference that does not resolve", "Speech")).to include("openai not available")
      expect_speech_refused("reference that does not resolve", "openai")
    end
  end

  describe "image analysis" do
    it "is ready, and reaches the network, with the key only in the server, which is where it runs" do
      expect(note_line("keys only in the server", "Image analysis")).to include("ready")
      expect(result("keys only in the server")["image"]["request"]).to eq([hosts["openai"]])
    end

    it "is not available, and sends nothing, without the key" do
      expect(note_line("no keys", "Image analysis")).to include("not available")
      expect(result("no keys")["image"]["request"]).to be_empty
      expect(result("no keys")["image"]["text"]).to include("OPENAI_API_KEY")
    end
  end

  describe "document readers" do
    it "is ready, and reads, when the container takes commands" do
      expect(note_line("keys in the config file", "Reading documents")).to include("ready: the Python container is running")
      expect(result("keys in the config file")["readers"]).to eq("pdf" => "Document body", "office" => "Document body")
    end

    it "can still fail after ready: the check does not run the converter" do
      ["converter fails", "converter reports an error on stdout"].each do |name|
        expect(note_line(name, "Reading documents")).to include("ready: the Python container is running")
        expect(result(name)["readers"].values).to all(start_with("Error:"))
      end
    end

    it "is not ready, and the readers fail in docker, when the container is stopped or gone" do
      ["container stopped", "container missing"].each do |name|
        expect(note_line(name, "Reading documents")).to include("not ready: the Python container is not running")
        expect(result(name)["probe_calls"].map(&:first)).to eq(["inspect"])
        expect(result(name)["readers"].values).to all(start_with("Error"))
      end
    end

    it "says neither ready nor stopped when docker gives no clear answer" do
      ["container restarting", "docker not answering"].each do |name|
        line = note_line(name, "Reading documents")
        expect(line).to include("could not be checked")
        expect(line).not_to include("ready: the Python container is running", "not running")
      end
    end
  end
end
