# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "socket"
require "tmpdir"
require_relative "../../../lib/monadic/utils/secret_references"

# config/env may hold 1Password references (op://...) instead of keys. The
# container has no op CLI; the desktop app delivers the values into a tmpfs.
# What must hold: a reference is never used as the key itself (it would go to
# a provider in an Authorization header, naming the vault), an unresolved one
# leaves the key unset, and plain values behave exactly as before. All values
# here are synthetic; no 1Password is involved.
RSpec.describe Monadic::Utils::SecretReferences do
  let(:refs) { described_class }

  around do |example|
    Dir.mktmpdir("secret-refs") do |dir|
      @dir = dir
      refs.reset!
      example.run
      refs.reset!
    end
  end

  def write(name, body)
    File.join(@dir, name).tap { |path| File.write(path, body) }
  end

  describe ".reference?" do
    it "is true only for values that start with op://" do
      expect(refs.reference?("op://Test/A/credential")).to be(true)
      expect(refs.reference?("sk-plain")).to be(false)
      expect(refs.reference?(" op://Test/A/credential")).to be(false)
      expect(refs.reference?(nil)).to be(false)
    end
  end

  describe ".resolve" do
    before { allow(refs).to receive(:resolved).and_return({ "OPENAI_API_KEY" => "fake-resolved" }) }

    it "returns plain values unchanged" do
      expect(refs.resolve("OPENAI_API_KEY", "sk-plain")).to eq("sk-plain")
    end

    it "returns the delivered value for a reference" do
      expect(refs.resolve("OPENAI_API_KEY", "op://Test/OPENAI/credential")).to eq("fake-resolved")
    end

    it "returns nil, never the reference text, when the reference was not resolved" do
      expect(refs.resolve("GEMINI_API_KEY", "op://Vault/GEMINI/credential")).to be_nil
      expect(refs.unresolved_keys([["GEMINI_API_KEY", "op://Vault/GEMINI/credential"], ["A", "plain"]]))
        .to eq(["GEMINI_API_KEY"])
    end
  end

  describe ".read_delivered" do
    it "reads the JSON the app streams into the tmpfs" do
      path = write("env", JSON.generate("OPENAI_API_KEY" => "fake-1", "EMPTY_API_KEY" => ""))
      expect(refs.read_delivered(path)).to eq("OPENAI_API_KEY" => "fake-1")
    end

    it "is empty when nothing was delivered or the file is malformed" do
      expect(refs.read_delivered(File.join(@dir, "absent"))).to eq({})
      expect(refs.read_delivered(write("bad", "{not json"))).to eq({})
    end
  end

  describe ".read_with_op (server running on the host)" do
    # A stand-in op: `inject` replaces each `{{ op://V/ITEM/f }}` in the
    # template with `fake-ITEM` (two lines for "multiline", a trailing CR for "trailingcr"),
    # as op does, fails on an item named "missing", and counts its calls.
    let(:op) do
      write("op", <<~RUBY).tap { |path| File.chmod(0o755, path) }
        #!/usr/bin/env ruby
        File.write("#{@dir}/calls.log", "\#{ARGV[0]}\n", mode: "a")
        input = $stdin.read
        if input.include?("/missing/")
          warn "[ERROR] isn't an item"
          exit 1
        end
        print input.gsub(%r{\{\{ op://[^/]+/([^/]+)/[^ ]+ \}\}}) { { "multiline" => "first\nsecond", "trailingcr" => "end\r" }.fetch($1) { "fake-\#{$1}" } }
      RUBY
    end

    it "reads every reference with one op inject call" do
      values = refs.read_with_op({ "OPENAI_API_KEY" => "op://Test/OPENAI/credential",
                                   "XAI_API_KEY" => "op://Test/XAI/credential" }, op: op)
      expect(values).to eq("OPENAI_API_KEY" => "fake-OPENAI", "XAI_API_KEY" => "fake-XAI")
      expect(File.read(File.join(@dir, "calls.log")).split).to eq(["inject"])
    end

    it "keeps a value that spans lines whole" do
      values = refs.read_with_op({ "SERVICE_PASSWORD" => "op://Test/multiline/password",
                                   "XAI_API_KEY" => "op://Test/XAI/credential" }, op: op)
      expect(values).to eq("SERVICE_PASSWORD" => "first\nsecond", "XAI_API_KEY" => "fake-XAI")
    end

    it "keeps a carriage return that belongs to the value" do
      expect(refs.read_with_op({ "A_PASSWORD" => "op://Test/trailingcr/password" }, op: op)).to eq("A_PASSWORD" => "end\r")
    end

    it "leaves every key unset when op fails" do
      expect(refs.read_with_op({ "A_API_KEY" => "op://Test/missing/credential" }, op: op)).to eq({})
    end

    it "leaves every key unset when op is not installed" do
      expect(refs.read_with_op({ "A_API_KEY" => "op://Test/A/credential" }, op: File.join(@dir, "no-op"))).to eq({})
    end

    # The server's listening socket is shared with the processes it forks,
    # so it is open across exec; the daemon op starts would keep it.
    it "gives op none of the server's descriptors" do
      server = TCPServer.new("127.0.0.1", 0)
      server.close_on_exec = false
      probe = write("probe-op", <<~RUBY).tap { |path| File.chmod(0o755, path) }
        #!/usr/bin/env ruby
        open = begin
          IO.for_fd(#{server.fileno}, autoclose: false)
          "open"
        rescue Errno::EBADF
          "closed"
        end
        File.write("#{@dir}/socket.log", open)
      RUBY
      refs.read_with_op({ "A_API_KEY" => "op://Test/A/credential" }, op: probe)
      expect(File.read(File.join(@dir, "socket.log"))).to eq("closed")
    ensure
      server&.close
    end
  end

  describe ".config_value (scripts that read config/env themselves)" do
    let(:env) do
      write("env", <<~ENV)
        OPENAI_API_KEY=sk-plain
        XAI_API_KEY=op://Test/XAI/credential
        GEMINI_API_KEY="op://Test/GEMINI/credential"
      ENV
    end

    before { allow(refs).to receive(:resolved).and_return({ "XAI_API_KEY" => "fake-xai" }) }

    it "returns plain values, resolves references, and never returns a reference" do
      expect(refs.config_value("OPENAI_API_KEY", env)).to eq("sk-plain")
      expect(refs.config_value("XAI_API_KEY", env)).to eq("fake-xai")
      expect(refs.config_value("GEMINI_API_KEY", env)).to be_nil
      expect(refs.config_value("ABSENT_API_KEY", env)).to be_nil
    end
  end

  describe ".config_value without a file on disk" do
    # CI has no ~/monadic/config/env; specs stub File.read for its path. An
    # existence check before reading bypassed the stub and broke them there
    # while they passed on a machine that has the file.
    it "reads through File.read, so a stubbed read is honoured" do
      path = File.join(@dir, "absent-env")
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(path).and_return("GEMINI_API_KEY=test-key\n")
      expect(refs.config_value("GEMINI_API_KEY", path)).to eq("test-key")
      expect(refs.config_value("GEMINI_API_KEY", File.join(@dir, "really-absent"))).to be_nil
    end
  end

  describe ".setting_value" do
    it "turns plain settings into booleans and numbers" do
      expect(refs.setting_value("EXTRA_LOGGING", "true")).to be(true)
      expect(refs.setting_value("AUTO_TTS_MAX_BYTES", "400")).to eq(400)
      expect(refs.setting_value("SOME_RATE", "1.5")).to eq(1.5)
      expect(refs.setting_value("SOME_NAME", "a\n12")).to eq("a\n12")
    end

    it "keeps credentials as strings, also when they look like numbers or span lines" do
      expect(refs.setting_value("SERVICE_PASSWORD", "0012345678")).to eq("0012345678")
      expect(refs.setting_value("OPENAI_API_KEY", "true")).to eq("true")
      expect(refs.setting_value("SERVICE_PASSWORD", "first\n12345678\nlast")).to eq("first\n12345678\nlast")
    end

    # A setting given as an op:// reference arrives here as the resolved string.
    it "gives a typed setting read from 1Password the type its readers compare against" do
      expect(refs.setting_value("AUTO_TTS_MAX_BYTES", "400")).to eq(400)
      expect(refs.setting_value("WEBSOCKET_PROGRESS_ENABLED", "false")).to be(false)
    end

    it "turns progress off when that setting is read from 1Password as false" do
      require_relative "../../../lib/monadic/utils/websocket"
      stub_const("CONFIG", CONFIG.merge("WEBSOCKET_PROGRESS_ENABLED" => refs.setting_value("WEBSOCKET_PROGRESS_ENABLED", "false")))
      expect(WebSocketHelper.progress_broadcast_enabled?).to be(false)
    end
  end

  describe ".scrub_env!" do
    it "removes references that Dotenv copied into ENV and keeps everything else" do
      env = { "OPENAI_API_KEY" => "op://Test/OPENAI/credential", "XAI_API_KEY" => "xai-plain", "HOME" => "/root" }
      refs.scrub_env!(env)
      expect(env).to eq("XAI_API_KEY" => "xai-plain", "HOME" => "/root")
    end

    it "removes credentials Dotenv set from the file, so child processes do not inherit them" do
      env = { "XAI_API_KEY" => "xai-from-file", "HF_TOKEN" => "hf-from-file", "EXTRA_LOGGING" => "true",
              "GEMINI_API_KEY" => "from-shell", "HOME" => "/root" }
      loaded = { "XAI_API_KEY" => "xai-from-file", "HF_TOKEN" => "hf-from-file", "EXTRA_LOGGING" => "true",
                 "GEMINI_API_KEY" => "from-file" }
      refs.scrub_env!(env, loaded: loaded)
      expect(env).to eq("EXTRA_LOGGING" => "true", "GEMINI_API_KEY" => "from-shell", "HOME" => "/root")
    end

    it "keeps a removed credential known to the redactor, also when Dotenv expanded it" do
      require "dotenv"
      require_relative "../../../lib/monadic/utils/secret_redactor"
      Dir.mktmpdir("scrub") do |dir|
        file = File.join(dir, "env")
        File.write(file, "PLAIN_PART=synthetic-value\nSERVICE_PASSWORD=${PLAIN_PART}-suffix\n")
        parsed = Dotenv.parse(file)
        env = parsed.dup
        refs.scrub_env!(env, loaded: parsed)
        expect(env).not_to have_key("SERVICE_PASSWORD")
        expect(Monadic::Utils::SecretRedactor.redact_values("got synthetic-value-suffix"))
          .to eq("got #{Monadic::Utils::SecretRedactor::REDACTION}")
      end
    ensure
      refs.reset!
    end

    it "uses one credential name rule for child environments and redaction" do
      require_relative "../../../lib/monadic/app"
      expect(MonadicApp::CREDENTIAL_ENV).to equal(refs::CREDENTIAL_NAME)
      require_relative "../../../lib/monadic/utils/secret_redactor"
      expect(Monadic::Utils::SecretRedactor::SENSITIVE_NAME).to equal(refs::CREDENTIAL_NAME)
    end
  end

  # Every script that needs a key must go through config_value; reading
  # config/env directly would hand an op:// reference to the API.
  #
  # Matching only `File.read(".../config/env")` missed two generators that put
  # the path in a variable first. What they all share is picking a key's line
  # out of the file themselves, so that is what this looks for.
  KEY_LINE_PARSE = /start_with\?\(\s*["'][A-Z0-9_]*_API_KEY|["']\^?[A-Z0-9_]*_API_KEY=["']\s*\)/
  ENV_FILE_READ = %r{File\.read\([^)]*monadic/config/env}

  def env_key_readers(root)
    Dir.glob(File.join(root, "{scripts,lib,apps}", "**", "*.rb")).reject { |path| path.end_with?("utils/secret_references.rb") }.select do |path|
      text = File.read(path)
      text.match?(ENV_FILE_READ) || text.match?(KEY_LINE_PARSE)
    end
  end

  it "leaves no script reading API keys from config/env directly" do
    root = File.expand_path("../../..", __dir__)
    expect(env_key_readers(root).map { |p| p.delete_prefix("#{root}/") }).to eq([])
  end

  it "recognises the ways a script has read a key itself" do
    Dir.mktmpdir("key-readers") do |root|
      FileUtils.mkdir_p(File.join(root, "scripts"))
      {
        "path_in_variable.rb" => %(path = "/monadic/config/env"\nFile.read(path).split("\\n").find { |l| l.start_with?("OPENAI_API_KEY=") }),
        "prefix_only.rb" => %(lines.find { |line| line.start_with?("GEMINI_API_KEY") }),
        "direct_read.rb" => %(File.read("\#{Dir.home}/monadic/config/env")),
        "uses_helper.rb" => %(Monadic::Utils::SecretReferences.config_value("XAI_API_KEY"))
      }.each { |name, body| File.write(File.join(root, "scripts", name), body) }

      found = env_key_readers(root).map { |p| File.basename(p) }.sort
      expect(found).to eq(%w[direct_read.rb path_in_variable.rb prefix_only.rb])
    end
  end
end
