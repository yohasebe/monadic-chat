# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/workbench/put"
require_relative "../../../lib/monadic/workbench/shown"
require_relative "../../../lib/monadic/shared_tools/workbench_tools"

RSpec.describe "a text put on the work screen (put_on_workbench) and what a reply showed (Shown)" do
  around do |example|
    Dir.mktmpdir("workbench-put-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, _ws_generation: 1, messages: [], parameters: { "app_name" => "Chat" } } }
  let(:put) { Monadic::Workbench::Put }
  let(:shown) { Monadic::Workbench::Shown }
  let(:tools) { Class.new { include MonadicSharedTools::WorkbenchTools }.new }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    WebSocketHelper::Replies.reset!
    put.reset!
    shown.reset!
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

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def written(path)
    File.binread(File.join(@data, path))
  end

  def files_in_folder
    Dir.glob(File.join(@data, "**", "*"), File::FNM_DOTMATCH).select { |f| File.file?(f) }
       .map { |f| f.delete_prefix("#{@data}/") }
  end

  describe "writing and showing" do
    it "writes a new file under workbench/ in the chat's folder and shows it, selected for the tab" do
      running_handle
      result = put.run(caller_for, name: "notes.md", content: "# Notes\n")
      expect(result).to include(shown: true, reason: nil)
      expect(result[:path]).to match(%r{\Aconversations/[^/]+/workbench/notes\.md\z})
      expect(written(result[:path])).to eq("# Notes\n")
      item = board.snapshot[:items].first
      expect(item).to include(path: result[:path], render: "markdown")
      expect(board.selected(tab: "tab-1", generation: 1)).to eq(item[:id])
    end

    it "numbers a taken name, keeping an extension of two parts whole" do
      running_handle
      first = put.run(caller_for, name: "sales.vl.json", content: "{\"a\":1}")
      second = put.run(caller_for, name: "sales.vl.json", content: "{\"a\":2}")
      expect(File.basename(first[:path])).to eq("sales.vl.json")
      expect(File.basename(second[:path])).to eq("sales-2.vl.json")
    end

    it "gives the same file for the same name and text again in one reply" do
      running_handle
      first = put.run(caller_for, name: "t.csv", content: "a,b\n")
      again = put.run(caller_for, name: "t.csv", content: "a,b\n")
      expect(again[:path]).to eq(first[:path])
      expect(files_in_folder.count { |f| f.end_with?(".csv") }).to eq(1)
    end

    it "shows again a file it wrote but could not show, without writing another" do
      running_handle
      allow_any_instance_of(Monadic::Workbench::Board).to receive(:add_file).and_raise(Monadic::Workbench::FileItem::Busy)
      first = put.run(caller_for, name: "t.md", content: "x")
      expect(first).to include(shown: false)
      expect(first[:path]).to end_with("workbench/t.md")
      allow_any_instance_of(Monadic::Workbench::Board).to receive(:add_file).and_call_original
      again = put.run(caller_for, name: "t.md", content: "x")
      expect(again).to include(path: first[:path], shown: true)
      expect(files_in_folder.count { |f| f.end_with?("t.md") }).to eq(1)
    end

    it "leaves no file being written in the folder's listing" do
      running_handle
      result = put.run(caller_for, name: "t.md", content: "x")
      dir = File.dirname(result[:path])
      expect(Dir.children(File.join(@data, dir))).to eq(["t.md"])
      expect(Monadic::Utils::SharedFs.being_written?(".t.md.0123456789abcdef.tmp")).to be(true)
      expect(Monadic::Utils::SharedFs.being_written?("t.md")).to be(false)
    end
  end

  describe "what it refuses" do
    before { running_handle }

    it "refuses names that are not one file name with an extension the work screen shows" do
      ["../x.md", "a/b.md", ".hidden.md", "x.exe", ".md", "x\u0000.md", "x‮.md", "#{'a' * 98}.md", 7].each do |name|
        expect { put.run(caller_for, name: name, content: "x") }.to raise_error(put::Refused), name.inspect
      end
      expect(files_in_folder).to be_empty
    end

    it "refuses content that is not UTF-8 text, or too large" do
      expect { put.run(caller_for, name: "a.txt", content: "\xFF".b) }.to raise_error(put::Refused, /UTF-8/)
      expect { put.run(caller_for, name: "a.txt", content: "a\0b") }.to raise_error(put::Refused, /UTF-8/)
      stub_const("Monadic::Workbench::Put::LIMIT", 3)
      expect { put.run(caller_for, name: "a.txt", content: "abcd") }.to raise_error(put::Refused, /at most 3 bytes/)
    end

    it "refuses without a caller, and for a reply that is not running" do
      expect { put.run(nil, name: "a.md", content: "x") }.to raise_error(put::Refused)
      other = Monadic::Workspace::Ids.generate(:request)
      expect { put.run(caller_for(other), name: "a.md", content: "x") }.to raise_error(put::Refused, /ended/)
    end

    it "refuses a late call of a reply that ended" do
      put.release(request_id)
      expect { put.run(caller_for, name: "a.md", content: "x") }.to raise_error(put::Refused, /ended/)
      expect(files_in_folder).to be_empty
    end
  end

  describe "against a Cancel and leaving the chat" do
    it "writes nothing when the reply was cancelled before the write was decided" do
      handle = running_handle
      the_caller = caller_for
      handle.cancel!
      expect { put.run(the_caller, name: "a.md", content: "x") }.to raise_error(put::Refused)
      expect(files_in_folder.grep(/a\.md/)).to be_empty
    end

    it "writes nothing when the chat was left after the first checks and before the decision" do
      running_handle
      the_caller = caller_for
      allow(Monadic::Workspace::Chats).to receive(:admit_in_epoch).and_wrap_original do |original, *args, &block|
        Monadic::Workspace::Chats.replacing!(session)
        original.call(*args, &block)
      end
      expect { put.run(the_caller, name: "a.md", content: "x") }.to raise_error(put::Refused, /stopped or the chat changed/)
      expect(files_in_folder.grep(/a\.md/)).to be_empty
    end

    it "finishes the file when the stop comes right after the write was decided, and leaves nothing half written" do
      handle = running_handle
      the_caller = caller_for
      decided = Queue.new
      go_on = Queue.new
      allow(handle).to receive(:admit_write).and_wrap_original do |original|
        original.call.tap do
          decided << true
          go_on.pop
        end
      end
      writer = Thread.new do
        put.run(the_caller, name: "kept.md", content: "whole text")
      rescue StandardError
        nil
      end
      decided.pop
      writer.kill
      go_on << true
      writer.join(5)
      expect(writer.alive?).to be(false)
      kept = files_in_folder.grep(/kept/)
      expect(kept.size).to eq(1)
      expect(kept.first).to end_with("workbench/kept.md")
      expect(written(kept.first)).to eq("whole text")
    end

    it "does not show a file the reply wrote after it was cancelled" do
      handle = running_handle
      the_caller = caller_for
      allow(handle).to receive(:admit_write).and_wrap_original do |original|
        original.call.tap { handle.cancel! }
      end
      result = put.run(the_caller, name: "late.md", content: "x")
      expect(result).to include(shown: false, reason: /stopped/)
      expect(files_in_folder.grep(/late\.md/).size).to eq(1)
      expect(board.snapshot[:items]).to be_empty
    end
  end

  describe "the tool" do
    it "says where the file is and that it was shown" do
      running_handle
      out = JSON.parse(tools.put_on_workbench(name: "a.md", content: "x", workbench: caller_for))
      expect(out).to include("status" => "shown_in_work_screen")
      expect(out["path"]).to end_with("workbench/a.md")
    end

    it "says a refusal as an error" do
      expect(tools.put_on_workbench(name: "a.md", content: "x", workbench: nil)).to start_with("❌")
    end
  end

  describe "what a reply showed" do
    def file_item(path, text)
      FileUtils.mkdir_p(File.dirname(File.join(@data, path)))
      File.binwrite(File.join(@data, path), text)
      board.add_file(path: path, origin: caller_for.origin, epoch: Monadic::Workspace::Chats.epoch(chat)).first
    end

    it "records each version once while the reply runs, and gives them to its message once" do
      running_handle
      item = file_item("a.md", "x")
      shown.add(request_id, item)
      shown.add(request_id, item)
      shown.add(request_id, file_item("b.csv", "1"))
      records = shown.seal(request_id)
      expect(records.map { |r| r["path"] }).to eq(%w[a.md b.csv])
      expect(records.first).to eq("path" => "a.md", "name" => "a.md", "sha256" => Digest::SHA256.hexdigest("x"),
                                  "preview" => "text", "render" => "markdown")
      expect(shown.seal(request_id)).to eq([])
      shown.add(request_id, item)
      expect(shown.seal(request_id)).to eq([])
    end

    it "takes nothing for a reply that is not running or was cancelled, and nothing after it ended" do
      item = file_item("a.md", "x")
      shown.add(request_id, item)
      handle = running_handle
      handle.cancel!
      shown.add(request_id, item)
      expect(shown.seal(request_id)).to eq([])
      other = Monadic::Workspace::Ids.generate(:request)
      running_handle(other)
      shown.close(other)
      shown.add(other, item)
      expect(shown.seal(other)).to eq([])
    end

    it "is recorded by show_on_workbench and by put_on_workbench" do
      running_handle
      File.binwrite(File.join(@data, "c.svg"), "<svg/>")
      tools.show_on_workbench(path: "c.svg", workbench: caller_for)
      tools.put_on_workbench(name: "d.md", content: "x", workbench: caller_for)
      expect(shown.seal(request_id).map { |r| r["name"] }).to eq(%w[c.svg d.md])
    end

    it "goes through the history and the shared export in its checked form" do
      require_relative "../../../lib/monadic/history/serializer"
      require_relative "../../../lib/monadic/utils/websocket"
      record = { "path" => "a/b.md", "name" => "b.md", "sha256" => "a" * 64, "preview" => "text" }
      message = { "role" => "assistant", "text" => "x", "mid" => "m1",
                  "workbench_shown" => [record.merge("token" => "t"), { "path" => "/etc/x" }] }
      expected = [record.merge("render" => "markdown")]
      expect(Monadic::History::Serializer.message(message)["workbench_shown"]).to eq(expected)
      exported = Class.new { include WebSocketHelper }.new.send(:privacy_clean_messages, [message]).first
      expect(exported["workbench_shown"]).to eq(expected)
      expect(Monadic::History::Serializer.message(message.merge("workbench_shown" => [{ "x" => 1 }])))
        .not_to have_key("workbench_shown")
    end

    it "keeps only records of the right form" do
      good = { "path" => "a/b.md", "name" => "b.md", "sha256" => "a" * 64, "preview" => "text", "url" => "x" }
      bad = [
        good.merge("path" => "/abs/b.md"), good.merge("path" => "a/../b.md"), good.merge("sha256" => "x"),
        good.merge("preview" => "image"), good.merge("name" => ""), "text", nil
      ]
      expect(shown.clean([good, *bad])).to eq([good.except("url").merge("render" => "markdown")])
      expect(shown.clean(bad)).to be_nil
      expect(shown.clean("x")).to be_nil
      expect(shown.clean([good] * 30).size).to eq(shown::LIMIT)
    end
  end
end
