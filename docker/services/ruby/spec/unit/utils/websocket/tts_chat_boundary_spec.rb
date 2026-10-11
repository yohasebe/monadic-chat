# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/workspace"

# Speech made for a chat must not play in the next one: audio that comes back
# after a Reset is dropped, and Reset stops speech still being made. The real
# TTS handler; only the provider call is played, held until the test releases it.
RSpec.describe "Speech across a chat change" do
  let(:session) { { parameters: {}, messages: [], chat_id: Monadic::Workspace::Ids.generate(:chat) } }
  let(:sent) { [] }
  let(:release) { Queue.new }
  let(:host) do
    s = session
    Class.new { include WebSocketHelper }.new.tap do |h|
      h.define_singleton_method(:session) { s }
    end
  end

  before do
    allow(host).to receive(:tts_api_request) do |*_args, **_kw|
      release.pop
      { "type" => "audio", "content" => "QUFB" }
    end
    allow(host).to receive(:send_or_broadcast) { |msg, *_| sent << JSON.parse(msg)["type"] }
    allow(WebSocketHelper).to receive(:send_audio_to_session) { |msg, *_| sent << JSON.parse(msg)["type"] }
  end

  def speak
    host.start_single_tts_request(text: "hello", provider: "openai-tts-4o", voice: "alloy", speed: 1.0,
                                  response_format: "mp3", language: "en", ws_session_id: "tab-1")
    host.instance_variable_get(:@tts_thread)
  end

  it "plays the audio when the chat stays the same" do
    thread = speak
    release << true
    thread.join(5)
    expect(sent).to include("audio")
  end

  it "drops audio that comes back after the chat changed" do
    thread = speak
    session[:chat_id] = Monadic::Workspace::Ids.generate(:chat)
    release << true
    thread.join(5)
    expect(sent).not_to include("audio", "tts_complete")
  end

  it "stops speech still being made when the chat is reset" do
    thread = speak
    host.send(:handle_ws_reset, session)
    thread.join(5)
    expect(thread.alive?).to be(false)
    expect(sent).not_to include("audio")
    expect(sent).to include("cancel") # the page's indicator does not stay on
  end

  describe "an AI User suggestion" do
    before { session[:messages] = [{ "role" => "user", "text" => "hi" }, { "role" => "assistant", "text" => "hello" }] }

    def suggest(during: nil)
      allow(host).to receive(:process_ai_user) do |*_args|
        during&.call
        { "type" => "text", "content" => "Next question?" }
      end
      host.send(:handle_ws_ai_user_query, nil, { "contents" => { "request_id" => "aiu_1" } }, session, nil)
    end

    it "goes into the input box when the chat stays the same, naming the request it answers" do
      notices = []
      allow(host).to receive(:send_or_broadcast) { |msg, *_| notices << JSON.parse(msg) }
      suggest.join(5)
      expect(notices.map { |n| n["type"] }).to include("ai_user", "ai_user_finished")
      expect(notices.map { |n| n["request_id"] }.uniq).to eq(["aiu_1"])
    end

    it "does not reach the next chat's input box after a Reset" do
      suggest(during: -> { session[:chat_id] = Monadic::Workspace::Ids.generate(:chat) }).join(5)
      expect(sent).not_to include("ai_user", "ai_user_finished")
    end

    it "refuses a second request while one is being written, naming the request, without waiting" do
      notices = []
      allow(host).to receive(:send_or_broadcast) { |msg, *_| notices << JSON.parse(msg) }
      writing = Thread.new { sleep 5 }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      second = host.send(:handle_ws_ai_user_query, nil, { "contents" => { "request_id" => "aiu_3" } }, session, nil, writing)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.5
      expect(second).to be_nil
      expect(notices).to eq([{ "type" => "ai_user_error", "content" => "ai_user_busy", "request_id" => "aiu_3" }])
    ensure
      writing&.kill
    end

    it "does not hold the read loop while a reply is still being written" do
      reply = Thread.new { sleep 5 }
      allow(host).to receive(:process_ai_user).and_return({ "type" => "text", "content" => "Next?" })
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      writing = host.send(:handle_ws_ai_user_query, nil, { "contents" => { "request_id" => "aiu_4" } }, session, reply)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.5
      expect(writing).to be_alive # waiting for the reply, in its own thread
      expect(sent).not_to include("ai_user_started")
    ensure
      writing&.kill
      reply&.kill
    end

    it "reports a failure as the request's own error, not as a general one" do
      notices = []
      allow(host).to receive(:send_or_broadcast) { |msg, *_| notices << JSON.parse(msg) }
      allow(host).to receive(:process_ai_user).and_return({ "type" => "error", "content" => "AI User error: quota" })
      host.send(:handle_ws_ai_user_query, nil, { "contents" => { "request_id" => "aiu_5" } }, session, nil).join(5)
      expect(notices.last).to eq("type" => "ai_user_error", "content" => "AI User error: quota", "request_id" => "aiu_5")
      expect(notices.map { |n| n["type"] }).not_to include("error", "wait")
    end

    # The read loop takes RESET only after the handler returns: the handler
    # hands back the thread writing the suggestion, which Reset then stops.
    it "is written in a thread of its own, which a Reset stops before it is done" do
      started = Queue.new
      allow(host).to receive(:process_ai_user) do |*_args|
        started << true
        sleep 5
        { "type" => "text", "content" => "Old suggestion" }
      end
      writing = host.send(:handle_ws_ai_user_query, nil, { "contents" => { "request_id" => "aiu_2" } }, session, nil)
      started.pop
      host.send(:stop_running_reply, writing, Queue.new)
      host.send(:handle_ws_reset, session)
      expect(writing).not_to be_alive
      expect(sent).not_to include("ai_user", "ai_user_finished")
      expect(sent).to include("cancel")
    end
  end

  describe "a reply still being written at Reset" do
    it "is stopped, so its tool cannot write its result into the next chat's session" do
      reached = Queue.new
      reply = Thread.new do
        reached << true
        sleep 0.5 # an image being generated
        session[:grok_last_image] = "old_chat_image.png"
      end
      reached.pop
      queue = Queue.new
      queue << { "_chat_id" => session[:chat_id] }

      host.send(:stop_running_reply, reply, queue)
      host.send(:handle_ws_reset, session)
      sleep 0.8

      expect(reply).not_to be_alive
      expect(session).not_to have_key(:grok_last_image)
      expect(queue).to be_empty
      expect(sent).to include("cancel")
    end

    it "sends nothing when no reply is running" do
      host.send(:stop_running_reply, nil, Queue.new)
      expect(sent).to be_empty
    end
  end
end
