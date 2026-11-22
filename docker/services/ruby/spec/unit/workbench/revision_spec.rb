# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/put"
require_relative "../../../lib/monadic/workbench/made"
require_relative "../../../lib/monadic/workbench/revision"
require_relative "../../../lib/monadic/utils/websocket/message_editor"

# What a reply changes in place that an earlier turn made: kept as it was,
# and put back when the turn is deleted or the reply is stopped.
RSpec.describe Monadic::Workbench::Revision do
  around do |example|
    Dir.mktmpdir("workbench-revision-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [] } }
  let(:made) { Monadic::Workbench::Made }
  let(:editor) { Class.new { include WebSocketHelper }.new }

  before do
    Monadic::Workbench::Board.reset!
    WebSocketHelper::Replies.reset!
    Monadic::Workbench::Shown.reset!
    made.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def folder
    @folder ||= Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: "AutoForge")[:relative_dir]
  end

  def project
    "#{folder}/auto_forge/app_1"
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(@data, path)))
    File.write(File.join(@data, path), text)
  end

  def read(path)
    File.read(File.join(@data, path))
  end

  # A reply that runs, changes the project, and ends with its message.
  def turn(text, mid)
    request_id = Monadic::Workspace::Ids.generate(:request)
    handle, = WebSocketHelper::Replies.open(request_id: request_id, chat_id: chat, tab: "tab-1", generation: 1)
    handle.attach(Thread.current)
    handle.begin!
    described_class.keep!(request_id, project, chat_id: chat)
    described_class.keep!(request_id, project, chat_id: chat)
    write("#{project}/index.html", text)
    made.seal(request_id)
    { "mid" => mid, "role" => "assistant", made::REVISIONS_KEY => made.clean_revisions(made.seal_revisions(request_id)) }
  end

  def delete(message)
    index = session[:messages].index(message)
    session[:messages].delete(message)
    editor.trash_made_files(session, message, session[:messages][index..])
  end

  it "keeps the thing as it was once per reply, and puts it back when the turn is deleted" do
    write("#{project}/index.html", "v1")
    message = turn("v2", "m1")
    expect(message[made::REVISIONS_KEY].size).to eq(1)
    before = message[made::REVISIONS_KEY].first["before"]
    expect(before).to start_with("#{folder}/revisions/")
    expect(read("#{before}/index.html")).to eq("v1")

    session[:messages] << message
    expect(delete(message)).to eq([project])
    expect(read("#{project}/index.html")).to eq("v1")
    trashed = Dir.glob(File.join(@data, folder, "trash", "*", "auto_forge", "app_1", "index.html"))
    expect(trashed.map { |f| File.read(f) }).to eq(["v2"])
  end

  it "puts back the state before both when two turns are deleted, oldest first" do
    write("#{project}/index.html", "v1")
    first = turn("v2", "m1")
    second = turn("v3", "m2")
    session[:messages].push(first, second)

    expect(delete(first)).to eq([])
    expect(read("#{project}/index.html")).to eq("v3")
    delete(second)
    expect(read("#{project}/index.html")).to eq("v1")
  end

  it "puts back the earlier turn's state when only the later turn is deleted" do
    write("#{project}/index.html", "v1")
    first = turn("v2", "m1")
    second = turn("v3", "m2")
    session[:messages].push(first, second)

    delete(second)
    expect(read("#{project}/index.html")).to eq("v2")
  end

  it "moves the copy to the trash when the thing itself is gone" do
    write("#{project}/index.html", "v1")
    message = turn("v2", "m1")
    FileUtils.rm_rf(File.join(@data, project))
    session[:messages] << message
    expect(delete(message)).to eq([])
    expect(File.exist?(File.join(@data, project))).to be false
    expect(Dir.exist?(File.join(@data, message[made::REVISIONS_KEY].first["before"]))).to be false
  end

  it "puts it back when the reply is stopped before its message" do
    write("#{project}/index.html", "v1")
    request_id = Monadic::Workspace::Ids.generate(:request)
    handle, = WebSocketHelper::Replies.open(request_id: request_id, chat_id: chat, tab: "tab-1", generation: 1)
    handle.attach(Thread.current)
    handle.begin!
    described_class.keep!(request_id, project, chat_id: chat)
    write("#{project}/index.html", "half")

    expect(made.close(request_id)).to eq([project])
    expect(read("#{project}/index.html")).to eq("v1")
  end

  it "keeps nothing for what the reply made itself, for another chat's folder, or without a running reply" do
    request_id = Monadic::Workspace::Ids.generate(:request)
    write("#{project}/index.html", "v1")
    expect(described_class.keep!(request_id, project, chat_id: chat)).to be_nil

    handle, = WebSocketHelper::Replies.open(request_id: request_id, chat_id: chat, tab: "tab-1", generation: 1)
    handle.attach(Thread.current)
    handle.begin!
    made.add(request_id, project, chat_id: chat)
    expect(described_class.keep!(request_id, project, chat_id: chat)).to be_nil
    expect(described_class.keep!(request_id, "conversations/other/auto_forge/x", chat_id: chat)).to be_nil
  end

  it "takes from a message only pairs of one chat folder, the copy in its revisions folder" do
    good = { "path" => "conversations/a/auto_forge/p", "before" => "conversations/a/revisions/l/auto_forge/p" }
    bad = [
      { "path" => "conversations/a/auto_forge/p", "before" => "conversations/b/revisions/l/auto_forge/p" },
      { "path" => "conversations/a/auto_forge/q", "before" => "conversations/a/auto_forge/q-old" },
      { "path" => "/etc", "before" => "conversations/a/revisions/l/x" },
      "x"
    ]
    expect(made.clean_revisions([good] + bad)).to eq([good])
    expect(made.clean_revisions(bad)).to be_nil
  end

  it "copies a folder without following a link in it" do
    write("#{project}/index.html", "v1")
    write("elsewhere/secret.txt", "s")
    File.symlink(File.join(@data, "elsewhere"), File.join(@data, project, "link"))
    expect(described_class.copy(folder, %w[auto_forge app_1], %w[auto_forge app_2])).to be true
    expect(read("#{folder}/auto_forge/app_2/index.html")).to eq("v1")
    expect(File.exist?(File.join(@data, folder, "auto_forge", "app_2", "link"))).to be false
  end
end
