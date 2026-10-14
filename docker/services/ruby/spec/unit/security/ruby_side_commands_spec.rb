# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/app"

# Commands that send_command runs on the Ruby side get the Ruby process's
# environment, which can read the keys (and in the container, Docker). The
# shared folder can be written by code the model runs, so nothing in it may
# run there: not a `ruby`, `bash` or `curl` placed in its scripts folder to
# be found on PATH, and not a Ruby script of its own. The keys are not in
# the environment the command gets either.
RSpec.describe "Ruby-side commands" do
  let(:app) { MonadicApp.new }

  around do |example|
    Dir.mktmpdir("ruby-side-") do |dir|
      @dir = File.realpath(dir)
      example.run
    end
  end

  let(:shared) { File.join(@dir, "data") }
  let(:bundled) { File.join(@dir, "scripts") }
  let(:marks) { File.join(@dir, "marks") }

  before do
    FileUtils.mkdir_p([File.join(shared, "scripts"), File.join(bundled, "cli_tools"), marks])
    stub_const("MonadicApp::LOCAL_SHARED_VOL", shared)
    stub_const("MonadicApp::LOCAL_SYSTEM_SCRIPT_DIR", bundled)
    stub_const("MonadicApp::LOCAL_USER_SCRIPT_DIR", File.join(shared, "scripts"))
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)

    # Impostors in the shared folder: each leaves a mark if it ever runs.
    %w[ruby bash curl env sh].each do |name|
      path = File.join(shared, "scripts", name)
      File.write(path, "#!/bin/sh\necho ran > #{marks}/#{name}\n")
      File.chmod(0o755, path)
    end
    # A bundled script, run the way the real ones are (env ruby shebang).
    probe = File.join(bundled, "cli_tools", "probe.rb")
    File.write(probe, "#!/usr/bin/env ruby\nFile.write(ARGV[0], ENV.keys.grep(/_API_KEY\\z/).join(','))\n")
    File.chmod(0o755, probe)
    # A Ruby script of its own in the shared folder
    File.write(File.join(shared, "scripts", "own.rb"), "File.write('#{marks}/own', 'ran')\n")
  end

  def ran_impostors
    Dir.children(marks)
  end

  it "runs a bundled script with this Ruby, none of the impostors, and without the keys" do
    ENV["MONADIC_TEST_API_KEY"] = "sk-test-MARKER"
    out = File.join(@dir, "probe-out")
    result = app.send_command(command: "probe.rb #{out}", container: "ruby")
    expect(result).to start_with("Command has been executed")
    expect(File.read(out)).not_to include("MONADIC_TEST_API_KEY") # the key was not in its environment
    expect(ran_impostors).to be_empty
  ensure
    ENV.delete("MONADIC_TEST_API_KEY")
  end

  it "finds bash, curl and env outside the shared folder" do
    app.send_command(command: "bash -c 'true'", container: "ruby")
    app.send_command(command: "curl --version", container: "ruby")
    app.send_command(command: "env true", container: "ruby")
    app.send_command(command: "sh -c 'true'", container: "ruby")
    expect(ran_impostors).to be_empty
  end

  it "refuses a Ruby script that does not come with Monadic Chat" do
    result = app.send_command(command: "own.rb", container: "ruby")
    expect(result).to include("is not a script that comes with Monadic Chat")
    yielded = nil
    app.send_command(command: "own.rb", container: "ruby") { |_out, err, status| yielded = [err, status.success?] }
    expect(yielded.last).to be(false)
    expect(ran_impostors).to be_empty
  end

  it "puts neither the shared folder nor a relative directory on PATH, and makes nothing executable" do
    command = app.ruby_side_command("probe.rb x")
    path = command[/\Aexport PATH=(\S+)/, 1]
    expect(Shellwords.split(path).first.split(":")).to all(start_with("/"))
    expect(path).not_to include(shared)
    expect(command).not_to include("chmod")
    expect(command).to include(Shellwords.escape(RbConfig.ruby), Shellwords.escape(File.join(bundled, "cli_tools", "probe.rb")))
  end

  it "keeps the shared folder off PATH even under another name (a link to it)" do
    alias_dir = File.join(@dir, "alias-bin")
    File.symlink(File.join(shared, "scripts"), alias_dir)
    original = ENV["PATH"]
    ENV["PATH"] = "#{alias_dir}:#{original}"
    app.send_command(command: "curl --version", container: "ruby")
    app.send_command(command: "bash -c 'true'", container: "ruby")
    expect(ran_impostors).to be_empty
  ensure
    ENV["PATH"] = original
  end

  describe "every Ruby-side caller" do
    let(:recorded) { [] }
    let(:host) { Class.new(MonadicApp) { include GeminiHelper if defined?(GeminiHelper) }.new }

    before do
      calls = recorded
      allow(MonadicApp).to receive(:capture_command) do |command, timeout:, env:|
        calls << [command, env]
        ["", "", OpenStruct.new(success?: true)]
      end
      allow(Monadic::Utils::ProgressBroadcaster).to receive(:with_progress) { |**_, &block| block.call }
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
      File.write(File.join(shared, "doc.txt"), "text")
      %w[tts_query.rb image_generator_openai.rb image_generator_grok.rb video_generator_gemini.rb
         video_generator_grok.rb content_fetcher.rb].each do |name|
        File.write(File.join(bundled, "cli_tools", name), "")
      end
      ENV["MONADIC_TEST_API_KEY"] = "sk-test-MARKER"
    end

    after { ENV.delete("MONADIC_TEST_API_KEY") }

    it "runs each with a safe PATH, the bundled script by this Ruby and its absolute path, and no keys" do
      callers = {
        list_providers_and_voices: -> { host.list_providers_and_voices },
        text_to_speech: -> { host.text_to_speech(text: "hello") },
        generate_image_with_openai: -> { host.generate_image_with_openai(operation: "generate", model: "gpt-image-1", prompt: "a; touch PWNED") },
        generate_image_with_grok: -> { host.generate_image_with_grok(prompt: "a cat") },
        generate_video_with_grok_imagine: -> { host.generate_video_with_grok_imagine(prompt: "a cat") },
        generate_video_with_veo: -> { host.generate_video_with_veo(prompt: "a cat") },
        fetch_text_from_file: -> { host.fetch_text_from_file(file: "doc.txt") }
      }
      callers.each do |name, call|
        before_count = recorded.size
        begin
          call.call
        rescue StandardError
          # the reply is not what matters here; the command it ran is
        end
        expect(recorded.size).to be > before_count, "#{name} ran no command"
      end
      recorded.each do |command, env|
        expect(command).to start_with("export PATH=")
        expect(command).not_to include("#{shared}/scripts")
        expect(command).not_to include("chmod")
        expect(command).not_to match(/&& (?:bash -c )?[\w.]+\.rb\b/) # no script left to be found on PATH
        expect(env).to include("MONADIC_TEST_API_KEY" => nil)
      end
      scripts = recorded.map(&:first).grep(/[\w-]+\.rb\b/)
      expect(scripts).to all(include(Shellwords.escape(RbConfig.ruby)))
    end
  end
end
