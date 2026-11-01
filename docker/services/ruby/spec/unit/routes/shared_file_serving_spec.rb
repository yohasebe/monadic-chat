# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../../../lib/monadic/utils/shared_file_path"

# GET /data/<name> serves the file it opened, once and never through a link:
# a name swapped for a link afterwards cannot make it read a file only the
# server can reach (the config env file with the API keys).
RSpec.describe "Serving a file of the shared folder" do
  let(:serve) { Monadic::Utils::SharedFilePath }

  around do |example|
    Dir.mktmpdir("shared-serve") do |dir|
      @root = File.join(dir, "data")
      @outside = File.join(dir, "outside")
      FileUtils.mkdir_p([@root, @outside])
      @secret = File.join(@outside, "env")
      File.write(@secret, "OPENAI_API_KEY=secret")
      File.write(File.join(@root, "clip.txt"), "0123456789")
      example.run
    end
  end

  before { allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@root) }

  def get(name, env = {})
    status, headers, body = serve.response(name, @root, { "REQUEST_METHOD" => "GET" }.merge(env))
    text = +""
    body.each { |chunk| text << chunk }
    body.close if body.respond_to?(:close)
    [status, headers, text]
  end

  it "serves the whole file and one byte range of it" do
    status, headers, text = get("clip.txt")
    expect([status, text, headers["content-length"], headers["accept-ranges"]]).to eq([200, "0123456789", "10", "bytes"])
    status, headers, text = get("clip.txt", "HTTP_RANGE" => "bytes=2-4")
    expect([status, text, headers["content-range"], headers["content-length"]]).to eq([206, "234", "bytes 2-4/10", "3"])
  end

  it "answers a range outside the file with 416, a current copy with 304, and HEAD with no body" do
    expect(get("clip.txt", "HTTP_RANGE" => "bytes=50-60").first).to eq(416)
    since = (File.mtime(File.join(@root, "clip.txt")) + 10).httpdate
    expect(get("clip.txt", "HTTP_IF_MODIFIED_SINCE" => since).first).to eq(304)
    status, headers, body = serve.response("clip.txt", @root, { "REQUEST_METHOD" => "HEAD" })
    expect([status, headers["content-length"], body]).to eq([200, "10", []])
  end

  it "serves nothing behind a link at the name, nor in a subfolder" do
    File.symlink(@secret, File.join(@root, "linked.txt"))
    expect(get("linked.txt").first).to eq(404)
    FileUtils.mkdir_p(File.join(@root, "sub"))
    File.write(File.join(@root, "sub", "a.txt"), "a")
    expect(get("sub/a.txt").first).to eq(404)
    expect(get("../outside/env").first).to eq(404)
  end

  it "keeps serving the file it opened when the name is swapped for a link before the body is read" do
    status, _headers, body = serve.response("clip.txt", @root, { "REQUEST_METHOD" => "GET" })
    File.rename(File.join(@root, "clip.txt"), File.join(@root, "moved.txt"))
    File.symlink(@secret, File.join(@root, "clip.txt"))
    text = +""
    body.each { |chunk| text << chunk }
    body.close
    expect([status, text]).to eq([200, "0123456789"])
    expect(text).not_to include("secret")
  end

  it "closes the file it opened after the body, a 304, a 416 and a HEAD" do
    fds = -> { Dir.children("/dev/fd").size }
    before = fds.call
    5.times do
      get("clip.txt")
      get("clip.txt", "HTTP_RANGE" => "bytes=99-")
      get("clip.txt", "HTTP_IF_MODIFIED_SINCE" => (Time.now + 3600).httpdate)
      serve.response("clip.txt", @root, { "REQUEST_METHOD" => "HEAD" })
    end
    expect(fds.call).to be <= before
  end
end
