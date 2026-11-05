# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/channel"

RSpec.describe "the workbench over the main socket (channel, asset server)" do
  def png(width, height, salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [width, height].pack("NN") + "\x08\x02\x00\x00\x00".b +
      "\x00" * 4 + salt.b
  end

  let(:state) { Dir.mktmpdir }
  let(:shared) { Dir.mktmpdir }
  let(:store) { Monadic::Workbench::Store.new(File.join(state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { chat_id: chat, _ws_generation: 1,
      messages: [{ "mid" => "m-user", "role" => "user", "text" => "a cat" },
                 { "mid" => "m-1", "role" => "assistant", "text" => "Here it is." }] }
  end
  let(:tab) { "tab-1" }
  let(:synced) { [] }
  let(:delivered) { [] }
  let(:recorder) do
    Monadic::Workbench::Channel.recorder_for(session, sync: -> { synced << true }, deliver: ->(m) { delivered << m })
  end
  let(:channel) { Monadic::Workbench::Channel }
  # The generation of each tab's connection now.
  let(:live_tabs) { { "tab-1" => 1 } }
  let(:live) { ->(t) { live_tabs[t] } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::ViewTokens.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
  end

  after do
    FileUtils.rm_rf(state)
    FileUtils.rm_rf(shared)
  end

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def candidate(name = "cat.png", salt = "")
    item = board.add_candidate(bytes: png(64, 48, salt), epoch: Monadic::Workspace::Chats.epoch(chat),
                               origin: { actor: :agent, request_id: "q-#{name}" }, name: name)
    # The reply that offered it was recorded as the message m-1.
    board.attach_reply("q-#{name}", "m-1", [item["id"]])
    item
  end

  def view(generation: 1, on_tab: tab)
    channel.view(session, tab: on_tab, generation: generation, live: live)
  end

  def answer(item, token, action: "save", operation_id: "op-00000001", generation: 1, on_tab: tab)
    obj = { "item_id" => item["id"], "action" => action, "token" => token, "operation_id" => operation_id }
    channel.act(obj, session, tab: on_tab, generation: generation, recorder: recorder, live: live)
  end

  describe "the view" do
    it "gives a chat without a board an empty one and makes nothing for it" do
      message = view
      expect(message["board"][:items]).to eq([])
      expect(message["approvals"]).to eq({})
      expect(channel.view(session, tab: tab, generation: 1, live: live, only_existing: true)).to be_nil
      expect(store.exists?(chat)).to be(false)
    end

    it "gives every image a token for this connection and an address" do
      item = candidate
      message = view
      expect(message["approvals"].keys).to eq([item["id"]])
      expect(message["assets"][item["id"]]).to start_with("/workbench/asset/")
      expect(message["board"].to_s).not_to include(message["approvals"][item["id"]])
      expect(view["approvals"]).to eq(message["approvals"])
      live_tabs[tab] = 2
      expect(view(generation: 2)["approvals"]).not_to eq(message["approvals"])
    end
  end

  describe "the answer" do
    it "saves the candidate, records it in the message that asked and tells the page" do
      item = candidate
      result = answer(item, view["approvals"][item["id"]])
      expect(result).to include("status" => "accepted", "state" => "recorded", "name" => "cat.png")
      expect(File.binread(File.join(shared, "cat.png"))).to eq(png(64, 48))
      expect(File.stat(File.join(shared, "cat.png")).mode & 0o044).to eq(0o044)
      record = session[:messages].last["artifacts"]
      expect(record.size).to eq(1)
      expect(record.first).to include("name" => "cat.png", "sha256" => Digest::SHA256.hexdigest(png(64, 48)),
                                      "content_type" => "image/png", "action" => "saved", "by" => "user")
      expect(Monadic::Workbench::Record.clean(record)).to eq(record)
      expect(synced).not_to be_empty
      expect(delivered.last).to include("type" => "message_artifacts", "mid" => "m-1", "chat_id" => chat)
    end

    it "gives the same answer sent again the same result and saves once" do
      item = candidate
      token = view["approvals"][item["id"]]
      answer(item, token)
      again = answer(item, token)
      expect(again).to include("status" => "same", "state" => "recorded")
      expect(Dir.children(shared).grep(/\.png\z/)).to eq(["cat.png"])
      expect(session[:messages].last["artifacts"].size).to eq(1)
    end

    it "refuses a token of another tab, another connection, or none" do
      item = candidate
      token = view["approvals"][item["id"]]
      expect(answer(item, token, on_tab: "tab-2")).to include("status" => "refused", "reason" => "not_allowed")
      expect(answer(item, token, generation: 2)).to include("status" => "refused")
      expect(answer(item, nil)).to include("status" => "refused")
      expect(Dir.children(shared)).to be_empty
    end

    it "refuses a token sent for another item than its own" do
      first = candidate("a.png", "1")
      token = view["approvals"][first["id"]]
      second = candidate("b.png", "2")
      expect(answer(second, token)).to include("status" => "refused", "reason" => "not_allowed")
      expect(Dir.children(shared)).to be_empty
    end

    it "forgets the tokens of a closed connection and of a replaced chat" do
      item = candidate
      message = view
      token = message["approvals"][item["id"]]
      address = message["assets"][item["id"]].delete_prefix(Monadic::Workbench::AssetServer::PREFIX)
      channel.connection_closed(tab, 1)
      expect(Monadic::Workbench::ViewTokens.view(address)).to be_nil
      live_tabs[tab] = 2
      message = view(generation: 2)
      Monadic::Workspace::Chats.replacing!(session)
      expect(Monadic::Workbench::Approvals.grant(message["approvals"][item["id"]], tab: tab, generation: 2)).to be_nil
      expect(Monadic::Workbench::ViewTokens.view(message["assets"][item["id"]].delete_prefix("/workbench/asset/"))).to be_nil
      expect(token).not_to be_nil
    end

    it "refuses the old connection once a newer one is the tab's, before the old one closes" do
      item = candidate
      token = view["approvals"][item["id"]]
      live_tabs[tab] = 2
      expect(answer(item, token)).to include("status" => "refused", "reason" => "not_allowed")
      expect(view).to be_nil
      expect(Dir.children(shared)).to be_empty
    end

    it "refuses a token of the chat the tab left for another" do
      item = candidate
      token = view["approvals"][item["id"]]
      session[:chat_id] = Monadic::Workspace::Ids.generate(:chat)
      expect(answer(item, token)).to include("status" => "refused", "reason" => "not_allowed")
    end

    it "leaves alone a replaced chat whose id this server did not issue" do
      expect { Monadic::Workspace::Chats.replacing!({ chat_id: "chat-a" }) }.not_to raise_error
    end

    it "writes nothing when a chat is replaced" do
      item = candidate
      answer(item, view["approvals"][item["id"]])
      revision = board.snapshot[:revision]
      Monadic::Workspace::Chats.replacing!(session)
      expect(board.snapshot[:revision]).to eq(revision)
    end

    it "refuses a token whose connection closed; the image stays, for the tab's next connection" do
      item = candidate
      token = view["approvals"][item["id"]]
      channel.connection_closed(tab, 1)
      expect(answer(item, token)).to include("status" => "refused")
      expect(board.item(item["id"])).not_to be_nil
      live_tabs[tab] = 2
      expect(answer(item, view(generation: 2)["approvals"][item["id"]], generation: 2)).to include("state" => "recorded")
    end

    it "refuses a token of a chat the user replaced" do
      item = candidate
      token = view["approvals"][item["id"]]
      Monadic::Workspace::Chats.replacing!(session)
      expect(answer(item, token)).to include("status" => "refused")
      expect(Dir.children(shared)).to be_empty
    end

    it "removes an image from the board with its bytes, and answers a removal sent again" do
      item = candidate
      bytes_dir = File.dirname(board.path(item.dig("candidate", "path")))
      token = view["approvals"][item["id"]]
      result = answer(item, token, action: "remove")
      expect(result).to include("status" => "accepted", "action" => "remove", "item_id" => item["id"])
      # The same operation again (its result was lost) is told it was done.
      expect(answer(item, token, action: "remove")).to include("status" => "same", "action" => "remove")
      expect(board.item(item["id"])).to be_nil
      expect(Dir.exist?(bytes_dir)).to be(false)
      expect(session[:messages].last).not_to have_key("artifacts")
    end

    it "reports a save that stopped; the same answer again finishes it" do
      item = candidate
      token = view["approvals"][item["id"]]
      allow(File).to receive(:link).and_raise(Errno::EACCES)
      expect(answer(item, token)).to include("status" => "incomplete")
      allow(File).to receive(:link).and_call_original
      expect(answer(item, token)).to include("status" => "same", "state" => "recorded")
      expect(Dir.children(shared).grep(/\.png\z/)).to eq(["cat.png"])
    end
  end

  describe "the record" do
    it "waits while the chat is not this session's, and is made when the chat is open again" do
      item = candidate
      token = view["approvals"][item["id"]]
      other = { chat_id: Monadic::Workspace::Ids.generate(:chat), messages: [] }
      away = channel.recorder_for(other, sync: -> {}, deliver: ->(_) {})
      result = channel.act({ "item_id" => item["id"], "action" => "save", "token" => token, "operation_id" => "op-00000001" },
                           session, tab: tab, generation: 1, recorder: away, live: live)
      expect(result).to include("state" => "shared_copied")
      expect(session[:messages].last).not_to have_key("artifacts")
      expect(channel.settle(session, recorder: recorder)).to be(true)
      expect(board.operation("op-00000001")["state"]).to eq("recorded")
      expect(session[:messages].last["artifacts"].size).to eq(1)
    end

    it "gives a message back the record of a save its history missed, once" do
      item = candidate
      answer(item, view["approvals"][item["id"]])
      session[:messages].last.delete("artifacts")
      synced.clear
      delivered.clear
      expect(channel.settle(session, recorder: recorder)).to be(false)
      expect(session[:messages].last["artifacts"].map { |a| a["name"] }).to eq(["cat.png"])
      expect(delivered.map { |m| m["type"] }).to eq(["message_artifacts"])
      channel.settle(session, recorder: recorder)
      expect(session[:messages].last["artifacts"].size).to eq(1)
      expect(synced.size).to eq(1)
    end

    it "waits for the message of an image whose reply still runs, and records the save there once it comes" do
      item = board.add_candidate(bytes: png(64, 48), epoch: Monadic::Workspace::Chats.epoch(chat),
                                 origin: { actor: :agent, request_id: "q-running" }, name: "cat.png")
      allow(Monadic::Workbench::Offer).to receive(:in_flight?).with("q-running").and_return(true)
      token = view["approvals"][item["id"]]
      expect(answer(item, token)).to include("state" => "shared_copied")
      expect(session[:messages].map { |m| m["artifacts"] }.compact).to be_empty
      # It cannot be removed while its save waits for the message.
      expect(answer(item, token, action: "remove", operation_id: "op-00000002")).to include("status" => "refused")
      channel.settle(session, recorder: recorder)
      expect(session[:messages].count { |m| m["artifacts"] }).to eq(0)
      board.attach_reply("q-running", "m-1", [item["id"]])
      allow(Monadic::Workbench::Offer).to receive(:in_flight?).with("q-running").and_return(false)
      channel.settle(session, recorder: recorder)
      expect(session[:messages].last["artifacts"].map { |a| a["name"] }).to eq(["cat.png"])
      expect(session[:messages].count { |m| m["artifacts"] }).to eq(1)
      expect(board.operation("op-00000001")["state"]).to eq("recorded")
    end

    it "records the save of an image whose reply recorded no message in a short message of its own, once" do
      item = board.add_candidate(bytes: png(64, 48), epoch: Monadic::Workspace::Chats.epoch(chat),
                                 origin: { actor: :agent, request_id: "q-stopped" }, name: "cat.png")
      answer(item, view["approvals"][item["id"]])
      note = session[:messages].last
      expect(note).to include("role" => "assistant", "text" => Monadic::Workbench::Offer.saved_note("cat.png"))
      expect(note["artifacts"].map { |a| a["name"] }).to eq(["cat.png"])
      expect(delivered.last).to include("type" => "html")
      expect(board.item(item["id"])["mid"]).to eq(note["mid"])
      channel.settle(session, recorder: recorder)
      expect(session[:messages].count { |m| m["artifacts"] }).to eq(1)
    end

    it "keeps nothing in the record of a Private chat" do
      allow(Monadic::History::Policy).to receive(:known_private?).with(chat).and_return(true)
      called = recorder.call(board: board, operation: { "mid" => "m-1" }, artifact: { id: "r_#{'0' * 20}" })
      expect(called).to be(false)
      expect(session[:messages].last).not_to have_key("artifacts")
    end
  end

  describe "the asset server" do
    let(:private_chats) { [] }
    let(:app) { ->(_env) { [200, {}, ["app"]] } }
    let(:server) do
      Monadic::Workbench::AssetServer.new(app, live: live, private_chat: ->(c) { private_chats.include?(c) },
                                               store: store)
    end

    def fetch_asset(path, site: "same-origin", method: "GET")
      server.call({ "PATH_INFO" => path, "REQUEST_METHOD" => method, "HTTP_SEC_FETCH_SITE" => site })
    end

    it "serves the candidate's bytes to a page of this server, kept from caches and other sites" do
      item = candidate
      status, headers, body = fetch_asset(view["assets"][item["id"]])
      expect(status).to eq(200)
      expect(body.join).to eq(png(64, 48))
      expect(headers).to include("content-type" => "image/png", "cache-control" => "no-store",
                                 "x-content-type-options" => "nosniff",
                                 "cross-origin-resource-policy" => "same-origin", "referrer-policy" => "no-referrer")
    end

    it "gives the same not-found to other sites, other methods, unknown and expired tokens" do
      item = candidate
      address = view["assets"][item["id"]]
      expect(fetch_asset(address, site: "cross-site").first).to eq(404)
      expect(fetch_asset(address, site: nil).first).to eq(404)
      expect(fetch_asset(address, method: "POST").first).to eq(404)
      expect(fetch_asset("/workbench/asset/#{'0' * 32}").first).to eq(404)
      now = Monadic::Workbench::ViewTokens.clock
      allow(Monadic::Workbench::ViewTokens).to receive(:clock).and_return(now + Monadic::Workbench::ViewTokens::TTL + 1)
      expect(fetch_asset(address).first).to eq(404)
    end

    it "stops serving when the tab's connection changed, the chat was replaced or is Private" do
      item = candidate
      address = view["assets"][item["id"]]
      live_tabs[tab] = 2
      expect(fetch_asset(address).first).to eq(404)
      live_tabs[tab] = 1
      private_chats << chat
      expect(fetch_asset(address).first).to eq(404)
      private_chats.clear
      expect(fetch_asset(address).first).to eq(200)
      Monadic::Workspace::Chats.replacing!(session)
      expect(fetch_asset(address).first).to eq(404)
    end

    it "does not serve a token given at an earlier epoch of the chat" do
      item = candidate
      token = Monadic::Workbench::ViewTokens.issue(tab: tab, generation: 1, chat_id: chat,
                                                   epoch: Monadic::Workspace::Chats.epoch(chat) - 1, item_id: item["id"],
                                                   sha256: item.dig("candidate", "sha256"))
      expect(fetch_asset("/workbench/asset/#{token}").first).to eq(404)
    end

    it "does not serve bytes that changed on disk" do
      item = candidate
      address = view["assets"][item["id"]]
      path = board.path(item.dig("candidate", "path"))
      File.chmod(0o600, path)
      File.binwrite(path, png(64, 48, "x"))
      expect(fetch_asset(address).first).to eq(404)
    end

    it "leaves every other address to the application" do
      expect(fetch_asset("/workbench/other").last).to eq(["app"])
    end
  end
end
