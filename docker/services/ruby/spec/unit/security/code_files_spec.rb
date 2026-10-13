# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/utils/shared_path_guard"

# Custom apps and helpers are loaded as code from the shared folder. A link
# there could point anywhere (made by code a model runs), so only real files
# that really lie inside the folder are loaded.
RSpec.describe "Monadic::Utils::SharedPathGuard.code_files" do
  let(:guard) { Monadic::Utils::SharedPathGuard }

  around do |example|
    Dir.mktmpdir("code-files-") do |dir|
      @dir = File.realpath(dir)
      example.run
    end
  end

  def write(path, text = "x")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  it "lists the real files in the folder" do
    helpers = File.join(@dir, "helpers")
    a = write(File.join(helpers, "a.rb"))
    b = write(File.join(helpers, "sub", "b.rb"))
    expect(guard.code_files(helpers, File.join("**", "*.rb"))).to eq([a, b])
  end

  it "skips a file that is a link, wherever it points" do
    helpers = File.join(@dir, "helpers")
    real = write(File.join(helpers, "real.rb"))
    outside = write(File.join(@dir, "outside", "evil.rb"))
    File.symlink(outside, File.join(helpers, "evil.rb"))
    File.symlink(real, File.join(helpers, "again.rb"))
    expect(guard.code_files(helpers, File.join("**", "*.rb"))).to eq([real])
  end

  it "loads nothing from a folder that is itself a link" do
    ordinary = File.join(@dir, "ordinary")
    write(File.join(ordinary, "probe.rb"))
    File.symlink(ordinary, File.join(@dir, "helpers"))
    expect(guard.code_files(File.join(@dir, "helpers"), File.join("**", "*.rb"))).to eq([])
  end

  it "skips a folder inside that links out" do
    helpers = File.join(@dir, "helpers")
    FileUtils.mkdir_p(helpers)
    write(File.join(@dir, "outside", "evil.rb"))
    File.symlink(File.join(@dir, "outside"), File.join(helpers, "linked"))
    expect(guard.code_files(helpers, File.join("**", "*.rb"))).to eq([])
  end

  it "returns nothing for a missing folder" do
    expect(guard.code_files(File.join(@dir, "none"), "*.rb")).to eq([])
  end
end
