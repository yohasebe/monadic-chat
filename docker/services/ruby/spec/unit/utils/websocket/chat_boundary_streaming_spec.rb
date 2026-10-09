# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/workspace"

# A turn that is still running when the user Resets (or switches apps)
# belongs to the chat it started in. What it produces afterwards must not be
# delivered into the new chat or recorded in it. The real streaming handler;
# only the provider call is played by a fake app.
RSpec.describe "Streaming across a chat change" do
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { [] }
  let(:queue) { Queue.new }
  let(:old_chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { parameters: {}, messages: [], chat_id: old_chat } }

  def fake_app(&during)
    Object.new.tap do |app|
      app.define_singleton_method(:api_request) do |_role, _session, &block|
        block.call({ "type" => "fragment", "content" => "BEFORE" })
        during&.call
        block.call({ "type" => "fragment", "content" => "AFTER" })
        [{ "choices" => [{ "message" => { "content" => "FINAL" }, "finish_reason" => "stop" }] }]
      end
      app.define_singleton_method(:settings) { {} }
    end
  end

  def run_turn(app)
    stub_const("APPS", { "FakeApp" => app })
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << msg }
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    thread = host.send(:handle_ws_streaming, nil, { "message" => "describe the video", "app_name" => "FakeApp" }, session, queue)
    thread&.join
  end

  it "drops what arrives after a Reset, records nothing, and still ends the turn on the page" do
    run_turn(fake_app { session[:chat_id] = Monadic::Workspace::Ids.generate(:chat) })

    sent = broadcasts.join("\n")
    expect(sent).to include("BEFORE")
    expect(sent).not_to include("AFTER")
    expect(queue).to be_empty
    expect(JSON.parse(broadcasts.last)["type"]).to eq("streaming_complete")
  end

  it "delivers a turn whose chat did not change" do
    run_turn(fake_app)
    sent = broadcasts.join("\n")
    expect(sent).to include("BEFORE", "AFTER")
    expect(queue.size).to eq(1)
  end
end
