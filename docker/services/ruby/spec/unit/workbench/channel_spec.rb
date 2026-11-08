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

  around do |example|
    Dir.mktmpdir("workbench-channel-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { chat_id: chat, _ws_generation: 1,
      messages: [{ "mid" => "m-user", "role" => "user", "text" => "a cat" },
                 { "mid" => "m-1", "role" => "assistant", "text" => "Here it is." }] }
  end
  let(:tab) { "tab-1" }
  let(:channel) { Monadic::Workbench::Channel }
  # The generation of each tab's connection now.
  let(:live_tabs) { { "tab-1" => 1 } }
  let(:live) { ->(t) { live_tabs[t] } }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::ViewTokens.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  def board
    Monadic::Workbench::Board.for(chat, store: store)
  end

  def image(name = "cat.png", salt = "", for_chat: chat)
    request = Monadic::Workspace::Ids.generate(:request)
    on = Monadic::Workbench::Board.for(for_chat, store: store)
    item = on.add_image(bytes: png(64, 48, salt), epoch: Monadic::Workspace::Chats.epoch(for_chat), name: name,
                        origin: { actor: :agent, request_id: request }, run: "j_#{SecureRandom.hex(10)}", app_name: "Image Generator")
    # The reply that offered it was recorded as the message m-1.
    on.attach_reply(request, "m-1", [item["id"]])
    item
  end

  def file_of(item)
    File.join(@data, item.dig("artifact", "path"))
  end

  def view(generation: 1, on_tab: tab)
    channel.view(session, tab: on_tab, generation: generation, live: live)
  end

  def remove(item, token, operation_id: "op-00000001", generation: 1, on_tab: tab)
    obj = { "item_id" => item["id"], "action" => "remove", "token" => token, "operation_id" => operation_id }
    channel.act(obj, session, tab: on_tab, generation: generation, live: live)
  end

  def download(artifact_id, generation: 1, on_tab: tab)
    channel.download({ "artifact_id" => artifact_id }, session, tab: on_tab, generation: generation, live: live)
  end

  describe "the view" do
    it "gives a chat without a board an empty one and makes nothing for it" do
      message = view
      expect(message["board"][:items]).to eq([])
      expect(message["approvals"]).to eq({})
      expect(store.exists?(chat)).to be(false)
    end

    it "says so also in a connection's first view, marked initial, so that a page lets another chat's board go" do
      first = channel.view(session, tab: tab, generation: 1, live: live, initial: true)
      expect(first["board"][:chat_id]).to eq(chat)
      expect(first["board"][:items]).to eq([])
      expect(first["initial"]).to be(true)
      expect(store.exists?(chat)).to be(false)
    end

    it "gives every image a token for this connection, an address, and where it is in the shared folder" do
      item = image
      message = view
      expect(message["approvals"].keys).to eq([item["id"]])
      expect(message["assets"][item["id"]]).to start_with("/workbench/asset/")
      expect(message["board"][:items].first).to include(path: item.dig("artifact", "path"), status: "ok")
      expect(message["board"].to_s).not_to include(message["approvals"][item["id"]])
      expect(message["board"].to_s).not_to include(@data)
      expect(view["approvals"]).to eq(message["approvals"])
      live_tabs[tab] = 2
      expect(view(generation: 2)["approvals"]).not_to eq(message["approvals"])
    end

    it "gives no address for an image whose file changed or is gone, and says which" do
      changed = image("a.png", "1")
      gone = image("b.png", "2")
      File.binwrite(file_of(changed), png(64, 48, "other"))
      File.unlink(file_of(gone))
      message = view
      expect(message["assets"]).to be_empty
      expect(message["board"][:items].map { |i| i[:status] }).to eq(%w[changed missing])
    end
  end

  describe "removing an image" do
    it "takes it off the board, keeps its file, and answers a removal sent again" do
      item = image
      token = view["approvals"][item["id"]]
      expect(remove(item, token)).to include("status" => "accepted", "action" => "remove", "item_id" => item["id"])
      expect(board.item(item["id"])).to be_nil
      expect(File.file?(file_of(item))).to be(true)
      # The same operation again (its result was lost) is told it was done.
      expect(remove(item, token)).to include("status" => "same")
    end

    it "refuses a token of another tab, another connection, another item, or none" do
      first = image("a.png", "1")
      token = view["approvals"][first["id"]]
      second = image("b.png", "2")
      expect(remove(first, token, on_tab: "tab-2")).to include("status" => "refused", "reason" => "not_allowed")
      expect(remove(first, token, generation: 2)).to include("status" => "refused")
      expect(remove(first, nil)).to include("status" => "refused")
      expect(remove(second, token)).to include("status" => "refused", "reason" => "not_allowed")
      expect(board.snapshot[:items].size).to eq(2)
    end

    it "forgets the tokens of a closed connection and of a replaced chat" do
      item = image
      message = view
      address = message["assets"][item["id"]].delete_prefix(Monadic::Workbench::AssetServer::PREFIX)
      channel.connection_closed(tab, 1)
      expect(Monadic::Workbench::ViewTokens.view(address)).to be_nil
      expect(remove(item, message["approvals"][item["id"]])).to include("status" => "refused")
      live_tabs[tab] = 2
      message = view(generation: 2)
      Monadic::Workspace::Chats.replacing!(session)
      expect(Monadic::Workbench::Approvals.grant(message["approvals"][item["id"]], tab: tab, generation: 2)).to be_nil
      expect(Monadic::Workbench::ViewTokens.view(message["assets"][item["id"]].delete_prefix("/workbench/asset/"))).to be_nil
    end

    it "refuses the old connection once a newer one is the tab's, and a token of the chat the tab left" do
      item = image
      token = view["approvals"][item["id"]]
      live_tabs[tab] = 2
      expect(remove(item, token)).to include("status" => "refused", "reason" => "not_allowed")
      expect(view).to be_nil
      live_tabs[tab] = 1
      session[:chat_id] = Monadic::Workspace::Ids.generate(:chat)
      expect(remove(item, token)).to include("status" => "refused", "reason" => "not_allowed")
    end

    it "leaves alone a replaced chat whose id this server did not issue, and writes nothing when one is replaced" do
      expect { Monadic::Workspace::Chats.replacing!({ chat_id: "chat-a" }) }.not_to raise_error
      image
      revision = board.snapshot[:revision]
      Monadic::Workspace::Chats.replacing!(session)
      expect(board.snapshot[:revision]).to eq(revision)
    end
  end

  describe "an address to save a copy" do
    it "is given for an image of the chat, also once it is off the board" do
      item = image
      remove(item, view["approvals"][item["id"]])
      result = download(item.dig("artifact", "id"))
      expect(result).to include("type" => "workbench_download", "artifact_id" => item.dig("artifact", "id"),
                                "name" => item.dig("artifact", "name"))
      expect(result["url"]).to start_with("/workbench/asset/")
    end

    it "is refused for another chat's image, an id that is not one, a Private chat, or an old connection" do
      theirs = image("a.png", "1", for_chat: Monadic::Workspace::Ids.generate(:chat))
      expect(download(theirs.dig("artifact", "id"))).to include("status" => "refused")
      expect(download("../x")).to include("status" => "refused")
      mine = image
      live_tabs[tab] = 2
      expect(download(mine.dig("artifact", "id"))).to include("status" => "refused")
      live_tabs[tab] = 1
      allow(Monadic::History::Policy).to receive(:known_private?).and_return(true)
      expect(download(mine.dig("artifact", "id"))).to include("status" => "refused")
    end
  end

  describe "the asset server" do
    let(:private_chats) { [] }
    let(:app) { ->(_env) { [200, {}, ["app"]] } }
    let(:server) do
      Monadic::Workbench::AssetServer.new(app, live: live, private_chat: ->(c) { private_chats.include?(c) })
    end

    def fetch_asset(path, site: "same-origin", method: "GET")
      server.call({ "PATH_INFO" => path, "REQUEST_METHOD" => method, "HTTP_SEC_FETCH_SITE" => site })
    end

    it "serves the image's bytes to a page of this server, kept from caches and other sites" do
      item = image
      status, headers, body = fetch_asset(view["assets"][item["id"]])
      expect(status).to eq(200)
      expect(body.join).to eq(png(64, 48))
      expect(headers).to include("content-type" => "image/png", "cache-control" => "no-store",
                                 "x-content-type-options" => "nosniff",
                                 "cross-origin-resource-policy" => "same-origin", "referrer-policy" => "no-referrer")
      expect(headers).not_to have_key("content-disposition")
    end

    it "serves a download as a file to save under the image's name" do
      item = image
      status, headers, body = fetch_asset(download(item.dig("artifact", "id"))["url"])
      name = item.dig("artifact", "name")
      expect(status).to eq(200)
      expect(body.join).to eq(png(64, 48))
      expect(headers["content-disposition"]).to eq("attachment; filename=\"#{name}\"; filename*=UTF-8''#{name}")
    end

    it "gives the same not-found to other sites, other methods, unknown and expired tokens" do
      item = image
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
      item = image
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

    it "does not serve a token given at an earlier epoch, or for an image of another chat" do
      item = image
      issue = lambda do |**over|
        token = Monadic::Workbench::ViewTokens.issue(
          **{ tab: tab, generation: 1, chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat),
              artifact_id: item.dig("artifact", "id"), sha256: item.dig("artifact", "sha256") }.merge(over)
        )
        "/workbench/asset/#{token}"
      end
      expect(fetch_asset(issue.call(epoch: Monadic::Workspace::Chats.epoch(chat) - 1)).first).to eq(404)
      other = Monadic::Workspace::Ids.generate(:chat)
      expect(fetch_asset(issue.call(chat_id: other, epoch: Monadic::Workspace::Chats.epoch(other))).first).to eq(404)
    end

    it "answers changed or gone for a file that is no longer the one recorded, and serves no other version" do
      item = image
      address = view["assets"][item["id"]]
      File.binwrite(file_of(item), png(64, 48, "x"))
      expect(fetch_asset(address).first).to eq(409)
      File.unlink(file_of(item))
      expect(fetch_asset(address).first).to eq(410)
      expect(fetch_asset(address).last.join).not_to include("PNG")
    end

    it "leaves every other address to the application" do
      expect(fetch_asset("/workbench/other").last).to eq(["app"])
    end
  end

  describe "the reply's message" do
    it "becomes the message of what the reply put on the board, once" do
      request = Monadic::Workspace::Ids.generate(:request)
      item = board.add_image(bytes: png(64, 48), epoch: Monadic::Workspace::Chats.epoch(chat), name: "cat.png",
                             origin: { actor: :agent, request_id: request }, run: "j_#{SecureRandom.hex(10)}", app_name: "x")
      expect(channel.reply_recorded(session, "m-2", request, [item["id"]])).to be(true)
      expect(board.item(item["id"])["mid"]).to eq("m-2")
      expect(channel.reply_recorded(session, "m-3", request, [item["id"]])).to be(false)
    end
  end
end
