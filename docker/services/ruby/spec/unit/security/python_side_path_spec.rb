# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "shellwords"
require_relative "../../../lib/monadic/app"

# Code a model runs can write the shared folder's scripts folder. In the
# Python container a python3, bash or ls left there must not stand in for the
# real one; a script with its own name is still found. Resolve the PATH that
# send_command builds with a real bash.
RSpec.describe "The Python container's PATH" do
  around do |example|
    Dir.mktmpdir("python-path-") do |dir|
      @dir = File.realpath(dir)
      example.run
    end
  end

  it "puts the user's scripts after the system's" do
    scripts = File.join(@dir, "scripts")
    FileUtils.mkdir_p(scripts)
    %w[ls own_tool].each do |name|
      File.write(File.join(scripts, name), "#!/bin/sh\necho impostor\n")
      File.chmod(0o755, File.join(scripts, name))
    end
    stub_const("MonadicApp::USER_SCRIPT_DIR", scripts)

    sent = nil
    allow(MonadicApp).to receive(:capture_command) { |cmd, **| sent = cmd; ["", "", 0] }
    MonadicApp.new.send(:send_command, command: "command -v ls own_tool", container: "python")

    bash_command = Shellwords.split(sent).last # docker exec ... bash -c <this>
    out, = Open3.capture2("bash", "-c", bash_command)
    found = out.split("\n")
    expect(found.first).not_to start_with(scripts) # the real ls
    expect(found.last).to eq(File.join(scripts, "own_tool"))
  end

  it "is in that order in the image as well" do
    dockerfile = File.read(File.expand_path("../../../../python/Dockerfile", __dir__))
    path = dockerfile[/^ENV PATH="([^"]+)"/, 1]
    parts = path.split(":")
    expect(parts.last).to eq("/monadic/data/scripts")
    expect(parts.index("${PATH}")).to be < parts.index("/monadic/data/scripts")
  end
end
