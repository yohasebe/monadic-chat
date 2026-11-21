# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/workspace"

# A reply is shown with the settings of its own message, also when the
# chat's settings changed between its end and its recording. The real
# streaming and HTML handlers; the provider call is played by a fake app.
RSpec.describe "The settings a reply is recorded with" do
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { [] }
  let(:queue) { Queue.new }
  let(:root) { Dir.mktmpdir }
  let(:session) do
    { parameters: { "app_name" => "FakeApp" }, messages: [], chat_id: Monadic::Workspace::Ids.generate(:chat),
      _ws_generation: 1 }
  end
  let(:seen) { [] }

  before do
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(root)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(root)
    allow(Monadic::History).to receive(:enabled?).and_return(false)
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << JSON.parse(msg) }
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:detect_language).and_return("en")
    allow(host).to receive(:check_past_messages).and_wrap_original do |original, limits|
      seen << limits.slice("context_size", "max_input_tokens")
      original.call(limits)
    end
    Thread.current[:rack_session] = session
    Thread.current[:websocket_session_id] = "tab-1"
    WebSocketHelper.register_live_session("tab-1", session, 1)
    app = Object.new
    app.define_singleton_method(:api_request) do |_role, _session, &_block|
      [{ "choices" => [{ "message" => { "content" => "ANSWER", "reasoning_content" => "PONDERING" }, "finish_reason" => "stop" }] }]
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

  # The recorded reply of a message, the chat's settings changed (as the
  # page does) after the answer was made and before it is recorded.
  def reply_card(message, changed_meanwhile)
    thread = host.send(:handle_ws_streaming, nil, { "message" => "hello", "app_name" => "FakeApp" }.merge(message),
                       session, queue)
    wait_for_answer_made(thread)
    session[:parameters].merge!(changed_meanwhile)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    thread.join(5)
    broadcasts.reverse.find { |b| b["type"] == "html" }&.fetch("content")
  end

  it "leaves the thinking off the reply of a message sent with Show Thinking off" do
    card = reply_card({ "show_thinking" => false }, { "show_thinking" => true })
    expect(card["text"]).to eq("ANSWER")
    expect(card).not_to have_key("thinking")
  end

  it "keeps the thinking with the reply of a message sent with Show Thinking on" do
    card = reply_card({ "show_thinking" => true }, { "show_thinking" => false })
    expect(card["thinking"]).to eq("PONDERING")
  end

  it "counts the chat's messages with the limits the message was sent with" do
    reply_card({ "context_size" => "7", "max_input_tokens" => "5000" },
               { "context_size" => "2", "max_input_tokens" => "100" })
    expect(seen.last).to eq("context_size" => 7, "max_input_tokens" => 5000)
  end

  it "counts with the chat's limits as they were when the message came, where it names none or one" do
    session[:parameters].merge!("context_size" => "9", "max_input_tokens" => "4000")
    reply_card({}, { "context_size" => "2", "max_input_tokens" => "100" })
    expect(seen.last).to eq("context_size" => 9, "max_input_tokens" => 4000)

    reply_card({ "context_size" => "6" }, { "context_size" => "2", "max_input_tokens" => "50" })
    expect(seen.last).to eq("context_size" => 6, "max_input_tokens" => 100)
  end
end
