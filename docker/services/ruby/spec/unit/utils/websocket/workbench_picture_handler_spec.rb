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
  let(:item) { { id: "i_1", kind: "file", preview: "pdf", version: "v" * 64, place: "current", name: "plan.pdf" } }
  let(:items) { [item] }
  let(:seen) { [] }
  let(:selections) { [] }

  before do
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(root)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(root)
    allow(Monadic::History).to receive(:enabled?).and_return(false)
    allow(Monadic::Workbench::Board).to receive(:existing).and_call_original
    allow(Monadic::Workbench::Board).to receive(:existing).with(chat_id)
                                                         .and_return(double("board", observe: { items: items, selected: "i_1" }, begin_reply: nil))
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
      seen_now << Monadic::Workspace::RequestContext.current&.pictures&.first
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
    expect(message["workbench_pictures"]).to eq([picture.reference])
    expect(JSON.generate(message)).not_to include(Base64.strict_encode64(png))
    expect(session[:parameters]).not_to have_key("workbench_picture")
    expect(Monadic::Workbench::Picture.read(chat_id, picture.id)).to eq(png)
  end

  it "is not taken for what the board does not have, and the message is sent all the same" do
    message = send_message("workbench_picture" => picture_data("version" => "w" * 64))
    expect(seen.last).to be_nil
    expect(message).not_to have_key("workbench_pictures")
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

  it "is taken unmarked only for a model that takes images and no tools, which cannot look at the work screen itself" do
    plain = picture_data.except("mark").merge("unmarked" => true)
    send_message("workbench_picture" => plain)
    expect(seen.last).to be_nil
    expect(Monadic::Utils::ModelSpec.tool_capability?("command-a-vision-07-2025")).to be(false)
    APPS["FakeApp"].define_singleton_method(:settings) { { "provider" => "cohere" } }
    message = send_message("workbench_picture" => plain, "model" => "command-a-vision-07-2025")
    expect(seen.last).to be_a(Monadic::Workbench::Picture)
    expect(message["workbench_pictures"].first).to include("unmarked" => true)
    expect(seen.last.note).to start_with("The image attached to this message is the part of page 2")
  ensure
    APPS["FakeApp"].define_singleton_method(:settings) { {} }
  end

  it "is sent back to the tab that asks for it, for a message of its chat only" do
    id = send_message("workbench_picture" => picture_data)["workbench_pictures"].first["id"]
    host.send(:handle_ws_workbench_picture, nil, { "picture_id" => id }, session)
    expect(sent.last).to include("type" => "workbench_picture", "picture_id" => id, "found" => true,
                                 "data" => "data:image/png;base64,#{Base64.strict_encode64(png)}")
    host.send(:handle_ws_workbench_picture, nil, { "picture_id" => "p_#{"b" * 20}" }, session)
    expect(sent.last).to include("found" => false)
    expect(sent.last).not_to have_key("data")
  end

  it "is removed with its message" do
    message = send_message("workbench_picture" => picture_data)
    id = message["workbench_pictures"].first["id"]
    host.handle_delete_message(nil, { "mid" => message["mid"] })
    expect(Monadic::Workbench::Picture.read(chat_id, id)).to be_nil
  end

  describe "of several marked items" do
    let(:image) { { id: "i_2", kind: "file", preview: "image", version: "x" * 64, place: "latest", name: "cat.png" } }
    let(:items) { [item, image, { id: "i_3", kind: "file", preview: "image", version: "y" * 64, place: "stash", name: "old.png" },
                   { id: "i_4", kind: "file", preview: "image", version: "z" * 64, place: "previous", name: "before.png" }] }
    let(:all_seen) { [] }

    def marked(id, version, extra = {})
      { "item_id" => id, "version" => version, "mark_id" => "m_#{id.delete('_')}aaaa", "mark_rev" => 2,
        "mark" => { "shape" => "ellipse", "color" => "magenta", "x" => 0.2, "y" => 0.2, "w" => 0.1, "h" => 0.1 },
        "image" => Base64.strict_encode64(png) }.merge(extra)
    end

    before do
      everything = all_seen
      APPS["FakeApp"].define_singleton_method(:api_request) do |_role, _session, &_block|
        everything << Monadic::Workspace::RequestContext.current&.pictures
        [{ "choices" => [{ "message" => { "content" => "ANSWER" }, "finish_reason" => "stop" }] }]
      end
    end

    it "takes one per marked item on the desk, in order, each saying which item and page it is" do
      message = send_message("workbench_pictures" => [marked("i_1", "v" * 64, "page" => 3, "pages" => 9), marked("i_2", "x" * 64)])
      pictures = all_seen.last
      expect(pictures.map(&:item_id)).to eq(%w[i_1 i_2])
      expect(pictures.first.note).to start_with('Work screen picture 1 attached to this message is page 3 of the PDF "plan.pdf"')
      expect(pictures.last.note).to start_with('Work screen picture 2 attached to this message is the image "cat.png"')
      expect(message["workbench_pictures"].map { |ref| ref.slice("item_id", "mark_id", "mark_rev") })
        .to eq([{ "item_id" => "i_1", "mark_id" => "m_i1aaaa", "mark_rev" => 2 },
                { "item_id" => "i_2", "mark_id" => "m_i2aaaa", "mark_rev" => 2 }])
      pictures.each { |picture| expect(Monadic::Workbench::Picture.read(chat_id, picture.id)).to eq(png) }
    end

    it "takes none when one is put away, Before, of another version, twice, or past the most a message takes" do
      [[marked("i_1", "v" * 64, "page" => 1, "pages" => 2), marked("i_3", "y" * 64)],
       [marked("i_4", "z" * 64)],
       [marked("i_2", "w" * 64)],
       [marked("i_2", "x" * 64), marked("i_2", "x" * 64)],
       Array.new(Monadic::Workbench::Picture::PER_MESSAGE + 1) { marked("i_2", "x" * 64) }].each do |list|
        message = send_message("workbench_pictures" => list)
        expect(all_seen.last).to eq([])
        expect(message).not_to have_key("workbench_pictures")
      end
      expect(Dir.glob(File.join(root, "**", "p_*.png"))).to be_empty
    end

    it "keeps none when the message is not accepted" do
      allow(host).to receive(:sts_session_capable?).and_return(true)
      host.send(:handle_ws_streaming, nil, { "message" => "hi", "app_name" => "FakeApp",
                                             "workbench_pictures" => [marked("i_2", "x" * 64)] }, session, queue)
      expect(Dir.glob(File.join(root, "**", "p_*.png"))).to be_empty
    end
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
    expect(kept["workbench_pictures"]).to eq(message["workbench_pictures"])
  end
end
