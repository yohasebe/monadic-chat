# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../lib/monadic/utils/privacy/language_detector"

# A message the user sends carries what the page shows on the work screen;
# the server makes what the model is told of it once, with the request, and
# keeps none of it with the chat's parameters.
RSpec.describe "The work screen observation of a message" do
  around do |example|
    Dir.mktmpdir("observation-request") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      previous = Thread.current[:websocket_session_id]
      Thread.current[:websocket_session_id] = "tab-1"
      example.run
    ensure
      Thread.current[:websocket_session_id] = previous
    end
  end

  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:session) { { parameters: {}, messages: [], chat_id: chat, _ws_generation: 1 } }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    @live = Monadic::Workbench::Board.live
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(tab) { tab == "tab-1" ? 1 : nil }
  end

  after { Monadic::Workbench::Board.live = @live }

  def opened
    File.binwrite(File.join(@data, "a.txt"), "one\ntwo\n")
    Monadic::Workbench::Board.for(chat, store: store)
                             .add_file(path: "a.txt", origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 },
                                       epoch: Monadic::Workspace::Chats.epoch(chat)).first
  end

  def send_message(obj)
    seen = []
    app = Object.new
    app.define_singleton_method(:api_request) do |_role, _session, &block|
      seen << Monadic::Workspace::RequestContext.current
      block.call({ "type" => "fragment", "content" => "ok" })
      [{ "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }] }]
    end
    app.define_singleton_method(:settings) { {} }
    stub_const("APPS", { "FakeApp" => app })
    allow(host).to receive(:send_or_broadcast)
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:send_error)
    thread = host.send(:handle_ws_streaming, nil, obj.merge("app_name" => "FakeApp"), session, Queue.new)
    raise "the answer did not finish" if thread && thread.join(10).nil?

    seen.last
  end

  it "makes the observation once for a message the user sent, with the range checked, keeping none of it in the parameters" do
    item = opened
    reported = { "item_id" => item["id"], "version" => item.dig("file", "sha256"), "range" => nil, "note" => "not_shown" }
    context = send_message({ "message" => "what is this?", "workbench_range" => reported })
    observation = context.observation
    expect(observation.request_id).to eq(context.request_id)
    expect(observation.data.dig("work_screen", "selected")).to include("id" => item["id"], "range_note" => "not_shown")
    expect(observation.data).to be_frozen
    expect(session[:parameters]).not_to have_key("workbench_range")
    expect(session[:messages].find { |m| m["role"] == "user" }["text"]).to eq("what is this?")
  end

  it "makes the observation for a message of images only" do
    opened
    image = { "title" => "a.png", "type" => "image/png", "data" => "data:image/png;base64,iVBORw0KGgo=" }
    expect(send_message({ "message" => "", "images" => [image] }).observation).not_to be_nil
  end

  it "makes none for a send that is not the user's message, or in a Private chat" do
    opened
    expect(send_message({ "message" => "" }).observation).to be_nil
    allow(Monadic::History::Policy).to receive(:private?).and_return(true)
    expect(send_message({ "message" => "hello" }).observation).to be_nil
  end

  it "sends the message when the observation cannot be made" do
    opened
    allow(Monadic::Workbench::Observation).to receive(:for_request).and_raise(RuntimeError, "broken")
    context = send_message({ "message" => "hello" })
    expect(context).not_to be_nil
    expect(context.observation).to be_nil
  end
end
