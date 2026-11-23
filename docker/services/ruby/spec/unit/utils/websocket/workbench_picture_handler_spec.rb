# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "base64"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/workspace"
require_relative "../../../../lib/monadic/history/serializer"

# A picture of the work screen sent with a message: taken when the message
# is accepted, given to its request, recorded on the message by reference,
# sent back to the tab that asks for it, and removed with the message. The
# real streaming handler; the provider call is played by a fake app.
RSpec.describe "The picture of the work screen sent with a message" do
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:sent) { [] }
  let(:queue) { Queue.new }
  let(:root) { Dir.mktmpdir }
  let(:chat_id) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { parameters: { "app_name" => "FakeApp", "model" => "gpt-6.1-terra" }, messages: [], chat_id: chat_id,
      _ws_generation: 1 }
  end
  let(:png) { "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [8, 8].pack("NN") + "\x08\x02\x00\x00\x00".b }
  let(:item) { { id: "i_1", kind: "file", preview: "pdf", version: "v" * 64 } }
  let(:seen) { [] }
  let(:selections) { [] }

  before do
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(root)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(root)
    allow(Monadic::History).to receive(:enabled?).and_return(false)
    allow(Monadic::Workbench::Board).to receive(:existing).and_call_original
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id)
                                                         .and_return(double("board", observe: { items: [item], selected: "i_1" }))
    allow(host).to receive(:send_or_broadcast) { |msg, *_| sent << JSON.parse(msg) }
    allow(host).to receive(:send_to_client) { |_c, msg| sent << msg }
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:detect_language).and_return("en")
    Thread.current[:rack_session] = session
    Thread.current[:websocket_session_id] = "tab-1"
    WebSocketHelper.register_live_session("tab-1", session, 1)
    seen_now = seen
    seen_selections = selections
    app = Object.new
    app.define_singleton_method(:api_request) do |_role, _session, &_block|
      seen_now << Monadic::Workspace::RequestContext.current&.picture
      seen_selections << Monadic::Workspace::RequestContext.current&.selection
      [{ "choices" => [{ "message" => { "content" => "ANSWER" }, "finish_reason" => "stop" }] }]
    end
    app.define_singleton_method(:settings) { {} }
    stub_const("APPS", { "FakeApp" => app })
  end

  after do
    WebSocketHelper.unregister_live_session("tab-1", 1)
    Thread.current[:rack_session] = nil
    Thread.current[:websocket_session_id] = nil
    Monadic::Workspace::Ledger.clear_unsettled!
    FileUtils.rm_rf(root)
  end

  def picture_data(overrides = {})
    { "item_id" => "i_1", "version" => "v" * 64, "page" => 2, "pages" => 4,
      "mark" => { "shape" => "rect", "x" => 0.1, "y" => 0.1, "w" => 0.3, "h" => 0.2 },
      "image" => Base64.strict_encode64(png) }.merge(overrides)
  end

  def send_message(extra = {})
    thread = host.send(:handle_ws_streaming, nil, { "message" => "What is this?", "app_name" => "FakeApp" }.merge(extra),
                       session, queue)
    wait_for_answer_made(thread)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    thread.join(5)
    session[:messages].reverse.find { |m| m["role"] == "user" }
  end

  it "is given to the message's request, kept, and recorded on the message by reference" do
    message = send_message("workbench_picture" => picture_data)
    picture = seen.last
    expect(picture).to be_a(Monadic::Workbench::Picture)
    expect(picture.request_id).to eq(message["request_id"])
    expect(message["workbench_picture"]).to eq(picture.reference)
    expect(JSON.generate(message)).not_to include(Base64.strict_encode64(png))
    expect(session[:parameters]).not_to have_key("workbench_picture")
    expect(Monadic::Workbench::Picture.read(chat_id, picture.id)).to eq(png)
  end

  it "is not taken for what the board does not have, and the message is sent all the same" do
    message = send_message("workbench_picture" => picture_data("version" => "w" * 64))
    expect(seen.last).to be_nil
    expect(message).not_to have_key("workbench_picture")
    expect(session[:parameters]).not_to have_key("workbench_picture")
  end

  it "is not taken in an app that makes images" do
    APPS["FakeApp"].define_singleton_method(:settings) { { "image_generation" => true } }
    send_message("workbench_picture" => picture_data)
    expect(seen.size).to eq(1)
    expect(seen.last).to be_nil
    APPS["FakeApp"].define_singleton_method(:settings) { {} }
    %w[ImageGeneratorOpenAI VideoGeneratorGemini].each do |name|
      APPS[name] = APPS["FakeApp"]
      session[:parameters]["app_name"] = name
      send_message("workbench_picture" => picture_data, "app_name" => name)
      expect(seen.last).to be_nil
    end
    expect(seen.size).to eq(3)
  end

  it "is not taken for a model known to take no images" do
    expect(Monadic::Utils::ModelSpec.get_model_property("command-a-03-2025", "vision_capability")).to be(false)
    send_message("workbench_picture" => picture_data, "model" => "command-a-03-2025")
    expect(seen.last).to be_nil
  end

  it "is sent back to the tab that asks for it, for a message of its chat only" do
    id = send_message("workbench_picture" => picture_data)["workbench_picture"]["id"]
    host.send(:handle_ws_workbench_picture, nil, { "picture_id" => id }, session)
    expect(sent.last).to include("type" => "workbench_picture", "picture_id" => id, "found" => true,
                                 "data" => "data:image/png;base64,#{Base64.strict_encode64(png)}")
    host.send(:handle_ws_workbench_picture, nil, { "picture_id" => "p_#{"b" * 20}" }, session)
    expect(sent.last).to include("found" => false)
    expect(sent.last).not_to have_key("data")
  end

  it "is removed with its message" do
    message = send_message("workbench_picture" => picture_data)
    id = message["workbench_picture"]["id"]
    host.handle_delete_message(nil, { "mid" => message["mid"] })
    expect(Monadic::Workbench::Picture.read(chat_id, id)).to be_nil
  end

  describe "with text selected" do
    def selection_data(overrides = {})
      { "item_id" => "i_1", "version" => "v" * 64, "page" => 2, "pages" => 4, "text" => "the eastern library" }
        .merge(overrides)
    end

    it "is given to the message's request, recorded on the message, kept with the history, never in the parameters" do
      message = send_message("workbench_selection" => selection_data)
      selection = selections.last
      expect(selection).to be_a(Monadic::Workbench::Selection)
      expect(selection.request_id).to eq(message["request_id"])
      expect(message["workbench_selection"]).to eq(selection.reference)
      expect(session[:parameters]).not_to have_key("workbench_selection")
      expect(Monadic::History::Serializer.send(:message, message)["workbench_selection"]).to eq(selection.reference)
    end

    it "is taken for a model that takes no images, and not for what the board does not have" do
      send_message("workbench_selection" => selection_data, "model" => "command-a-03-2025")
      expect(selections.last).to be_a(Monadic::Workbench::Selection)
      message = send_message("workbench_selection" => selection_data("version" => "w" * 64))
      expect(selections.last).to be_nil
      expect(message).not_to have_key("workbench_selection")
    end
  end

  it "is kept with the chat's history by reference" do
    message = send_message("workbench_picture" => picture_data)
    kept = Monadic::History::Serializer.send(:message, message)
    expect(kept["workbench_picture"]).to eq(message["workbench_picture"])
  end
end
