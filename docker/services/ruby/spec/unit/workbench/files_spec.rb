# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"
require_relative "../../../lib/monadic/shared_tools/workbench_tools"

RSpec.describe "files of the shared folder on the workbench (board, channel, asset server, tool)" do
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("workbench-files-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { chat_id: chat, _ws_generation: 1, messages: [] } }
  let(:channel) { Monadic::Workbench::Channel }
  let(:live_tabs) { { "tab-1" => 1, "tab-2" => 1 } }
  let(:live) { ->(t) { live_tabs[t] } }

  before do
    Monadic::Workbench::Board.reset!
    # A selection counts for the connection a tab has now.
    Monadic::Workbench::Board.live = live
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::ViewTokens.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def write(path, bytes)
    full = File.join(@data, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, bytes)
    full
  end

  def board(private: false)
    Monadic::Workbench::Board.for(chat, private: private, store: store)
  end

  def epoch
    Monadic::Workspace::Chats.epoch(chat)
  end

  def open_file(path, on: board, tab: "tab-1")
    on.add_file(path: path, origin: { actor: :user, source: :panel, tab: tab, generation: 1 }, epoch: epoch)
  end

  def image(salt = "")
    board.add_image(bytes: png(64, 48, salt), epoch: epoch, name: "cat.png", run: "j_#{SecureRandom.hex(10)}",
                    origin: { actor: :agent, request_id: Monadic::Workspace::Ids.generate(:request) },
                    app_name: "Image Generator")
  end

  describe "opening a file" do
    it "keeps a reference and the version, selects it for the tab it was opened for, and copies nothing" do
      write("reports/notes.txt", "one\ntwo\n")
      item, added = open_file("reports/notes.txt")
      expect(added).to be(true)
      expect(item["file"]).to include("path" => "reports/notes.txt", "name" => "notes.txt", "preview" => "text",
                                      "sha256" => Digest::SHA256.hexdigest("one\ntwo\n"), "size" => 8)
      expect(board.selected(tab: "tab-1", generation: 1)).to eq(item["id"])
      expect(board.selected(tab: "tab-2", generation: 1)).to be_nil
      expect(Dir.glob(File.join(@state, "**", "notes.txt"))).to be_empty
      expect(JSON.parse(File.read(Dir.glob(File.join(@state, "workbench", "**", "*.json")).first)).to_s).not_to include("tab-1")
    end

    it "selects the item it has for the same file at the same version instead of adding it again" do
      write("a.txt", "a")
      first, = open_file("a.txt")
      again, added = open_file("a.txt", tab: "tab-2")
      expect(added).to be(false)
      expect(again["id"]).to eq(first["id"])
      expect(board.snapshot[:items].size).to eq(1)
      expect(board.selected(tab: "tab-2", generation: 1)).to eq(first["id"])
    end

    it "says when the file changed or is gone, and reads only the version it opened" do
      full = write("a.txt", "abc")
      item, = open_file("a.txt")
      mtime = File.mtime(full)
      File.binwrite(full, "xyz")
      File.utime(mtime, mtime, full)
      # The same size and time: the view cannot tell, the use does.
      expect { board.file_read(item["id"], sha256: item.dig("file", "sha256")) }
        .to raise_error(Monadic::Workbench::Artifact::Changed)
      File.binwrite(full, "longer now")
      expect(board.snapshot[:items].first[:status]).to eq("changed")
      File.delete(full)
      expect(board.snapshot[:items].first[:status]).to eq("missing")
      expect { board.file_read(item["id"], sha256: item.dig("file", "sha256")) }
        .to raise_error(Monadic::Workbench::Artifact::Missing)
      write("a.txt", "longer now")
      newer, added = open_file("a.txt")
      expect(added).to be(true)
      expect(newer["id"]).not_to eq(item["id"])
    end

    it "refuses a path out of the shared folder, through a link, a kind it does not show, or a file too large" do
      write("doc.pdf", "%PDF-1.4")
      write("real/a.txt", "a")
      File.symlink(File.join(@data, "real"), File.join(@data, "linked"))
      outside = File.join(File.dirname(@data), "outside.txt")
      File.binwrite(outside, "secret")
      File.symlink(outside, File.join(@data, "out.txt"))
      ["../outside.txt", "/etc/hosts", "linked/a.txt", "out.txt", "doc.pdf", "", "a\0b.txt"].each do |path|
        expect { open_file(path) }.to raise_error(Monadic::Workbench::Board::Refused), path.inspect
      end
      stub_const("Monadic::Workbench::FileItem::LIMIT", 2)
      expect { open_file("real/a.txt") }.not_to raise_error
      write("big.txt", "abc")
      expect { open_file("big.txt") }.to raise_error(Monadic::Workbench::Board::Refused, /too large/)
      expect(board.snapshot[:items].size).to eq(1)
    end

    it "is held in memory only in a Private chat" do
      write("a.txt", "a")
      item, = open_file("a.txt", on: board(private: true))
      expect(item["kind"]).to eq("file")
      expect(store.exists?(chat)).to be(false)
    end
  end

  describe "the row of items" do
    let(:limit) { Monadic::Workbench::Board::ITEM_LIMIT }

    it "takes the oldest item off when it is full, but not one a tab shows nor the latest image" do
      write("f1.txt", "1")
      shown, = open_file("f1.txt")
      board.select(tab: "tab-2", generation: 1, item_id: shown["id"])
      latest = image("x")
      (3..limit).each do |i|
        write("f#{i}.txt", i.to_s)
        open_file("f#{i}.txt")
      end
      write("next.txt", "next")
      open_file("next.txt")
      paths = board.snapshot[:items].map { |i| i[:path] }
      expect(paths.size).to eq(limit)
      expect(paths).to include("f1.txt", latest.dig("artifact", "path"))
      expect(paths).not_to include("f3.txt")
      expect(File.file?(File.join(@data, "f3.txt"))).to be(true)
    end

    it "refuses to add when every item is kept, and the user can still take one off" do
      (1..limit).each { |i| live_tabs["tab-#{i}"] = 1 }
      live_tabs["tab-x"] = 1
      items = (1..limit).map do |i|
        write("f#{i}.txt", i.to_s)
        open_file("f#{i}.txt", tab: "tab-#{i}").first
      end
      write("next.txt", "next")
      expect { open_file("next.txt", tab: "tab-x") }.to raise_error(Monadic::Workbench::Board::Refused, /full/)
      status, = board.accept(item_id: items.first["id"], action: "remove", operation_id: "op-00000001", epoch: epoch,
                             sha256: items.first.dig("file", "sha256"))
      expect(status).to eq(:accepted)
      expect { open_file("next.txt", tab: "tab-x") }.not_to raise_error
    end

    it "keeps a tab's selection for its connection only" do
      write("a.txt", "a")
      item, = open_file("a.txt")
      expect { board.select(tab: "tab-1", generation: 1, item_id: "i_nothing") }
        .to raise_error(Monadic::Workbench::Board::Refused)
      board.select(tab: "tab-1", generation: 2, item_id: item["id"])
      board.drop_selection("tab-1", 1)
      expect(board.selected(tab: "tab-1", generation: 2)).to eq(item["id"])
      board.drop_selection("tab-1", 2)
      expect(board.selected(tab: "tab-1", generation: 2)).to be_nil
    end
  end

  describe "over the main socket" do
    it "opens a file for this tab: the view says this tab selected it and gives an address" do
      write("a.txt", "a")
      result = channel.open_file({ "path" => "a.txt" }, session, tab: "tab-1", generation: 1, live: live)
      expect(result).to include("type" => "workbench_opened", "path" => "a.txt", "added" => true)
      mine = channel.view(session, tab: "tab-1", generation: 1, live: live)
      other = channel.view(session, tab: "tab-2", generation: 1, live: live)
      expect(mine["selected"]).to eq(result["item_id"])
      expect(other["selected"]).to be_nil
      expect(mine["assets"][result["item_id"]]).to start_with(Monadic::Workbench::AssetServer::PREFIX)
      expect(mine["board"][:items].first).to include(kind: "file", path: "a.txt", preview: "text", status: "ok")
    end

    it "refuses an open from a replaced connection and says why a file is not opened" do
      write("a.txt", "a")
      live_tabs["tab-1"] = 2
      expect(channel.open_file({ "path" => "a.txt" }, session, tab: "tab-1", generation: 1, live: live))
        .to include("status" => "refused", "reason" => "not_allowed")
      live_tabs["tab-1"] = 1
      expect(channel.open_file({ "path" => "../x.txt" }, session, tab: "tab-1", generation: 1, live: live))
        .to include("status" => "refused")
    end

    it "takes the tab's selection, and answers what it holds when an item is gone" do
      write("a.txt", "a")
      item_id = channel.open_file({ "path" => "a.txt" }, session, tab: "tab-1", generation: 1, live: live)["item_id"]
      expect(channel.select({ "item_id" => nil }, session, tab: "tab-1", generation: 1, live: live))
        .to include("status" => "accepted")
      expect(channel.select({ "item_id" => "i_gone" }, session, tab: "tab-1", generation: 1, live: live))
        .to include("status" => "refused")
      channel.select({ "item_id" => item_id }, session, tab: "tab-1", generation: 1, live: live)
      channel.connection_closed("tab-1", 1, session)
      expect(board.selected(tab: "tab-1", generation: 1)).to be_nil
    end
  end

  describe "the asset server" do
    let(:private_chats) { [] }
    let(:server) do
      Monadic::Workbench::AssetServer.new(->(_env) { [200, {}, ["app"]] }, live: live,
                                                                            private_chat: ->(c) { private_chats.include?(c) })
    end

    def address(path)
      item_id = channel.open_file({ "path" => path }, session, tab: "tab-1", generation: 1, live: live)["item_id"]
      channel.view(session, tab: "tab-1", generation: 1, live: live)["assets"][item_id]
    end

    def fetch_asset(url, range: nil)
      env = { "PATH_INFO" => url, "REQUEST_METHOD" => "GET", "HTTP_SEC_FETCH_SITE" => "same-origin" }
      env["HTTP_RANGE"] = range if range
      server.call(env)
    end

    it "serves the file at the version opened, with its type" do
      write("pic.png", png(2, 2))
      status, headers, body = fetch_asset(address("pic.png"))
      expect(status).to eq(200)
      expect(body.join).to eq(png(2, 2))
      expect(headers).to include("content-type" => "image/png", "cache-control" => "no-store",
                                 "content-security-policy" => "default-src 'none'")
    end

    it "serves the beginning of a long text and says it was cut" do
      stub_const("Monadic::Workbench::FileItem::TEXT_LIMIT", 4)
      write("long.txt", "abcdefgh")
      status, headers, body = fetch_asset(address("long.txt"))
      expect(status).to eq(200)
      expect(body.join).to eq("abcd")
      expect(headers).to include("content-type" => "text/plain; charset=utf-8", "x-workbench-truncated" => "1")
    end

    it "serves a range of audio or video from the checked bytes" do
      write("clip.mp3", "0123456789")
      url = address("clip.mp3")
      status, headers, body = fetch_asset(url, range: "bytes=2-4")
      expect(status).to eq(206)
      expect(body.join).to eq("234")
      expect(headers).to include("content-range" => "bytes 2-4/10", "accept-ranges" => "bytes")
      expect(fetch_asset(url, range: "bytes=20-").first).to eq(416)
    end

    it "answers 409 for a file that changed and 410 for one that is gone" do
      full = write("a.txt", "a")
      url = address("a.txt")
      File.binwrite(full, "b")
      expect(fetch_asset(url).first).to eq(409)
      File.delete(full)
      expect(fetch_asset(url).first).to eq(410)
    end

    it "serves a file of a Private chat to its tab" do
      private_chats << chat
      allow(Monadic::History::Policy).to receive(:known_private?).and_return(true)
      write("a.txt", "a")
      expect(fetch_asset(address("a.txt")).first).to eq(200)
    end
  end

  describe "show_on_workbench" do
    let(:tool) { Class.new { include MonadicSharedTools::WorkbenchTools }.new }
    let(:caller_of_reply) do
      Monadic::Workbench::Caller.new(chat_id: chat, epoch: epoch, request_id: Monadic::Workspace::Ids.generate(:request),
                                     session: session, tab: "tab-1", generation: 1)
    end

    it "shows the file for the tab of the reply and tells the chat's pages" do
      write("charts/a.png", png(2, 2))
      expect(channel).to receive(:changed).with(chat)
      result = JSON.parse(tool.show_on_workbench(path: "/monadic/data/charts/a.png", workbench: caller_of_reply))
      expect(result).to include("status" => "shown_in_work_screen", "path" => "charts/a.png")
      item = board.snapshot[:items].first
      expect(item).to include(kind: "file", actor: "agent", path: "charts/a.png")
      expect(board.selected(tab: "tab-1", generation: 1)).to eq(item[:id])
    end

    it "refuses without the server's caller, and for a file it does not show" do
      expect(tool.show_on_workbench(path: "a.png")).to start_with("❌")
      expect(tool.show_on_workbench(path: "../x.png", workbench: caller_of_reply)).to start_with("❌")
      expect(board.snapshot[:items]).to be_empty
    end

    it "is offered to every app, whatever the provider" do
      %w[openai claude gemini].each do |provider|
        state = MonadicDSL.app("WorkbenchInject#{provider.capitalize}") do
          description "x"
          llm { provider provider }
        end
        tools = state.settings[:tools]
        list = tools.is_a?(Hash) ? (tools[:function_declarations] || tools["function_declarations"] || []) : Array(tools)
        names = list.map { |t| t.dig(:function, :name) || t.dig("function", "name") || t[:name] || t["name"] }
        expect(names.count("show_on_workbench")).to eq(1), provider
      end
    end
  end
  describe "the chat's browser" do
    let(:owner) { MonadicSharedTools::BrowserOwner }
    let(:open_instance) { [1] }

    before do
      require_relative "../../../lib/monadic/shared_tools/browser_owner"
      allow(owner).to receive(:view) do |c|
        next nil unless c == chat && open_instance.first

        MonadicSharedTools::BrowserOwner::View.new(chat, epoch, open_instance.first, "s-1", "w-1")
      end
    end

    def opened(instance = 1, tab: "tab-1")
      board.add_browser(instance: instance, origin: { actor: :agent, source: :browser, tab: tab, generation: 1 }, epoch: epoch)
    end

    it "is an item while open and after it closed, selected for the tab that opened it, and never saved" do
      item = opened
      expect(board.selected(tab: "tab-1", generation: 1)).to eq(item["id"])
      expect(board.snapshot[:items].first).to include(kind: "browser", status: "open", version: "browser:1")
      expect(opened["id"]).to eq(item["id"])
      expect(board.snapshot[:items].size).to eq(1)
      open_instance[0] = nil
      expect(board.snapshot[:items].first[:status]).to eq("closed")
      write("a.txt", "a")
      open_file("a.txt")
      saved = JSON.parse(File.read(Dir.glob(File.join(@state, "workbench", "**", "*.json")).first))
      expect(saved["items"].values.map { |i| i["kind"] }).to eq(["file"])
    end

    it "is not put back after the user took it off, and a new browser is a new item" do
      item = opened
      status, = board.accept(item_id: item["id"], action: "remove", operation_id: "op-00000001", epoch: epoch,
                             sha256: "browser:1")
      expect(status).to eq(:accepted)
      expect(opened).to be_nil
      expect(board.snapshot[:items]).to be_empty
      open_instance[0] = 2
      expect(opened(2)["browser"]).to eq("instance" => 2)
    end

    it "is kept while open when the board makes room, and can go once closed" do
      item = opened(1, tab: "tab-x")
      board.select(tab: "tab-x", generation: 1, item_id: nil)
      (1..Monadic::Workbench::Board::ITEM_LIMIT).each do |i|
        write("f#{i}.txt", i.to_s)
        open_file("f#{i}.txt")
      end
      expect(board.snapshot[:items].map { |i| i[:id] }).to include(item["id"])
      open_instance[0] = nil
      write("g.txt", "g")
      open_file("g.txt")
      expect(board.snapshot[:items].map { |i| i[:id] }).not_to include(item["id"])
    end

    it "gives the browser a token to remove it, and no address" do
      item = opened
      message = channel.view(session, tab: "tab-1", generation: 1, live: live)
      expect(message["approvals"]).to have_key(item["id"])
      expect(message["assets"]).not_to have_key(item["id"])
      expect(message["selected"]).to eq(item["id"])
    end

    it "is put on the board when the browser opens, for the tab of the message that opened it" do
      require_relative "../../../lib/monadic/work_screen"
      # No tab is connected: nothing is sent.
      if defined?(WebSocketHelper)
        allow(WebSocketHelper).to receive(:live_tabs_for_chat).and_return([])
      else
        stub_const("WebSocketHelper", Module.new { def self.live_tabs_for_chat(*) = [] })
      end
      request = Monadic::Workspace::RequestContext.new(chat_id: chat, tab: "tab-2", generation: 1)
      Monadic::Workspace::RequestContext.with(request) { Monadic::WorkScreen.browser_opened(chat) }
      item = board.snapshot[:items].first
      expect(item).to include(kind: "browser", status: "open")
      expect(board.selected(tab: "tab-2", generation: 1)).to eq(item[:id])
      expect(board.selected(tab: "tab-1", generation: 1)).to be_nil
    end
  end
  describe "connections, versions and load" do
    it "lets no work of an older connection select over the tab's newer one" do
      write("a.txt", "a")
      write("b.txt", "b")
      live_tabs["tab-1"] = 2
      mine, = board.add_file(path: "a.txt", origin: { actor: :user, tab: "tab-1", generation: 2 }, epoch: epoch)
      board.add_file(path: "b.txt", origin: { actor: :agent, tab: "tab-1", generation: 1 }, epoch: epoch)
      expect(board.selected(tab: "tab-1", generation: 2)).to eq(mine["id"])
      expect { board.add_file(path: "b.txt", origin: { actor: :user, tab: "tab-1", generation: 1 }, epoch: epoch) }
        .to raise_error(Monadic::Workbench::Board::Refused, "not_allowed")
    end

    it "drops what a connection selected in a chat it left" do
      write("a.txt", "a")
      item, = open_file("a.txt")
      Thread.current[:websocket_session_id] = "tab-1"
      begin
        Monadic::Workspace::Chats.replacing!({ chat_id: chat, _ws_generation: 1 })
      ensure
        Thread.current[:websocket_session_id] = nil
      end
      expect(board.selected(tab: "tab-1", generation: 1)).to be_nil
      expect(board.snapshot[:items].map { |i| i[:id] }).to eq([item["id"]])
    end

    it "is shown again when the same bytes were saved again and the user opens it" do
      full = write("a.txt", "abc")
      item, = open_file("a.txt")
      File.utime(Time.now + 60, Time.now + 60, full)
      expect(board.snapshot[:items].first[:status]).to eq("changed")
      again, added = open_file("a.txt")
      expect(added).to be(false)
      expect(again["id"]).to eq(item["id"])
      expect(board.snapshot[:items].first[:status]).to eq("ok")
    end

    it "says changed when serving found other bytes behind the same stat, or a file grown past the limit" do
      server = Monadic::Workbench::AssetServer.new(->(_env) { [200, {}, []] }, live: live, private_chat: ->(_c) { false })
      full = write("a.txt", "abc")
      item_id = channel.open_file({ "path" => "a.txt" }, session, tab: "tab-1", generation: 1, live: live)["item_id"]
      url = channel.view(session, tab: "tab-1", generation: 1, live: live)["assets"][item_id]
      mtime = File.mtime(full)
      File.binwrite(full, "xyz")
      File.utime(mtime, mtime, full)
      env = { "PATH_INFO" => url, "REQUEST_METHOD" => "GET", "HTTP_SEC_FETCH_SITE" => "same-origin" }
      expect(server.call(env).first).to eq(409)
      after = channel.view(session, tab: "tab-1", generation: 1, live: live)
      expect(after["board"][:items].first[:status]).to eq("changed")
      expect(after["assets"]).not_to have_key(item_id)

      write("b.txt", "b")
      other = channel.open_file({ "path" => "b.txt" }, session, tab: "tab-1", generation: 1, live: live)["item_id"]
      url = channel.view(session, tab: "tab-1", generation: 1, live: live)["assets"][other]
      stub_const("Monadic::Workbench::FileItem::LIMIT", 2)
      write("b.txt", "bigger")
      expect(server.call(env.merge("PATH_INFO" => url)).first).to eq(409)
    end

    it "reads a few files at once and tells the others to try again" do
      stub_const("Monadic::Workbench::FileItem::READS", 1)
      stub_const("Monadic::Workbench::FileItem::READ_WAIT", 0.05)
      inside = Queue.new
      leave = Queue.new
      holder = Thread.new { Monadic::Workbench::FileItem.turn { inside << true; leave.pop } }
      inside.pop
      expect { Monadic::Workbench::FileItem.turn { :never } }.to raise_error(Monadic::Workbench::FileItem::Busy)
      leave << true
      holder.join
      expect(Monadic::Workbench::FileItem.turn { :now }).to eq(:now)
    end

    it "tells the chat's other tabs when a file is opened" do
      write("a.txt", "a")
      expect(channel).to receive(:changed).with(chat).once
      channel.open_file({ "path" => "a.txt" }, session, tab: "tab-1", generation: 1, live: live)
      channel.open_file({ "path" => "a.txt" }, session, tab: "tab-1", generation: 1, live: live)
    end
  end
end

