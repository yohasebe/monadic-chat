# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/workspace"

# The page is told when an answer starts running and, exactly once, how it
# ended: "done" when the answer is recorded in the chat, "no_reply" when it
# ends without one. The real streaming and HTML handlers; only the provider
# call is played by a fake app.
RSpec.describe "Reply state sent to the page" do
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { [] }
  let(:queue) { Queue.new }
  let(:session) { { parameters: {}, messages: [], chat_id: Monadic::Workspace::Ids.generate(:chat) } }

  def fake_app(responses: nil, &during)
    Object.new.tap do |app|
      app.define_singleton_method(:api_request) do |_role, _session, &block|
        block.call({ "type" => "fragment", "content" => "Hello" })
        during&.call
        responses || [{ "choices" => [{ "message" => { "content" => "FINAL" }, "finish_reason" => "stop" }] }]
      end
      app.define_singleton_method(:settings) { {} }
    end
  end

  before do
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << msg }
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:detect_language).and_return("en")
    Thread.current[:rack_session] = session
  end

  after { Thread.current[:rack_session] = nil }

  def start_turn(app)
    stub_const("APPS", { "FakeApp" => app })
    host.send(:handle_ws_streaming, nil, { "message" => "Hi", "app_name" => "FakeApp" }, session, queue)
  end

  def finish_turn(thread)
    host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
  end

  def states
    broadcasts.map { |m| JSON.parse(m) rescue nil }.compact.select { |m| m["type"] == "reply_state" }
  end

  def request_id
    session[:messages].find { |m| m["role"] == "user" }["request_id"]
  end

  it "says the answer is running, then done once it is recorded" do
    finish_turn(start_turn(fake_app))
    expect(states).to eq([{ "type" => "reply_state", "state" => "running", "request_id" => request_id },
                          { "type" => "reply_state", "state" => "finished", "outcome" => "done",
                            "request_id" => request_id }])
    expect(session[:messages].last["text"]).to eq("FINAL")
    expect(session[:messages].last).not_to have_key("_request_id")
  end

  it "ends with no_reply when the provider gives no answer" do
    start_turn(fake_app(responses: [])).join
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
  end

  it "ends with no_reply when the answer is an error" do
    start_turn(fake_app(responses: [{ "type" => "error", "content" => "boom" }])).join
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
  end

  it "ends with no_reply when the answer is stopped (Cancel, a closed connection)" do
    gate = Queue.new
    thread = start_turn(fake_app { gate.pop })
    sleep 0.05 until thread.status == "sleep"
    thread.kill
    thread.join
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
  end

  it "ends with no_reply once when the chat changes after the answer was queued" do
    thread = start_turn(fake_app)
    wait_for_answer_made(thread)
    session[:chat_id] = Monadic::Workspace::Ids.generate(:chat)
    finish_turn(thread)
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
  end

  it "ends with no_reply when Cancel or Reset drops an answer still waiting in the queue" do
    thread = start_turn(fake_app)
    wait_for_answer_made(thread)
    host.send(:stop_running_reply, thread, queue)
    expect(queue).to be_empty
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
  end

  it "ends once when the answer is stopped right away, before its thread ran" do
    10.times do
      broadcasts.clear
      thread = start_turn(fake_app)
      host.send(:stop_running_reply, thread, queue)
      thread.join
      finish_turn(nil)
      ends = states.select { |s| s["state"] == "finished" }
      expect(ends.size).to eq(1)
    end
  end

  it "ends once when Cancel stops the answer" do
    gate = Queue.new
    thread = start_turn(fake_app { gate.pop })
    host.send(:stop_reply_work, thread)
    thread.join
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
  end

  it "starts nothing, and marks the refusal, when the message is not accepted" do
    allow(host).to receive(:sts_session_capable?).and_return(true)
    expect(start_turn(fake_app)).to be_nil
    expect(states).to be_empty
    refusal = broadcasts.map { |m| JSON.parse(m) }.find { |m| m["type"] == "error" }
    expect(refusal["not_accepted"]).to be(true)
  end

  it "ends once for an answer of several parts" do
    two = [{ "choices" => [{ "message" => { "content" => "ONE" }, "finish_reason" => "stop" }] },
           { "choices" => [{ "message" => { "content" => "TWO" }, "finish_reason" => "stop" }] }]
    finish_turn(start_turn(fake_app(responses: two)))
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "done"]])
  end

  describe "AI User suggestion" do
    before do
      session[:messages] = [{ "role" => "user", "text" => "a" }, { "role" => "assistant", "text" => "b" }]
    end

    def ask(&during)
      allow(host).to receive(:process_ai_user) do
        during&.call
        { "type" => "ai_user", "content" => "next question" }
      end
      host.send(:handle_ws_ai_user_query, nil, { "contents" => { "request_id" => "q1", "params" => {} } }, session, nil)
    end

    it "is running while written and done once given, under an id of the server's own" do
      ask.join
      expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "done"]])
      ids = states.map { |s| s["request_id"] }.uniq
      expect(ids.size).to eq(1)
      expect(ids.first).to match(/\Aai_user:\h{16}\z/)
    end

    it "ends with no_reply when it is stopped" do
      gate = Queue.new
      thread = ask { gate.pop }
      sleep 0.05 until thread.status == "sleep"
      thread.kill
      thread.join
      expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
    end
  end

  it "ends with no_reply once when the chat changes while the answer runs" do
    finish_turn(start_turn(fake_app { session[:chat_id] = Monadic::Workspace::Ids.generate(:chat) }))
    expect(states.map { |s| [s["state"], s["outcome"]] }).to eq([["running", nil], ["finished", "no_reply"]])
  end
end
