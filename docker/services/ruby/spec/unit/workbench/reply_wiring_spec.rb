# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workspace"

# A reply that put an image on the workbench ends with its message
# recorded: the image becomes that message's, the message records what the
# reply made, and the page is sent the board with the token for it. The real streaming and HTML handlers; the provider
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
    Monadic::Workspace::Ledger.clear_unsettled!
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
        Monadic::Workbench::Offer.end_reply(Monadic::Workbench::Offer.image(caller, job))
      end
      app.define_singleton_method(:settings) { {} }
    end
  end

  # A provider call that shows a file of the shared folder as the tool
  # does, then answers with text (or with nothing).
  def showing_app(path, answer: "Here it is")
    Object.new.tap do |app|
      app.define_singleton_method(:api_request) do |_role, session, &_block|
        request = Monadic::Workspace::RequestContext.current
        caller = Monadic::Workbench::Caller.new(chat_id: session[:chat_id], epoch: 0, request_id: request.request_id,
                                                session: session, tab: request.tab, generation: request.generation)
        Class.new { include MonadicSharedTools::WorkbenchTools }.new.show_on_workbench(path: path, workbench: caller)
        answer ? [{ "choices" => [{ "message" => { "content" => answer }, "finish_reason" => "stop" }] }] : []
      end
      app.define_singleton_method(:settings) { {} }
    end
  end

  # A provider call whose tool changes the app's state by turn
  # (Monadic::TurnState), then answers with text.
  def state_app(running, answer: "Noted")
    require_relative "../../../lib/monadic/shared_tools/monadic_session_state"
    Object.new.tap do |app|
      app.define_singleton_method(:api_request) do |_role, session, &_block|
        request = Monadic::Workspace::RequestContext.current
        running[0] = Monadic::Workbench::Caller.new(chat_id: session[:chat_id], epoch: Monadic::Workspace::Chats.epoch(session[:chat_id]),
                                                    request_id: request.request_id, session: session)
        Class.new { include Monadic::SharedTools::MonadicSessionState }.new
             .monadic_save_state(key: "notes", payload: { "a" => 1 }, session: session)
        answer ? [{ "choices" => [{ "message" => { "content" => answer }, "finish_reason" => "stop" }] }] : []
      end
      app.define_singleton_method(:settings) { { turn_state: true } }
    end
  end

  it "gives what the reply changed in its app's state to its message, and lets it go when the reply has none" do
    running = []
    allow(Monadic::Workbench::Caller).to receive(:current) { running[0] }
    Monadic::TurnState.reset!
    stub_const("APPS", { "FakeApp" => state_app(running) })
    session[:parameters] = { "app_name" => "FakeApp" }
    thread = host.send(:handle_ws_streaming, nil, { "message" => "note", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    thread.join(5)
    expect(session[:messages].last["state_changes"]).to eq([{ "app" => "FakeApp", "kind" => "value", "key" => "notes",
                                                              "op" => "set", "data" => { "a" => 1 } }])

    stub_const("APPS", { "FakeApp" => state_app(running, answer: nil) })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "again", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    thread.join(5)
    expect(session[:messages].count { |m| m["state_changes"] }).to eq(1)
  end

  it "gives the files the reply showed to its message before it is sent" do
    require_relative "../../../lib/monadic/shared_tools/workbench_tools"
    File.write(File.join(shared, "plan.md"), "# Plan")
    stub_const("APPS", { "FakeApp" => showing_app("plan.md") })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "show", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    thread.join(5)
    message = session[:messages].last
    expect(message["workbench_shown"]).to match([a_hash_including("path" => "plan.md", "render" => "markdown")])
    sent = broadcasts.find { |m| m["type"] == "html" }
    expect(sent["content"]["workbench_shown"]).to eq(message["workbench_shown"])
  end

  it "gives what the reply made in the chat's folder to its message" do
    require_relative "../../../lib/monadic/shared_tools/workbench_tools"
    app = Object.new.tap do |made_app|
      made_app.define_singleton_method(:api_request) do |_role, session, &_block|
        request = Monadic::Workspace::RequestContext.current
        caller = Monadic::Workbench::Caller.new(chat_id: session[:chat_id], epoch: Monadic::Workspace::Chats.epoch(session[:chat_id]),
                                                request_id: request.request_id, session: session, tab: request.tab,
                                                generation: request.generation)
        Class.new { include MonadicSharedTools::WorkbenchTools }.new.put_on_workbench(name: "draft.md", content: "x", workbench: caller)
        [{ "choices" => [{ "message" => { "content" => "Done" }, "finish_reason" => "stop" }] }]
      end
      made_app.define_singleton_method(:settings) { {} }
    end
    stub_const("APPS", { "FakeApp" => app })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "write", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    thread.join(5)
    expect(session[:messages].last["workbench_made"]).to match([%r{\Aconversations/[^/]+/workbench/draft\.md\z}])
  end

  it "keeps nothing of a reply that ended without a message for the next one" do
    require_relative "../../../lib/monadic/shared_tools/workbench_tools"
    File.write(File.join(shared, "plan.md"), "# Plan")
    stub_const("APPS", { "FakeApp" => showing_app("plan.md", answer: nil) })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "show", "app_name" => "FakeApp" }, session, queue)
    thread.join(5)
    request_id = session[:messages].find { |m| m["role"] == "user" }["request_id"]
    expect(Monadic::Workbench::Shown.seal(request_id)).to eq([])
    stub_const("APPS", { "FakeApp" => showing_app("missing.md", answer: "No file") })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "again", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    thread.join(5)
    expect(session[:messages].last).to include("text" => a_string_including("No file"))
    expect(session[:messages].last).not_to have_key("workbench_shown")
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
    expect(message["artifacts"]).to eq([board.item(item[:id])["artifact"].slice(*Monadic::Workbench::Record::FIELDS)])
    expect(broadcasts.find { |m| m["type"] == "html" }.dig("content", "artifacts")).to eq(message["artifacts"])
    expect(message["workbench_made"]).to eq([message["artifacts"].first["path"]])
  end

  it "gives the page an address to save a copy of what the message records, in the connection's turn" do
    stub_const("APPS", { "FakeApp" => offering_app(store, png) })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "a cat", "app_name" => "FakeApp" }, session, queue)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    entry = session[:messages].last["artifacts"].first
    host.send(:handle_ws_workbench_download, nil, { "artifact_id" => entry["id"] }, session)
    answer = broadcasts.find { |m| m["type"] == "workbench_download" }
    expect(answer).to include("artifact_id" => entry["id"], "name" => entry["name"])
    expect(answer["url"]).to start_with(Monadic::Workbench::AssetServer::PREFIX)
    expect(File.binread(File.join(shared, entry["path"]))).to eq(png)
  end

  it "moves the image of a reply that ends without its message to the trash, and closes that reply" do
    stub_const("APPS", { "FakeApp" => offering_app(store, png) })
    thread = host.send(:handle_ws_streaming, nil, { "message" => "a cat", "app_name" => "FakeApp" }, session, queue)
    wait_for_answer_made(thread)
    board = Monadic::Workbench::Board.for(session[:chat_id])
    item = board.snapshot[:items].first
    placed = board.item(item[:id])
    path = placed.dig("artifact", "path")
    host.send(:stop_reply_work, thread)

    expect(Monadic::Workbench::Offer.closed?(placed.dig("origin", "request_id"))).to be(true)
    expect(board.snapshot[:items]).to be_empty
    expect(File.exist?(File.join(Monadic::Utils::Environment.data_path, path))).to be(false)
    folder = path.split("/").first(2).join("/")
    trashed = Dir.glob(File.join(Monadic::Utils::Environment.data_path, folder, "trash", "*stopped-*", "**", "*"))
    expect(trashed.map { |f| File.basename(f) }).to include(File.basename(path))
  end
end
