# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"
require "rbconfig"
require "shellwords"
require_relative "../../support/capability_agreement/isolated_run"

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
# "reached the network" is as far as a call can get here (which key it
# carried is not looked at: the check is whether a key was found). "Ready" in the
# note means its checks passed, not that the call works: a reader can still
# fail after a "ready".
#
# The cases marked "container" run the same way as if in the container: the
# container's paths and the file the desktop app delivers resolved
# 1Password references into are placed in a folder of the check's own
# (container_paths.rb). This is the container's branch of the code, not a
# run in a real container.
RSpec.describe "Capability note and tools agree" do
  support = File.expand_path("../../support/capability_agreement", __dir__)
  time_limit = 300 # seconds for the whole check

  running_ok = { "container" => "running", "reader" => { "status" => 0, "stdout" => "Document body" } }
  file_keys = { "OPENAI_API_KEY" => "fake-openai", "GEMINI_API_KEY" => "fake-gemini",
                "ELEVENLABS_API_KEY" => "fake-elevenlabs" }
  reference = { "OPENAI_API_KEY" => "op://Vault/Item/field" }
  container_file = reference.merge("GEMINI_API_KEY" => "fake-gemini")

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
      "docker" => running_ok.merge("container" => "no_daemon") },
    { "name" => "container: reference delivered", "file" => container_file, "config" => {}, "op" => :recording_op,
      "docker" => running_ok,
      "container" => { "delivered" => JSON.generate("OPENAI_API_KEY" => "fake-delivered",
                                                    "ELEVENLABS_API_KEY" => "fake-elevenlabs") } },
    { "name" => "container: nothing delivered", "file" => container_file, "config" => {}, "op" => :recording_op,
      "docker" => running_ok, "container" => { "delivered" => nil } },
    { "name" => "container: delivered file malformed", "file" => container_file, "config" => {},
      "op" => :recording_op, "docker" => running_ok, "container" => { "delivered" => "{not json" } },
    { "name" => "container: delivered value empty", "file" => container_file, "config" => {}, "op" => :recording_op,
      "docker" => running_ok, "container" => { "delivered" => JSON.generate("OPENAI_API_KEY" => "") } },
    { "name" => "container: reference removed after start", "started" => { "file" => container_file, "op" => :recording_op },
      "file" => container_file.except("OPENAI_API_KEY"), "config" => {}, "op" => :recording_op, "docker" => running_ok,
      "container" => { "delivered" => JSON.generate("OPENAI_API_KEY" => "fake-delivered") } },
    { "name" => "container: reference changed after start", "started" => { "file" => container_file, "op" => :recording_op },
      "file" => container_file.merge("OPENAI_API_KEY" => "op://Vault/Other/field"), "config" => {}, "op" => :recording_op,
      "docker" => running_ok, "container" => { "delivered" => JSON.generate("OPENAI_API_KEY" => "fake-delivered") } }
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
    container_root = File.join(@dir, "container")
    FileUtils.mkdir_p([data, config_dir, bin, File.join(container_root, "monadic", "data"),
                       File.join(container_root, "monadic", "config"), File.join(container_root, "run", "monadic-secrets")])
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
    # Notes each time it is started, and resolves nothing.
    @op_log = File.join(@dir, "op.log")
    recording_op = File.join(bin, "recording-op")
    File.write(recording_op, "#!/bin/sh\necho started >> #{Shellwords.escape(@op_log)}\nexit 1\n")
    [docker, fake_op, recording_op].each { |f| File.chmod(0o755, f) }

    ops = { fake_op: fake_op, recording_op: recording_op }
    with_op = cases.map do |c|
      c = c.merge("op" => ops.fetch(c["op"], "/usr/bin/false"))
      c["started"] &&= c["started"].merge("op" => ops.fetch(c["started"]["op"], "/usr/bin/false"))
      c
    end
    File.write(File.join(@dir, "cases.json"), JSON.generate(with_op))

    env = CapabilityAgreement::IsolatedRun.env(home: home, bin: bin, events: File.join(@dir, "events"),
                                               preload: ["container_paths"]).merge(
      "MONADIC_TEST_CONTAINER_ROOT" => container_root,
      "MONADIC_TEST_DOCKER_LOG" => File.join(@dir, "docker.log"),
      "MONADIC_TEST_DOCKER_STATE" => File.join(@dir, "docker.json")
    )
    results = File.join(@dir, "results.json")
    argv = [RbConfig.ruby, File.join(support, "driver.rb"), File.join(@dir, "cases.json"), results]
    CapabilityAgreement::IsolatedRun.run(env, argv, chdir: File.expand_path("../../..", __dir__), time_limit: time_limit)

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
        [c["setup_events"], c["note_events"], c["reader_events"], c["image"], *c["speech"].values].compact
      end
      expect([@results["startup"], *phases].flat_map { |events| events["socket"] }).to be_empty
    end

    it "sent nothing while building the note" do
      expect(@results["cases"].flat_map { |c| c.dig("note_events", "request") }).to be_empty
    end

    it "gave docker only the commands the readers should send" do
      @results["cases"].reject { |c| c["container"] }.each do |c|
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

  describe "speech inside the container" do
    it "uses the value delivered for a reference, in the note and the command" do
      name = "container: reference delivered"
      expect(note_line(name, "Speech")).to include("openai ready", "gemini ready", "elevenlabs not available")
      expect_speech_reached_network(name, "openai")
      expect_speech_reached_network(name, "gemini")
      expect_speech_refused(name, "elevenlabs")
    end

    it "has no key for a reference when nothing usable was delivered" do
      ["container: nothing delivered", "container: delivered file malformed", "container: delivered value empty"].each do |name|
        expect(note_line(name, "Speech")).to include("openai not available", "gemini ready")
        expect_speech_refused(name, "openai")
        expect_speech_reached_network(name, "gemini")
      end
    end

    it "keeps to what was delivered when the config file changes while the server runs" do
      removed = "container: reference removed after start"
      expect(note_line(removed, "Speech")).to include("openai not available")
      expect_speech_refused(removed, "openai")
      # The delivered values stay until the container starts again.
      changed = "container: reference changed after start"
      expect(note_line(changed, "Speech")).to include("openai ready")
      expect_speech_reached_network(changed, "openai")
    end

    it "never starts op" do
      expect(@results["cases"].count { |c| c["container"] }).to eq(6)
      expect(File.exist?(@op_log)).to be(false)
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
