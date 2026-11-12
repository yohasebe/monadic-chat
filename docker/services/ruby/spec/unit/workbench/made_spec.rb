# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/put"
require_relative "../../../lib/monadic/workbench/made"
require_relative "../../../lib/monadic/workbench/turn_trash"
require_relative "../../../lib/monadic/workbench/chat_output"
require_relative "../../../lib/monadic/utils/websocket/message_editor"

# What a reply made in its chat's folder is kept with its message, and
# deleting the message moves it to the chat's trash, touching nothing else.
RSpec.describe "what a turn made (Made) and the trash it goes to (TurnTrash)" do
  around do |example|
    Dir.mktmpdir("workbench-made-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, _ws_generation: 1, messages: [], parameters: { "app_name" => "Chat" } }
  end
  let(:made) { Monadic::Workbench::Made }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    WebSocketHelper::Replies.reset!
    Monadic::Workbench::Put.reset!
    Monadic::Workbench::Shown.reset!
    made.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def running_handle(id = request_id)
    handle, = WebSocketHelper::Replies.open(request_id: id, chat_id: chat, tab: "tab-1", generation: 1)
    handle.attach(Thread.current)
    handle.begin!
    handle
  end

  def caller_for(id = request_id)
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat), request_id: id,
                                   session: session, tab: "tab-1", generation: 1)
  end

  def folder_dir
    Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: "Chat")[:relative_dir]
  end

  def exists?(path)
    File.exist?(File.join(@data, path)) || File.symlink?(File.join(@data, path))
  end

  describe "recording" do
    it "records the run folders and the files a running reply makes, once each, for its message" do
      running_handle
      job = Monadic::Workbench::ChatOutput.run_folder(session: session, workbench: caller_for, app_name: "Chat")
      put = Monadic::Workbench::Put.run(caller_for, name: "draft.md", content: "# Draft\n")
      expect(made.seal(request_id)).to eq([job[:relative], put[:path]])
      expect(made.seal(request_id)).to eq([])
    end

    it "keeps nothing for a reply that is not running, or that ended" do
      made.add(request_id, "conversations/a/artifacts/j_1")
      expect(made.seal(request_id)).to eq([])
      running_handle
      made.close(request_id)
      made.add(request_id, "conversations/a/artifacts/j_1")
      expect(made.seal(request_id)).to eq([])
    end

    it "keeps, from a message, relative paths of the chat folders only" do
      paths = ["conversations/a/artifacts/j_1", "/etc/passwd", "conversations/../x", "data/x.md",
               "conversations/a/artifacts/j_1", 3]
      expect(made.clean(paths)).to eq(["conversations/a/artifacts/j_1"])
      expect(made.clean(["/x"])).to be_nil
      expect(made.clean("conversations/a")).to be_nil
    end
  end

  it "goes through the history and the shared export in its checked form" do
    require_relative "../../../lib/monadic/history/serializer"
    require_relative "../../../lib/monadic/utils/websocket"
    message = { "role" => "assistant", "text" => "x", "mid" => "m1",
                "workbench_made" => ["conversations/a/workbench/d.md", "/etc/x"] }
    expect(Monadic::History::Serializer.message(message)["workbench_made"]).to eq(["conversations/a/workbench/d.md"])
    exported = Class.new { include WebSocketHelper }.new.send(:privacy_clean_messages, [message]).first
    expect(exported["workbench_made"]).to eq(["conversations/a/workbench/d.md"])
    expect(Monadic::History::Serializer.message(message.merge("workbench_made" => ["/x"]))).not_to have_key("workbench_made")
  end

  describe "a reply that ends without its message" do
    it "moves what it made to the chat's trash and takes it off the work screen" do
      running_handle
      job = Monadic::Workbench::ChatOutput.run_folder(session: session, workbench: caller_for, app_name: "Chat")
      kept = Monadic::Workbench::ChatOutput.keep(job, "tune.abc", "X:1")
      put = Monadic::Workbench::Put.run(caller_for, name: "draft.md", content: "# Draft\n")
      expect(Monadic::Workbench::Board.for(chat, store: store).snapshot[:items].map { |i| i[:path] }).to include(put[:path])

      expect(made.close(request_id)).to contain_exactly(job[:relative], put[:path])
      expect(exists?(kept)).to be false
      expect(exists?(put[:path])).to be false
      trashed = Dir.glob(File.join(@data, folder_dir, "trash", "*stopped-*", "**", "*")).map { |f| File.basename(f) }
      expect(trashed).to include("tune.abc", "draft.md")
      expect(Monadic::Workbench::Board.for(chat, store: store).snapshot[:items].map { |i| i[:path] }).not_to include(put[:path])
    end

    it "moves nothing once its message took what it made" do
      running_handle
      put = Monadic::Workbench::Put.run(caller_for, name: "draft.md", content: "# Draft\n")
      made.seal(request_id)
      expect(made.close(request_id)).to eq([])
      expect(exists?(put[:path])).to be true
    end
  end

  describe "the trash" do
    def write(path, text = "x")
      FileUtils.mkdir_p(File.dirname(File.join(@data, path)))
      File.write(File.join(@data, path), text)
    end

    it "moves what is inside the chat's folder into its trash, keeping where it was" do
      dir = folder_dir
      write("#{dir}/artifacts/j_1/score.abc", "X:1")
      write("#{dir}/workbench/draft.md")
      moved = Monadic::Workbench::TurnTrash.move(dir, ["#{dir}/artifacts/j_1", "#{dir}/workbench/draft.md"], "turn")
      expect(moved).to eq(["#{dir}/artifacts/j_1", "#{dir}/workbench/draft.md"])
      expect(File.read(File.join(@data, dir, "trash/turn/artifacts/j_1/score.abc"))).to eq("X:1")
      expect(exists?("#{dir}/trash/turn/workbench/draft.md")).to be true
      expect(exists?("#{dir}/artifacts/j_1")).to be false
    end

    it "leaves what is missing, a link, outside the folder, or already in the trash" do
      dir = folder_dir
      write("elsewhere/mine.md")
      write("#{dir}/trash/old/x.md")
      FileUtils.mkdir_p(File.join(@data, dir, "workbench"))
      File.symlink(File.join(@data, "elsewhere"), File.join(@data, dir, "workbench", "link"))
      paths = ["#{dir}/workbench/gone.md", "#{dir}/workbench/link", "elsewhere/mine.md", "#{dir}/trash/old/x.md",
               "#{dir}/workbench/../../elsewhere/mine.md"]
      expect(Monadic::Workbench::TurnTrash.move(dir, paths, "turn")).to eq([])
      expect(exists?("elsewhere/mine.md")).to be true
      expect(File.symlink?(File.join(@data, dir, "workbench", "link"))).to be true
      expect(exists?("#{dir}/trash/old/x.md")).to be true
    end

    it "never goes through a link on the way to the trash" do
      dir = folder_dir
      write("#{dir}/workbench/draft.md")
      write("elsewhere/keep.md")
      File.symlink(File.join(@data, "elsewhere"), File.join(@data, dir, "trash"))
      expect(Monadic::Workbench::TurnTrash.move(dir, ["#{dir}/workbench/draft.md"], "turn")).to eq([])
      expect(exists?("#{dir}/workbench/draft.md")).to be true
      expect(Dir.children(File.join(@data, "elsewhere"))).to eq(["keep.md"])
    end

    it "names a turn's part of the trash by the time and the message" do
      expect(Monadic::Workbench::TurnTrash.label("m_1/../x", now: Time.utc(2026, 11, 12, 9, 8, 7))).to eq("20261112-090807-m_1x")
    end
  end

  describe "deleting a message" do
    let(:editor) { Class.new { include WebSocketHelper }.new }

    it "moves what the message made to the trash and takes its files off the work screen" do
      running_handle
      put = Monadic::Workbench::Put.run(caller_for, name: "draft.md", content: "# Draft\n")
      board = Monadic::Workbench::Board.for(chat, store: store)
      expect(board.snapshot[:items].map { |i| i[:path] }).to include(put[:path])
      kept = File.join(Monadic::Workspace::Folders.lookup(session)[:relative_dir], "workbench", "mine.md")
      File.write(File.join(@data, kept), "mine")
      message = { "mid" => "m1", "role" => "assistant", "workbench_made" => [put[:path]] }

      moved = editor.trash_made_files(session, message)
      expect(moved).to eq([put[:path]])
      expect(exists?(put[:path])).to be false
      expect(exists?(kept)).to be true
      expect(board.snapshot[:items].map { |i| i[:path] }).not_to include(put[:path])
    end

    it "moves nothing for a message that made nothing, or in a chat without a folder" do
      expect(editor.trash_made_files(session, { "mid" => "m1", "role" => "assistant" })).to eq([])
      other = { Monadic::Workspace::Chats::SESSION_KEY => Monadic::Workspace::Ids.generate(:chat) }
      expect(editor.trash_made_files(other, { "workbench_made" => ["conversations/a/workbench/x.md"] })).to eq([])
    end
  end
end
