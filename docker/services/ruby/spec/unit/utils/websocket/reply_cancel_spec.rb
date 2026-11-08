# frozen_string_literal: true

require "spec_helper"
require "json"
require "rack"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/workspace"
require_relative "../../../../lib/monadic/utils/reply_cancel_server"

# Stopping an answer: by HTTP (the token given to its connection) while the
# read loop waits for it, or by the WebSocket Cancel. Whatever stops it, the
# answer ends once, its worker gives that end unless the answer was taken
# to be recorded, and what stops it waits until it has ended. The real
# streaming and HTML handlers; the provider is played by a fake app whose
# steps the examples hold and release.
RSpec.describe "Stopping an answer" do
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { Queue.new }
  let(:queue) { Queue.new }
  let(:session) do
    { parameters: {}, messages: [], chat_id: Monadic::Workspace::Ids.generate(:chat), _ws_generation: 1 }
  end
  let(:tokens) { [] }

  before do
    WebSocketHelper::Replies.reset!
    allow(Monadic::History).to receive(:enabled?).and_return(false) if defined?(Monadic::History)
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << msg }
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:detect_language).and_return("en")
    allow(WebSocketHelper).to receive(:send_to_connection) do |tab, generation, json, chat_id:|
      tokens << JSON.parse(json).merge("tab" => tab, "generation" => generation, "chat" => chat_id)
      true
    end
    Thread.current[:rack_session] = session
    Thread.current[:websocket_session_id] = "tab-1"
  end

  after do
    Thread.current[:rack_session] = nil
    Thread.current[:websocket_session_id] = nil
  end

  # A provider call that says it began (began) and goes on when released.
  def held_app(began:, release:, responses: nil)
    Object.new.tap do |app|
      app.define_singleton_method(:api_request) do |_role, _session, &block|
        block.call({ "type" => "fragment", "content" => "Hello" })
        began << true
        release.pop
        responses || [{ "choices" => [{ "message" => { "content" => "FINAL" }, "finish_reason" => "stop" }] }]
      end
      app.define_singleton_method(:settings) { {} }
    end
  end

  def start_turn(app)
    stub_const("APPS", { "FakeApp" => app })
    host.send(:handle_ws_streaming, nil, { "message" => "Hi", "app_name" => "FakeApp" }, session, queue)
  end

  def sent
    list = []
    list << JSON.parse(broadcasts.pop) until broadcasts.empty?
    list
  end

  def ends(list)
    list.select { |m| m["type"] == "reply_state" && m["state"] == "finished" }.map { |m| m["outcome"] }
  end

  def http_cancel(token, env = {})
    app = Monadic::Utils::ReplyCancelServer.new(->(_env) { [200, {}, ["app"]] })
    app.call(Rack::MockRequest.env_for("/reply/cancel/#{token}", { method: "POST", "HTTP_SEC_FETCH_SITE" => "same-origin" }.merge(env)))
  end

  def assistant_texts
    session[:messages].select { |m| m["role"] == "assistant" }.map { |m| m["text"] }
  end

  describe "the token" do
    it "is given to the connection the answer runs for only, with the answer it stops" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      expect(tokens.size).to eq(1)
      expect(tokens.first).to include("type" => "reply_cancel", "tab" => "tab-1", "generation" => 1,
                                      "chat" => session[:chat_id], "request_id" => thread[:reply_request_id])
      expect(tokens.first["token"]).to match(WebSocketHelper::Replies::TOKEN)
      release << true
      wait_for_answer_made(thread)
      host.send(:handle_ws_html, nil, {}, session, thread, queue)
      expect(WebSocketHelper::Replies.by_token(tokens.first["token"])).to be_nil
    end

    it "is not given past the limit, and the answers that have one keep it" do
      stub_const("WebSocketHelper::Replies::TOKENS", 1)
      _first, first_token = WebSocketHelper::Replies.open(request_id: "r1", chat_id: "c", tab: "t", generation: 1)
      second, second_token = WebSocketHelper::Replies.open(request_id: "r2", chat_id: "c", tab: "t", generation: 1)
      expect(first_token).not_to be_nil
      expect(second_token).to be_nil
      expect(WebSocketHelper::Replies.find("r2")).to equal(second)
      expect(WebSocketHelper::Replies.by_token(first_token)).not_to be_nil
    end

    it "goes with the connection it was given to" do
      _handle, token = WebSocketHelper::Replies.open(request_id: "r1", chat_id: "c", tab: "t", generation: 1)
      WebSocketHelper::Replies.forget_tokens("t", 2)
      expect(WebSocketHelper::Replies.by_token(token)).not_to be_nil
      WebSocketHelper::Replies.forget_tokens("t", 1)
      expect(WebSocketHelper::Replies.by_token(token)).to be_nil
    end
  end

  describe "by HTTP" do
    it "stops an answer still being written: nothing is recorded, it ends once, and the HTML wait is over" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      html = Thread.new do
        Thread.current[:rack_session] = session
        host.send(:handle_ws_html, nil, {}, session, thread, queue)
      end
      status, = http_cancel(tokens.first["token"])
      expect(status).to eq(204)
      expect(html.join(5)).not_to be_nil
      expect(thread.join(5)).not_to be_nil
      expect(thread[:reply_handle]).to be_ended
      expect(assistant_texts).to be_empty
      expect(ends(sent)).to eq(["no_reply"])
    end

    it "stops an answer made and not yet taken, with no HTML, Cancel or close after it" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      release << true
      wait_for_answer_made(thread)
      http_cancel(tokens.first["token"])
      expect(thread.join(5)).not_to be_nil
      expect(ends(sent)).to eq(["no_reply"])
      expect(WebSocketHelper::Replies.by_token(tokens.first["token"])).to be_nil
      # What is left in the queue is not recorded when the HTML comes later.
      host.send(:handle_ws_html, nil, {}, session, thread, queue)
      expect(assistant_texts).to be_empty
      expect(ends(sent)).to eq([])
    end

    it "does not stop an answer already taken to be recorded" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      release << true
      wait_for_answer_made(thread)
      handle = thread[:reply_handle]
      expect(handle.take_for_saving).to be(true)
      expect(handle.cancel!).to eq([nil, []])
      expect(handle).not_to be_cancelled
    end

    it "answers the same not found for what it does not take" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      token = tokens.first["token"]
      expect(http_cancel(token, method: "GET").first).to eq(404)
      expect(http_cancel(token, "HTTP_SEC_FETCH_SITE" => "cross-site").first).to eq(404)
      expect(http_cancel(token, input: "x").first).to eq(404)
      expect(http_cancel(token, "HTTP_TRANSFER_ENCODING" => "chunked").first).to eq(404)
      expect(http_cancel("x" * 43).first).to eq(404)
      expect(http_cancel("short").first).to eq(404)
      expect(thread[:reply_handle]).not_to be_cancelled
      release << true
      wait_for_answer_made(thread)
      host.send(:handle_ws_html, nil, {}, session, thread, queue)
      expect(http_cancel(token).first).to eq(404)
    end

    it "passes on what is not its own" do
      app = Monadic::Utils::ReplyCancelServer.new(->(_env) { [200, {}, ["app"]] })
      expect(app.call(Rack::MockRequest.env_for("/reply/other", method: "POST")).first).to eq(200)
    end
  end

  describe "what an answer made" do
    it "is recorded whole when it is taken, and ends once" do
      two = [{ "choices" => [{ "message" => { "content" => "ONE" }, "finish_reason" => "stop" }] },
             { "choices" => [{ "message" => { "content" => "TWO" }, "finish_reason" => "stop" }] }]
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release, responses: two))
      release << true
      wait_for_answer_made(thread)
      expect(queue.size).to eq(1)
      host.send(:handle_ws_html, nil, {}, session, thread, queue)
      expect(assistant_texts).to eq(%w[ONE TWO])
      expect(ends(sent)).to eq(["done"])
      expect(thread.join(5)).not_to be_nil
    end

    it "lets its worker go when it was recorded and ended before the worker came to wait" do
      handle = WebSocketHelper::ReplyHandle.new(request_id: "r", chat_id: "c", tab: "t", generation: 1)
      handle.attach(Thread.current)
      handle.begin!
      handle.answer! { nil }
      expect(handle.take_for_saving).to be(true)
      handle.end!
      waiter = Thread.new { handle.await_handoff }
      expect(waiter.join(2)).not_to be_nil
    end

    it "puts nothing in the queue when there is nothing, and ends without an answer" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release, responses: []))
      release << true
      expect(thread.join(5)).not_to be_nil
      expect(queue).to be_empty
      expect(ends(sent)).to eq(["no_reply"])
    end

    it "is put in the queue all or not at all against a Cancel" do
      handle = WebSocketHelper::ReplyHandle.new(request_id: "r", chat_id: "c", tab: "t", generation: 1)
      handle.attach(Thread.current)
      expect(handle.begin!).to be(true)
      handle.cancel!
      put = false
      expect(handle.answer! { put = true }).to be(false)
      expect(put).to be(false)
    end
  end

  describe "an answer that could not be recorded" do
    # A response the HTML handler fails on while recording it.
    let(:broken) { { "choices" => [{ "message" => { "content" => "BAD" }, "finish_reason" => "stop" }] } }
    let(:good) { { "choices" => [{ "message" => { "content" => "GOOD" }, "finish_reason" => "stop" }] } }

    before do
      allow(host).to receive(:detect_language) do |text|
        raise ArgumentError, "not recorded" if text.include?("BAD")

        "en"
      end
    end

    def made(responses)
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release, responses: responses))
      release << true
      wait_for_answer_made(thread)
      thread
    end

    it "ends once without an answer when none of it could be recorded" do
      thread = made([broken, broken])
      host.send(:handle_ws_html, nil, {}, session, thread, queue)
      expect(assistant_texts).to eq([])
      expect(ends(sent)).to eq(["no_reply"])
      expect(thread.join(5)).not_to be_nil
      expect(WebSocketHelper::Replies.find(thread[:reply_request_id])).to be_nil
    end

    it "ends once as answered when part of it was recorded" do
      thread = made([broken, good])
      host.send(:handle_ws_html, nil, {}, session, thread, queue)
      expect(assistant_texts).to eq(["GOOD"])
      expect(ends(sent)).to eq(["done"])
      expect(thread.join(5)).not_to be_nil
    end

    it "ends once even when an error leaves the HTML handler" do
      thread = made([broken])
      allow(host).to receive(:send_error).and_raise(IOError, "connection gone")
      expect { host.send(:handle_ws_html, nil, {}, session, thread, queue) }.to raise_error(IOError)
      expect(ends(sent)).to eq(["no_reply"])
      expect(thread.join(5)).not_to be_nil
      expect(WebSocketHelper::Replies.find(thread[:reply_request_id])).to be_nil
    end
  end

  describe "a Cancel against the steps that cannot be split" do
    let(:handle) { WebSocketHelper::ReplyHandle.new(request_id: "r", chat_id: "c", tab: "t", generation: 1) }
    let(:worker) { Thread.new { sleep } }

    before do
      handle.attach(worker)
      handle.begin!
    end

    after { worker.kill }

    it "waits while the answer is put in the queue, and then does not stop the worker that put it" do
      inside = Queue.new
      go_on = Queue.new
      putting = Thread.new do
        handle.answer! do
          inside << true
          go_on.pop
        end
      end
      inside.pop
      cancelling = Thread.new { handle.cancel! }
      expect(cancelling.join(0.2)).to be_nil
      go_on << true
      expect(putting.value).to be(true)
      thread, = cancelling.value
      expect(thread).to be_nil
      expect(handle.cancelled?).to be(true)
      expect(handle.take_for_saving).to be(false)
    end

    it "puts nothing in the queue once cancelled first" do
      thread, = handle.cancel!
      expect(thread).to be(worker)
      put = false
      expect(handle.answer! { put = true }).to be(false)
      expect(put).to be(false)
    end

    it "does not cancel an answer taken to be recorded, and an answer cancelled is not taken" do
      handle.answer! { nil }
      expect(handle.take_for_saving).to be(true)
      expect(handle.cancel!).to eq([nil, []])
      expect(handle.cancelled?).to be(false)

      other = WebSocketHelper::ReplyHandle.new(request_id: "s", chat_id: "c", tab: "t", generation: 1)
      other.attach(worker)
      other.begin!
      other.answer! { nil }
      other.cancel!
      expect(other.take_for_saving).to be(false)
    end
  end

  describe "an answer cancelled before its worker began" do
    it "does nothing and ends once" do
      handle = WebSocketHelper::ReplyHandle.new(request_id: "r", chat_id: "c", tab: "t", generation: 1)
      handle.cancel!
      handle.attach(Thread.current)
      expect(handle.begin!).to be(false)
      expect(handle.worker_owns_end!).to be(true)
    end

    it "is ended by its worker, never begun, when an error came before the worker was attached" do
      handles = []
      workers = []
      allow(WebSocketHelper::ReplyHandle).to receive(:new).and_wrap_original do |make, **args|
        make.call(**args).tap do |made|
          handles << made
          tries = 0
          allow(made).to receive(:attach).and_wrap_original do |attach, thread|
            workers << thread
            tries += 1
            raise IOError, "connection gone" if tries == 1

            attach.call(thread)
          end
        end
      end
      began = Queue.new
      expect { start_turn(held_app(began: began, release: Queue.new)) }.to raise_error(IOError)
      handle = handles.first
      expect(workers.first.join(5)).not_to be_nil
      expect(handle.ended?).to be(true)
      expect(handle.cancelled?).to be(true)
      expect(began).to be_empty
      expect(ends(sent)).to eq(["no_reply"])
      expect(WebSocketHelper::Replies.find(handle.request_id)).to be_nil
      token = tokens.find { |t| t["request_id"] == handle.request_id }["token"]
      expect(WebSocketHelper::Replies.by_token(token)).to be_nil
    end

    it "is ended where it was made when its worker could not be made" do
      allow(Thread).to receive(:new).and_raise(ThreadError, "no thread")
      began = Queue.new
      release = Queue.new
      expect { start_turn(held_app(began: began, release: release)) }.to raise_error(ThreadError)
      expect(ends(sent)).to eq(["no_reply"])
      request_id = session[:messages].find { |m| m["role"] == "user" }["request_id"]
      expect(WebSocketHelper::Replies.find(request_id)).to be_nil
    end
  end

  describe "by the WebSocket Cancel" do
    it "waits until the answer ended, past the time it notes" do
      stub_const("WebSocketHelper::REPLY_STOP_WAIT", 0.05)
      notes = []
      allow(Monadic::Utils::ExtraLogger).to receive(:log) { |&b| notes << b.call }
      handle = WebSocketHelper::ReplyHandle.new(request_id: "r", chat_id: "c", tab: "t", generation: 1)
      # A worker whose own end is held: stopped, it ends only when let go.
      worker = Thread.new do
        handle.begin!
        sleep
      ensure
        Thread.handle_interrupt(Object => :never) { sleep 0.01 until Thread.current[:let_go] }
      end
      handle.attach(worker)
      sleep 0.01 until handle.phase == :running
      stopped = Thread.new { WebSocketHelper::Replies.stop_and_settle(handle) }
      sleep 0.2
      expect(stopped).to be_alive
      worker[:let_go] = true
      worker.join(5)
      handle.end!
      expect(stopped.join(5)).not_to be_nil
      expect(notes.grep(/still stopping/).size).to eq(1)
      expect(notes.grep(/ended after a stop/).size).to eq(1)
      expect(notes.join).not_to include("token")
    end

    it "stops the answer still being written and records nothing" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      host.send(:stop_reply_work, thread)
      expect(thread).not_to be_alive
      expect(thread[:reply_handle]).to be_ended
      expect(ends(sent)).to eq(["no_reply"])
    end

    it "drops an answer made and not yet taken, waiting for its worker to end it" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      release << true
      wait_for_answer_made(thread)
      host.send(:stop_running_reply, thread, queue)
      expect(queue).to be_empty
      expect(thread).not_to be_alive
      expect(ends(sent)).to eq(["no_reply"])
    end

    it "lets a message sent after it start a new answer" do
      began = Queue.new
      release = Queue.new
      first = start_turn(held_app(began: began, release: release))
      began.pop
      host.send(:stop_reply_work, first)
      sent
      second = start_turn(held_app(began: began, release: release))
      began.pop
      expect(host.send(:reply_busy?, second)).to be(true)
      release << true
      wait_for_answer_made(second)
      expect(host.send(:reply_busy?, second)).to be(false)
      host.send(:handle_ws_html, nil, {}, session, second, queue)
      expect(assistant_texts).to eq(["FINAL"])
    end
  end

  describe "what waits for an answer" do
    it "a suggestion is not written for an answer that was cancelled" do
      session[:messages] = [{ "role" => "user", "text" => "a" }, { "role" => "assistant", "text" => "b" }]
      allow(host).to receive(:process_ai_user).and_return({ "type" => "ai_user", "content" => "next" })
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      suggestion = host.send(:handle_ws_ai_user_query, nil, { "contents" => { "request_id" => "q1", "params" => {} } },
                             session, thread)
      http_cancel(tokens.first["token"])
      expect(suggestion.join(5)).not_to be_nil
      expect(sent.map { |m| m["type"] }).not_to include("ai_user")
      expect(host).not_to have_received(:process_ai_user)
    end

    it "Play waits for the answer and leaves it for the HTML to record" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      allow(host).to receive(:start_tts_playback)
      allow(host).to receive(:privacy_sanitize_tts_text) { |text, *_| text }
      play = Thread.new { host.send(:handle_ws_play_tts, nil, { "text" => "x", "tts_provider" => "webspeech" }, session, thread) }
      release << true
      expect(play.join(5)).not_to be_nil
      host.send(:handle_ws_html, nil, {}, session, thread, queue)
      expect(assistant_texts).to eq(["FINAL"])
      expect(ends(sent)).to eq(["done"])
    end
  end

  describe "speech for an answer" do
    let(:handle) { WebSocketHelper::ReplyHandle.new(request_id: "r", chat_id: "c", tab: "t", generation: 1) }

    it "is not started once the answer was cancelled" do
      handle.cancel!
      spoken = false
      host.send(:start_reply_speech, handle) { spoken = true }
      sleep 0.05
      expect(spoken).to be(false)
    end

    it "names the answer it is for, so the page can drop what comes for one it stopped" do
      began = Queue.new
      release = Queue.new
      stub_const("APPS", { "FakeApp" => held_app(began: began, release: release) })
      obj = { "message" => "Hi", "app_name" => "FakeApp", "auto_speech" => true, "tts_provider" => "webspeech" }
      # As the app holds it (a number), whatever the config file says.
      allow(CONFIG).to receive(:[]).and_call_original
      allow(CONFIG).to receive(:[]).with("AUTO_TTS_MAX_BYTES").and_return(400)
      thread = host.send(:handle_ws_streaming, nil, obj, session, queue)
      release << true
      frames = []
      Timeout.timeout(5) do
        frames << JSON.parse(broadcasts.pop) until frames.any? { |f| f["type"] == "tts_complete" }
      end
      request_id = frames.find { |f| f["type"] == "reply_state" && f["state"] == "running" }["request_id"]
      speech = frames.select { |f| %w[web_speech tts_complete].include?(f["type"]) }
      expect(speech.map { |f| f["type"] }).to eq(%w[web_speech tts_complete])
      expect(speech.map { |f| f["reply_speech"] }).to all(eq(request_id))
      WebSocketHelper::Replies.cancel(WebSocketHelper::Replies.find(request_id))
      expect(thread.join(5)).not_to be_nil
    end

    it "played by hand names no answer" do
      host.send(:start_tts_playback, text: "Hello there.", provider: "webspeech", voice: nil, speed: 1,
                                     response_format: "mp3", language: "en", manual_play: true, ws_session_id: "tab-1")
      frames = sent
      expect(frames.map { |f| f["type"] }).to include("web_speech", "tts_complete")
      expect(frames).to all(satisfy { |f| !f.key?("reply_speech") })
    end

    it "made after the stop, while its start was held up, is stopped, and the stop does not wait for it" do
      WebSocketHelper::Replies.instance_variable_get(:@handles)["r"] = handle
      token = "B" * 43
      WebSocketHelper::Replies.instance_variable_get(:@tokens)[token] = handle
      starter_holds = Queue.new
      go_on = Queue.new
      made = Queue.new
      host.send(:start_reply_speech, handle) do
        starter_holds << true
        go_on.pop
        Thread.new { sleep }.tap { |speech| made << speech }
      end
      starter_holds.pop
      status, = http_cancel(token)
      expect(status).to eq(204)
      go_on << true
      expect(made.pop.join(5)).not_to be_nil
    end

    it "made before the stop is stopped by it, with its prefetches" do
      speech = nil
      prefetch = nil
      starter = nil
      host.send(:start_reply_speech, handle) do
        starter = Thread.current
        prefetch = Thread.new { sleep }
        speech = Thread.new { sleep }.tap { |t| t[:tts_futures] = [prefetch] }
      end
      Timeout.timeout(5) { sleep 0.01 until starter && !starter.alive? }
      WebSocketHelper::Replies.cancel(handle)
      expect(speech.join(5)).not_to be_nil
      expect(prefetch.join(5)).not_to be_nil
    end
  end

  # A stopped reply's message is marked for the model (StoppedReplies): the
  # stop is noted as it takes, before the worker has ended, so a new
  # connection of the tab that builds the next request finds it.
  describe "the message of a stopped reply" do
    let(:stopped) { Monadic::Workspace::StoppedReplies }

    before { stopped.reset! }

    def user_turn(of = session)
      of[:messages].find { |m| m["role"] == "user" }
    end

    it "is noted when Cancel takes, before the worker ends, and a new connection's copy is marked from it" do
      began = Queue.new
      release = Queue.new
      in_ensure = Queue.new
      go_on = Queue.new
      allow(host).to receive(:mark_stopped_turn) do
        in_ensure << true
        go_on.pop
      end
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      # The copy a new connection of the tab restores: the message unmarked.
      restored = Marshal.load(Marshal.dump(session.except(:messages))).merge(messages: Marshal.load(Marshal.dump(session[:messages])))
      request_id = thread[:reply_request_id]
      WebSocketHelper::Replies.cancel(thread[:reply_handle])
      in_ensure.pop
      # The worker is held before marking and before its end.
      expect(stopped.recorded?(session[:chat_id], request_id)).to be(true)
      expect(thread[:reply_handle]).not_to be_ended
      expect(stopped.apply!(restored)).to be(true)
      expect(user_turn(restored)["reply_stopped"]).to be(true)
      go_on << true
      expect(thread.join(5)).not_to be_nil
      expect(ends(sent)).to eq(["no_reply"])
    end

    it "is marked in the connection's own chat when the worker ends" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      status, = http_cancel(tokens.first["token"])
      expect(status).to eq(204)
      expect(thread.join(5)).not_to be_nil
      expect(user_turn["reply_stopped"]).to be(true)
      expect(user_turn["text"]).to eq("Hi")
    end

    it "still ends the reply when marking fails" do
      began = Queue.new
      release = Queue.new
      allow(host).to receive(:mark_stopped_turn).and_raise(IOError, "state not saved")
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      WebSocketHelper::Replies.cancel(thread[:reply_handle])
      expect(thread.join(5)).not_to be_nil
      expect(thread[:reply_handle]).to be_ended
      expect(ends(sent)).to eq(["no_reply"])
      expect(stopped.recorded?(session[:chat_id], thread[:reply_request_id])).to be(true)
    end

    it "is not marked when the reply ends with an error" do
      app = Object.new.tap do |a|
        a.define_singleton_method(:api_request) { |*_| raise IOError, "provider down" }
        a.define_singleton_method(:settings) { {} }
      end
      allow(host).to receive(:send_error)
      thread = start_turn(app)
      thread.report_on_exception = false if thread
      begin
        thread&.join(5)
      rescue IOError
        nil
      end
      expect(user_turn).not_to have_key("reply_stopped")
      expect(stopped.recorded?(session[:chat_id], thread && thread[:reply_request_id])).to be(false)
    end

    # A provider call that keeps what the conversation was when it was made.
    def seeing_app(seen, also: nil)
      Object.new.tap do |app|
        app.define_singleton_method(:api_request) do |_role, sess, &_block|
          seen << Marshal.load(Marshal.dump(sess[:messages]))
          also&.call(sess)
          [{ "choices" => [{ "message" => { "content" => "OK" }, "finish_reason" => "stop" }] }]
        end
        app.define_singleton_method(:settings) { {} }
      end
    end

    # A whole turn on sess: its answer made and recorded.
    def turn_on(sess, app, text)
      stub_const("APPS", { "FakeApp" => app })
      Thread.current[:rack_session] = sess
      thread = host.send(:handle_ws_streaming, nil, { "message" => text, "app_name" => "FakeApp" }, sess, queue)
      wait_for_answer_made(thread)
      host.send(:handle_ws_html, nil, {}, sess, thread, queue)
      thread.join(5)
    end

    it "is marked for the next request of a new connection before the provider is called" do
      began = Queue.new
      release = Queue.new
      allow(host).to receive(:mark_stopped_turn)
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      restored = session.except(:messages).merge(messages: Marshal.load(Marshal.dump(session[:messages])), _ws_generation: 2)
      WebSocketHelper::Replies.cancel(thread[:reply_handle])
      thread.join(5)
      seen = []
      turn_on(restored, seeing_app(seen), "Hello")
      stopped_turn, current = seen.first.select { |m| m["role"] == "user" }
      expect(stopped_turn).to include("text" => "Hi", "reply_stopped" => true)
      expect(current).to include("text" => "Hello")
      expect(current).not_to have_key("reply_stopped")
    end

    it "reaches the request after when the stop is noted only after the next one began, and drops its compaction" do
      seen = []
      turn_on(session, seeing_app(seen), "Hi")
      stopped_id = user_turn["request_id"]
      # The next request (B) is built and compacts what it has, before the
      # stop of the first is noted.
      turn_on(session, seeing_app(seen, also: ->(sess) { sess[:grok_compaction] = { "blob" => {} } }), "Hello")
      stopped.record(session[:chat_id], stopped_id)
      turn_on(session, seeing_app(seen), "Again")
      expect(seen[1].find { |m| m["request_id"] == stopped_id }).not_to have_key("reply_stopped")
      expect(seen[2].find { |m| m["request_id"] == stopped_id }).to include("reply_stopped" => true)
      expect(session).not_to have_key(:grok_compaction)
    end

    it "is not marked when Cancel comes after the answer was taken to be recorded" do
      began = Queue.new
      release = Queue.new
      thread = start_turn(held_app(began: began, release: release))
      began.pop
      release << true
      wait_for_answer_made(thread)
      handle = thread[:reply_handle]
      expect(handle.take_for_saving).to be(true)
      WebSocketHelper::Replies.cancel(handle)
      expect(stopped.recorded?(session[:chat_id], handle.request_id)).to be(false)
      expect(user_turn).not_to have_key("reply_stopped")
    end
  end
end
