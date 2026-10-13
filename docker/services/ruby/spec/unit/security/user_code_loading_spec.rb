# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "dotenv"
require "open3"
require "rbconfig"
require_relative "../../../lib/monadic/utils/shared_path_guard"
require_relative "../../../lib/monadic/dsl"

# In development mode the server runs on the host, where the read-only mounts
# that keep model-run code out of apps and helpers do not apply. It loads
# custom apps and helpers there only when the shell that starts it asks.
RSpec.describe "Monadic::Utils::SharedPathGuard.user_code_files" do
  let(:guard) { Monadic::Utils::SharedPathGuard }

  around do |example|
    Dir.mktmpdir("user-code-") do |dir|
      @root = File.realpath(dir)
      @helpers = File.join(@root, "helpers")
      FileUtils.mkdir_p(@helpers)
      @file = File.join(@helpers, "a.rb")
      File.write(@file, "x")
      saved = ENV.fetch("MONADIC_LOAD_USER_CODE", nil)
      example.run
    ensure
      ENV["MONADIC_LOAD_USER_CODE"] = saved
    end
  end

  before do
    guard.instance_variable_set(:@told_user_code_skipped, nil)
    guard.instance_variable_set(:@told_user_code_flag_ignored, nil)
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with("/.dockerenv").and_return(false)
    @home = File.join(@root, "home")
    FileUtils.mkdir_p(File.join(@home, "monadic", "config"))
    allow(Etc).to receive(:getpwuid).and_return(Struct.new(:dir).new(@home))
  end

  it "loads them in the container" do
    allow(File).to receive(:file?).with("/.dockerenv").and_return(true)
    ENV.delete("MONADIC_LOAD_USER_CODE")
    expect(guard.user_code_files(@helpers, "*.rb")).to eq([@file])
  end

  it "loads none in development mode, and says how to load them" do
    ENV.delete("MONADIC_LOAD_USER_CODE")
    expect { expect(guard.user_code_files(@helpers, "*.rb")).to eq([]) }
      .to output(/MONADIC_LOAD_USER_CODE=true in the shell/).to_stdout
  end

  it "loads them in development mode when the shell asks" do
    ENV["MONADIC_LOAD_USER_CODE"] = "true"
    expect(guard.user_code_files(@helpers, "*.rb")).to eq([@file])
  end

  # rake server:debug reads the config env file into ENV before it starts
  # the server, so there the value is in ENV either way: the file decides.
  # Each form here is one Dotenv reads as setting the flag; read it with
  # Dotenv itself, then ask the guard.
  {
    "a plain line" => "MONADIC_LOAD_USER_CODE=true\n",
    "a colon" => "MONADIC_LOAD_USER_CODE: true\n",
    "a BOM" => "\uFEFFMONADIC_LOAD_USER_CODE=true\n",
    "CR line ends" => "A=x\rMONADIC_LOAD_USER_CODE=true\r",
    "export and spaces" => "  export MONADIC_LOAD_USER_CODE = true\n"
  }.each do |form, text|
    it "is not turned on by the config env file (#{form})" do
      ENV.delete("MONADIC_LOAD_USER_CODE")
      file = File.join(@home, "monadic", "config", "env")
      File.binwrite(file, text)
      Dotenv.load(file)
      expect(ENV.fetch("MONADIC_LOAD_USER_CODE", nil)).to eq("true") # Dotenv did set it
      expect { expect(guard.user_code_files(@helpers, "*.rb")).to eq([]) }
        .to output(/remove it from that file/).to_stdout
    end
  end

  it "looks at the config file under HOME as well as the account's home" do
    other = File.join(@root, "other-home")
    FileUtils.mkdir_p(File.join(other, "monadic", "config"))
    File.write(File.join(other, "monadic", "config", "env"), "MONADIC_LOAD_USER_CODE=true\n")
    ENV["MONADIC_LOAD_USER_CODE"] = "true"
    saved_home = ENV.fetch("HOME", nil)
    ENV["HOME"] = other
    expect(guard.user_code_asked_for_on_host?).to be(false)
  ensure
    ENV["HOME"] = saved_home
  end

  it "does not take IN_CONTAINER from ENV for the container" do
    ENV.delete("MONADIC_LOAD_USER_CODE")
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(true)
    expect(guard.user_code_files(@helpers, "*.rb")).to eq([])
  end
end

RSpec.describe "Files the server loads as code" do
  let(:guard) { Monadic::Utils::SharedPathGuard }

  around do |example|
    Dir.mktmpdir("code-file-") do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  it "skips a hard link: the same file may be written from elsewhere" do
    helpers = File.join(@root, "helpers")
    FileUtils.mkdir_p(helpers)
    File.write(File.join(@root, "ordinary.txt"), "x")
    File.link(File.join(@root, "ordinary.txt"), File.join(helpers, "linked.rb"))
    File.write(File.join(helpers, "plain.rb"), "x")
    expect(guard.code_files(helpers, "*.rb")).to eq([File.join(helpers, "plain.rb")])
  end

  # The DSL loader also loads <app>_tools.rb and <app>_constants.rb beside an
  # app file it was given: under the same rule.
  it "does not load a linked tools file beside an app" do
    app_dir = File.join(@root, "apps", "demo")
    FileUtils.mkdir_p(app_dir)
    File.write(File.join(app_dir, "demo_openai.mdsl"), 'app "DemoOpenAI" do; end')
    File.write(File.join(@root, "elsewhere.rb"), "$adjacent_link_loaded = true")
    File.symlink(File.join(@root, "elsewhere.rb"), File.join(app_dir, "demo_tools.rb"))
    File.write(File.join(app_dir, "demo_constants.rb"), "$adjacent_plain_loaded = true")

    expect { MonadicDSL::Loader.load(File.join(app_dir, "demo_openai.mdsl")) }
      .to output(/Not loading demo_tools\.rb/).to_stderr
    expect($adjacent_link_loaded).to be_nil
    expect($adjacent_plain_loaded).to be(true)
  end
end

# rake server:debug reads the config env file before it starts the server;
# what it passes on must carry the flag only when the shell set it. Run the
# task's own lines that do this.
RSpec.describe "rake server:debug and the user code flag" do
  around do |example|
    Dir.mktmpdir("rake-flag-") do |home|
      @home = home
      FileUtils.mkdir_p(File.join(home, "monadic", "config"))
      File.write(File.join(home, "monadic", "config", "env"), "MONADIC_LOAD_USER_CODE=true\n")
      example.run
    end
  end

  def passed_on(shell_value)
    rake = File.read(File.expand_path("../../../../../../rakelib/server.rake", __dir__))
    block = rake[/^\s*require 'dotenv'\n.*?^\s*ENV\.delete\("MONADIC_LOAD_USER_CODE"\)[^\n]*\n/m]
    expect(block).not_to be_nil
    script = "#{block}\nputs ENV.fetch('MONADIC_LOAD_USER_CODE', 'unset')"
    env = { "HOME" => @home, "MONADIC_LOAD_USER_CODE" => shell_value }
    out, = Open3.capture2(env, RbConfig.ruby, "-e", script)
    out.strip
  end

  it "does not pass on a value from the config file" do
    expect(passed_on(nil)).to eq("unset")
  end

  it "passes on the shell's value" do
    expect(passed_on("true")).to eq("true")
  end
end
