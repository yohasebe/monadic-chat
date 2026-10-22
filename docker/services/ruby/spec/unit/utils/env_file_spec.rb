# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../../../lib/monadic/utils/env_file"
require_relative "../../../lib/monadic/utils/secret_references"

# The config env file is read for its settings, not as an environment:
# nothing in it is run, what decides where requests go or what program runs
# is never taken from it, and only what the code reads from ENV is put there.
RSpec.describe Monadic::Utils::EnvFile do
  around do |example|
    Dir.mktmpdir("env-file") do |dir|
      @dir = File.realpath(dir)
      @shared = File.join(@dir, "data")
      FileUtils.mkdir_p(@shared)
      example.run
    end
  end

  before { stub_const("#{described_class}::SHARED_FOLDERS", [@shared]) }

  def env_file(text)
    File.join(@dir, "env").tap { |path| File.write(path, text) }
  end

  def load(path, env = {})
    described_class.load!(path, env: env, out: StringIO.new)
  end

  describe "parsing" do
    it "reads plain, quoted and exported values, and comments, as Dotenv does" do
      path = env_file(<<~'ENV')
        # a comment
        export UI_LANGUAGE=ja
        A=plain value # trailing comment
        B='single #not a comment'
        C="line\nnext \"q\""
        D=
      ENV
      expect(described_class.parse(path)).to eq("UI_LANGUAGE" => "ja", "A" => "plain value",
                                                "B" => "single #not a comment", "C" => "line\\nnext \"q\"", "D" => "")
    end

    it "reads what Dotenv read: a BOM, KEY: value, a # after a value, CR line ends, quotes over lines" do
      path = File.join(@dir, "env")
      File.binwrite(path, "\xEF\xBB\xBFOPENAI_API_KEY=first\nUI_LANGUAGE: ja\nA=value#comment\rB=true\n" \
                          "NOTE=\"one\nEXTRA_LOGGING=true\ntwo\"\nS='it\\'s'\n")
      expect(described_class.parse(path)).to eq("OPENAI_API_KEY" => "first", "UI_LANGUAGE" => "ja", "A" => "value", "B" => "true",
                                                "NOTE" => "one\nEXTRA_LOGGING=true\ntwo", "S" => "it\\'s")
    end

    it "uses no value whose quote is never closed, nor anything after it, and names its key" do
      ["NOTE=\"never closed\n", "NOTE='never closed\n", "NOTE=\"\n"].each do |opening|
        path = env_file("UI_LANGUAGE=ja\n#{opening}EXTRA_LOGGING=true\nGEMINI_API_KEY=after\n")
        out = StringIO.new
        env = {}
        accepted = described_class.load!(path, env: env, out: out)
        expect(accepted).to eq("UI_LANGUAGE" => "ja"), opening
        expect(env).to eq("UI_LANGUAGE" => "ja")
        expect(Monadic::Utils::SecretReferences.config_value("GEMINI_API_KEY", path)).to be_nil
        expect(out.string).to include("NOTE")
        expect(out.string).not_to include("never closed", "after")
      end
    end

    it "gives the scripts the same credential as the server" do
      path = env_file("export OPENAI_API_KEY=sk-test # label\nGEMINI_API_KEY='g-test'\n")
      %w[OPENAI_API_KEY GEMINI_API_KEY].each do |key|
        expect(Monadic::Utils::SecretReferences.config_value(key, path)).to eq(described_class.accepted(path)[key])
      end
      expect(described_class.accepted(path)["OPENAI_API_KEY"]).to eq("sk-test")
    end

    it "runs nothing and expands nothing, whatever the key" do
      marker = File.join(@dir, "ran")
      path = env_file(<<~ENV)
        EXTRA_LOGGING=$(touch #{marker})
        https_proxy=$(touch #{marker})
        SOME_SETTING=`touch #{marker}`
        UI_LANGUAGE=${HOME}
      ENV
      env = { "EXTRA_LOGGING" => "shell" }
      accepted = load(path, env)
      expect(File.exist?(marker)).to be(false)
      expect(accepted).to include("SOME_SETTING" => "`touch #{marker}`", "UI_LANGUAGE" => "${HOME}")
      expect(env["EXTRA_LOGGING"]).to eq("shell")
    end
  end

  it "never takes a proxy, a service address or a program path, and names (never shows) what it left out" do
    path = env_file(<<~ENV)
      https_proxy=http://elsewhere:8080
      HTTPS_PROXY=http://elsewhere:8080
      QDRANT_URL=http://elsewhere:6333
      MONADIC_OP_CLI=/tmp/run-me
      OPENAI_API_KEY=k
    ENV
    env = {}
    out = StringIO.new
    accepted = described_class.load!(path, env: env, out: out)
    expect(accepted.keys).to eq(["OPENAI_API_KEY"])
    expect(env.keys).to eq(["OPENAI_API_KEY"])
    expect(out.string).to include("https_proxy", "QDRANT_URL", "MONADIC_OP_CLI")
    expect(out.string).not_to include("elsewhere")
  end

  it "takes no setting named like an address, a program or an unchecked file" do
    path = env_file(<<~ENV)
      OLLAMA_HOST=http://elsewhere:11434
      SEARCH_ENDPOINT=https://elsewhere/
      CUSTOM_BASE_URL=https://elsewhere/
      MY_TOOL_CMD=/tmp/run-me
      NOTES_PATH=/etc/passwd
      UI_LANGUAGE=ja
      GEMINI_API_KEY=k
    ENV
    expect(described_class.accepted(path).keys).to eq(%w[UI_LANGUAGE GEMINI_API_KEY])
  end

  it "loses no setting the code reads from CONFIG by name to those forms" do
    files = Dir.glob(File.join(ruby_root, "{lib,apps,scripts}", "**", "*.rb"))
    names = files.flat_map do |file|
      File.read(file).scan(/CONFIG(?:\[|\.fetch\(|\.dig\(|\.key\?\()["']([A-Za-z0-9_]+)["']/).flatten
    end.uniq
    expect(names.size).to be > 30
    lost = names.select do |name|
      !described_class::REFUSED.include?(name) && !described_class::PORT_KEYS.include?(name) &&
        !described_class::PATH_KEYS.key?(name) && described_class.usable(name, "x").nil?
    end
    expect(lost).to be_empty, "read from CONFIG but refused by name: #{lost.sort.join(', ')}"
  end

  it "takes a port only as a number from 1 to 65535" do
    path = env_file(<<~ENV)
      EMBEDDINGS_DEV_PORT=80@example.invalid
      QDRANT_DEV_PORT=6333
      EXTRACTOR_DEV_PORT=0
      PRIVACY_DEV_PORT=70000
      JUPYTER_PORT=8889x
      MCP_SERVER_PORT= 3100
    ENV
    expect(described_class.accepted(path)).to eq("QDRANT_DEV_PORT" => "6333", "MCP_SERVER_PORT" => "3100")
  end

  describe "settings that name a file" do
    it "takes an existing file or folder outside the shared folder, as its real path" do
      ca = File.join(@dir, "ca.pem")
      File.write(ca, "pem")
      File.symlink(ca, File.join(@dir, "ca-link.pem"))
      path = env_file("SSL_CERT_FILE=#{File.join(@dir, 'ca-link.pem')}\nSSL_CERT_DIR=#{@dir}\n")
      expect(described_class.accepted(path)).to eq("SSL_CERT_FILE" => ca, "SSL_CERT_DIR" => @dir)
    end

    it "leaves out one in the shared folder, behind a link into it, leading nowhere, relative, or of the wrong kind" do
      File.write(File.join(@shared, "ca.pem"), "pem")
      File.symlink(@shared, File.join(@dir, "innocent"))
      File.symlink(File.join(@shared, "future.pem"), File.join(@dir, "dangling.pem"))
      File.write(File.join(@dir, "relative.pem"), "pem")
      path = env_file(<<~ENV)
        SSL_CERT_FILE=#{File.join(@shared, 'ca.pem')}
        SSL_CERT_DIR=#{File.join(@dir, 'innocent')}
        HELP_DATA_DUMP=#{File.join(@dir, 'dangling.pem')}
        TTS_DICT_PATH=relative.pem
      ENV
      # Relative to the folder it runs in, relative.pem exists outside the shared folder.
      expect(Dir.chdir(@dir) { described_class.accepted(path) }).to be_empty
      path = env_file("SSL_CERT_DIR=#{File.join(@dir, 'relative.pem')}\nSSL_CERT_FILE=op://Vault/item/field\n")
      expect(described_class.accepted(path)).to be_empty
    end
  end

  it "puts in ENV only what the code reads from it, and leaves the shell's values alone" do
    path = env_file("EXTRA_LOGGING=true\nGEMINI_DEFAULT_MODEL=g\nSOME_APP_SETTING=x\nUI_LANGUAGE=ja\n")
    env = { "UI_LANGUAGE" => "en" }
    accepted = load(path, env)
    expect(accepted).to include("SOME_APP_SETTING" => "x", "UI_LANGUAGE" => "ja")
    expect(env).to eq("EXTRA_LOGGING" => "true", "GEMINI_DEFAULT_MODEL" => "g", "UI_LANGUAGE" => "en")
  end

  it "reads nothing without a file" do
    expect(load(File.join(@dir, "missing"))).to eq({})
  end

  # Settings the process gets from its own environment (the shell, compose,
  # the operating system), never from the config file.
  let(:process_only) { %w[USERPROFILE IN_CONTAINER RACK_ENV] }
  let(:ruby_root) { File.expand_path("../../..", __dir__) }

  it "knows every setting the code reads from ENV by name" do
    files = Dir.glob(File.join(ruby_root, "{lib,apps,scripts}", "**", "*.rb")) + [File.join(ruby_root, "config.ru")]
    names = files.flat_map do |file|
      File.read(file).scan(/ENV(?:\[|\.fetch\(|\.key\?\()["']([A-Za-z0-9_]+)["']/).flatten
    end.uniq
    expect(names.size).to be > 30
    unknown = names.reject do |name|
      described_class.env_key?(name) || described_class::REFUSED.include?(name) || process_only.include?(name)
    end
    expect(unknown).to be_empty, "read from ENV but not in EnvFile: #{unknown.sort.join(', ')}"
  end

  it "is the only reader of the config env file that loads it into the environment" do
    repo = File.expand_path("../../..", ruby_root)
    top = Dir.glob(File.join(repo, "{rakelib,lib}", "**", "*.{rb,rake}")) + Dir.glob(File.join(repo, "bin", "*"))
    expect(top).to include(File.join(repo, "rakelib", "server.rake"), File.join(repo, "lib", "test_runner.rb"))
    files = Dir.glob(File.join(ruby_root, "{lib,apps,scripts}", "**", "*.rb")) + top.select { |f| File.file?(f) } +
            [File.join(ruby_root, "config.ru")]
    expect(files.size).to be > 200
    using = files.select { |file| File.read(file).match?(/^\s*[^#\n]*Dotenv\.(?:load|overload|parse)/) }
    expect(using.map { |f| f.delete_prefix("#{repo}/") }).to be_empty
  end
end
