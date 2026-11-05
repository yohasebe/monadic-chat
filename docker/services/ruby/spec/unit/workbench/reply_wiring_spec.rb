# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workspace"

# A reply that offered a candidate ends with its message recorded: the
# candidate becomes that message's and the page is sent the board with the
# token that answers it. The real streaming and HTML handlers; the provider
# call is played by a fake app that offers a candidate as the tool does.
RSpec.describe "the workbench when a reply is recorded" do
  def png
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [8, 8].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { [] }
  let(:queue) { Queue.new }
  let(:root) { Dir.mktmpdir }
  let(:store) { Monadic::Workbench::Store.new(File.join(root, "workbench")) }
  let(:shared) { File.join(root, "data").tap { |d| Dir.mkdir(d) } }
  let(:session) do
    { parameters: {}, messages: [], chat_id: Monadic::Workspace::Ids.generate(:chat), _ws_generation: 1 }
  end

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Approvals.reset!
    Monadic::Workbench::Offer.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(shared)
    # The real handlers sync the chat: nothing of it reaches the history or
    # the state folder of the computer running the specs.
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(root)
    allow(Monadic::History).to receive(:enabled?).and_return(false)
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << JSON.parse(msg) }
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:detect_language).and_return("en")
    Thread.current[:rack_session] = session
    Thread.current[:websocket_session_id] = "tab-1"
    WebSocketHelper.register_live_session("tab-1", session, 1)
  end

  after do
    WebSocketHelper.unregister_live_session("tab-1", 1)
    Thread.current[:rack_session] = nil
    Thread.current[:websocket_session_id] = nil
    FileUtils.rm_rf(root)
  end

  def offering_app(store, bytes)
    Object.new.tap do |app|
      app.define_singleton_method(:api_request) do |_role, session, &_block|
        caller = Monadic::Workbench::Caller.new(chat_id: session[:chat_id], epoch: 0,
                                                request_id: Monadic::Workspace::RequestContext.current.request_id,
                                                session: session)
        job = Monadic::Workbench::JobOutput.make(session[:chat_id], store: store)
        Monadic::Workbench::JobOutput.write!(Monadic::Workbench::JobOutput.out_dir(job), "cat.png", bytes, root: store.root)
        offered = Monadic::Workbench::Offer.image(caller, job)
        [{ "choices" => [{ "message" => { "content" => Monadic::Workbench::Offer.reply_text(offered),
                                          Monadic::Workbench::Offer::ITEMS_KEY => [offered.item_id] },
                           "finish_reason" => "stop" }] }]
      end
      app.define_singleton_method(:settings) { {} }
    end
  end

  it "gives the image to the reply's message and sends the page a token for it" do
    stub_const("APPS", { "FakeApp" => offering_app(store, png) })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "a cat", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    message = session[:messages].last
    expect(message["role"]).to eq("assistant")
    board = Monadic::Workbench::Board.for(session[:chat_id])
    item = board.snapshot[:items].first
    expect(item[:mid]).to eq(message["mid"])
    view = broadcasts.find { |m| m["type"] == "workbench" }
    expect(view["approvals"].keys).to eq([item[:id]])
  end

  it "saves when the page asks, in the connection's turn, and tells the page" do
    stub_const("APPS", { "FakeApp" => offering_app(store, png) })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "a cat", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    view = broadcasts.find { |m| m["type"] == "workbench" }
    item = view["board"]["items"].first
    host.send(:handle_ws_workbench_action, nil,
              { "item_id" => item["id"], "action" => "save", "token" => view["approvals"][item["id"]],
                "operation_id" => "op-00000001" },
              session)
    expect(broadcasts.find { |m| m["type"] == "workbench_result" }).to include("state" => "recorded", "name" => "cat.png")
    expect(broadcasts.find { |m| m["type"] == "message_artifacts" }).to include("mid" => session[:messages].last["mid"])
    expect(File.binread(File.join(shared, "cat.png"))).to eq(png)
    expect(session[:messages].last["artifacts"].first["name"]).to eq("cat.png")
  end

  it "keeps the image of a reply that ends without its message, and closes that reply" do
    stub_const("APPS", { "FakeApp" => offering_app(store, png) })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "a cat", "app_name" => "FakeApp" }, session, queue)
    thread.join
    host.send(:stop_reply_work, thread)
    item = Monadic::Workbench::Board.for(session[:chat_id]).snapshot[:items].first
    expect(item[:mid]).to be_nil
    request_id = Monadic::Workbench::Board.for(session[:chat_id]).item(item[:id]).dig("origin", "request_id")
    expect(Monadic::Workbench::Offer.closed?(request_id)).to be(true)
  end
end
