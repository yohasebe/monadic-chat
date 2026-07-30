# frozen_string_literal: true

require 'spec_helper'
require 'async'
require 'async/queue'
require 'async/condition'
require 'async/semaphore'
require 'json'
require 'monadic/utils/extra_logger'
require 'monadic/utils/model_spec'
require_relative '../../../../lib/monadic/utils/websocket'
require 'monadic/utils/websocket/sts_stream_handler'

# Unit tests for the speech-to-speech (STS) bridge in WebSocketHelper.
# The upstream OpenAI socket is ALWAYS faked — no real network. Two levels:
#   * synchronous: reader/writer helpers driven directly with a fake conn
#   * full bridge: Async::WebSocket::Client.connect stubbed to yield a
#     queue-backed fake conn, exercising chunk → session.updated → commit →
#     upstream events end to end.
RSpec.describe "WebSocketHelper STS bridge" do
  # Fake upstream connection: read returns queued incoming frames (then nil
  # to end the reader loop); write captures frames.
  class StsFakeConn
    attr_reader :writes

    def initialize(incoming = [])
      @incoming = incoming
      @writes = []
    end

    def write(body)
      @writes << body
    end

    def flush; end

    def read
      @incoming.shift
    end

    def parsed_writes
      @writes.map { |w| JSON.parse(w) }
    end
  end

  # Blocking variant for the full-bridge test: read parks on an Async::Queue.
  class StsBlockingConn
    attr_reader :writes

    def initialize
      @inbox = Async::Queue.new
      @writes = []
    end

    def push(hash)
      @inbox.enqueue(hash.to_json)
    end

    def close
      @inbox.enqueue(nil)
    end

    def read
      @inbox.dequeue
    end

    def write(body)
      @writes << body
    end

    def flush; end

    def parsed_writes
      @writes.map { |w| JSON.parse(w) }
    end
  end

  # Host including the helper with captured broadcasts and a plain session.
  def build_host(params: {}, messages: [])
    Class.new do
      include WebSocketHelper

      def initialize(params, messages)
        @session = { parameters: params, messages: messages }
        @broadcasts = []
      end

      attr_reader :session, :broadcasts

      def send_or_broadcast(payload, _ws_session_id)
        @broadcasts << payload
      end

      def detect_language(_text)
        "en"
      end

      def sync_session_state!; end
    end.new(params, messages)
  end

  def fresh_state(model: "gpt-realtime-2.1", voice: "alloy", instructions: nil)
    {
      cmd_queue: Async::Queue.new,
      session_ready: false,
      seeded: false,
      abort_seq: 0,
      ready: Async::Condition.new,
      model: model,
      voice: voice,
      instructions: instructions,
      turn: nil
    }
  end

  def fresh_turn(id = "turn1")
    {
      id: id,
      user_partial: +"",
      assistant_transcript: +"",
      gate_open: false,
      pending_fragments: [],
      user_msg_ref: nil,
      assistant_finalized: false,
      cancel_notified: false,
      gate_timer: nil
    }
  end

  def parsed_broadcasts(host)
    host.broadcasts.map { |b| JSON.parse(b) }
  end

  def wait_until(task, timeout: 2.0)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    until yield
      raise "wait_until timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) - start > timeout

      task.sleep(0.005)
    end
  end

  let(:host) { build_host(params: { "model" => "gpt-realtime-2.1", "app_name" => "VoiceChatOpenAI" }) }

  describe "#sts_session_capable?" do
    it "delegates to ModelSpec.supports_speech_to_speech? with the session model" do
      allow(Monadic::Utils::ModelSpec).to receive(:supports_speech_to_speech?)
        .with("gpt-realtime-2.1").and_return(true)
      sess = { parameters: { "model" => "gpt-realtime-2.1" } }
      expect(host.sts_session_capable?(sess)).to be(true)
    end

    it "returns false when ModelSpec says the model is not STS-capable" do
      allow(Monadic::Utils::ModelSpec).to receive(:supports_speech_to_speech?)
        .with("gpt-5").and_return(false)
      sess = { parameters: { "model" => "gpt-5" } }
      expect(host.sts_session_capable?(sess)).to be(false)
    end

    it "accepts string-keyed session/parameters hashes" do
      allow(Monadic::Utils::ModelSpec).to receive(:supports_speech_to_speech?)
        .with("gpt-realtime-2.1").and_return(true)
      sess = { "parameters" => { "model" => "gpt-realtime-2.1" } }
      expect(host.sts_session_capable?(sess)).to be(true)
    end

    it "returns false when no model is set" do
      expect(host.sts_session_capable?({ parameters: {} })).to be(false)
    end

    it "returns false (never raises) when the ModelSpec accessor does not exist yet" do
      allow(Monadic::Utils::ModelSpec).to receive(:supports_speech_to_speech?)
        .and_raise(NoMethodError)
      sess = { parameters: { "model" => "gpt-realtime-2.1" } }
      expect(host.sts_session_capable?(sess)).to be(false)
    end
  end

  describe "#build_sts_session_update_payload (wire contract)" do
    let(:payload) do
      host.send(:build_sts_session_update_payload,
                { model: "gpt-realtime-2.1", voice: "alloy", instructions: "Speak slowly." })
    end
    let(:session_cfg) { payload[:session] }

    it "emits a session.update envelope with type=realtime" do
      expect(payload[:type]).to eq("session.update")
      expect(session_cfg[:type]).to eq("realtime")
    end

    it "requests audio+text modalities" do
      expect(session_cfg[:modalities]).to eq(%w[audio text])
    end

    it "pins input audio to audio/pcm @ 24kHz with client-driven turns" do
      audio_in = session_cfg[:audio][:input]
      expect(audio_in[:format]).to eq({ type: "audio/pcm", rate: 24_000 })
      expect(audio_in.key?(:turn_detection)).to be(true)
      expect(audio_in[:turn_detection]).to be_nil
    end

    it "enables input audio transcription with gpt-4o-transcribe" do
      expect(session_cfg[:audio][:input][:transcription][:model]).to eq("gpt-4o-transcribe")
    end

    it "pins output audio to audio/pcm @ 24kHz and carries the voice" do
      audio_out = session_cfg[:audio][:output]
      expect(audio_out[:format]).to eq({ type: "audio/pcm", rate: 24_000 })
      expect(audio_out[:voice]).to eq("alloy")
    end

    it "carries instructions when provided" do
      expect(session_cfg[:instructions]).to eq("Speak slowly.")
    end

    it "omits instructions when blank" do
      p = host.send(:build_sts_session_update_payload,
                    { model: "m", voice: "alloy", instructions: "  " })
      expect(p[:session].key?(:instructions)).to be(false)
    end
  end

  describe "#handle_sts_audio_commit (defensive surface)" do
    it "broadcasts a no-audio error when no bridge exists" do
      host.handle_sts_audio_commit(nil, {})
      expect(host.broadcasts.length).to eq(1)
      payload = JSON.parse(host.broadcasts.first)
      expect(payload["type"]).to eq("error")
      expect(payload["content"]).to match(/no audio/i)
    end

    it "enqueues [:commit, <fresh turn_id>] when the bridge state is healthy" do
      queue = Async::Queue.new
      host.session[:_sts] = { cmd_queue: queue }
      host.handle_sts_audio_commit(nil, {})
      type, turn_id = queue.dequeue
      expect(type).to eq(:commit)
      expect(turn_id).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  describe "missing API key" do
    it "reports an error to the client and does not crash" do
      stub_const("CONFIG", {})
      state = fresh_state
      host.session[:_sts] = state

      expect { host.send(:run_sts_bridge!, state, "ws-test") }.not_to raise_error

      payloads = parsed_broadcasts(host)
      expect(payloads.length).to eq(1)
      expect(payloads.first["type"]).to eq("error")
      expect(payloads.first["content"]).to match(/OPENAI_API_KEY/)
      expect(host.session[:_sts]).to be_nil
    end
  end

  describe "upstream event → client message mapping" do
    let(:state) { fresh_state }

    def run_reader(host, state, events)
      conn = StsFakeConn.new(events.map(&:to_json))
      host.send(:sts_reader_loop, conn, state, "ws-test")
      conn
    end

    it "accumulates transcription deltas into stt_partial messages" do
      state[:turn] = fresh_turn
      run_reader(host, state, [
                   { type: "conversation.item.input_audio_transcription.delta", delta: "Hello" },
                   { type: "conversation.item.input_audio_transcription.delta", delta: " world" }
                 ])
      partials = parsed_broadcasts(host).select { |p| p["type"] == "stt_partial" }
      expect(partials.map { |p| p["content"] }).to eq(["Hello", "Hello world"])
    end

    it "maps transcription.completed to stt, appends the user message, then releases the gate" do
      turn = fresh_turn
      turn[:pending_fragments] << "assistant chunk"
      state[:turn] = turn

      run_reader(host, state, [
                   { type: "conversation.item.input_audio_transcription.completed", transcript: "hi there" }
                 ])

      payloads = parsed_broadcasts(host)
      stt = payloads.find { |p| p["type"] == "stt" }
      expect(stt).to include("content" => "hi there", "logprob" => nil)

      # user message appended to session[:messages] (streaming_handler shape)
      user_msgs = host.session[:messages].select { |m| m["role"] == "user" }
      expect(user_msgs.length).to eq(1)
      expect(user_msgs.first).to include("text" => "hi there", "app_name" => "VoiceChatOpenAI", "active" => true)
      expect(user_msgs.first["mid"]).to match(/\A[0-9a-f]{8}\z/)

      # order gate: the buffered fragment went out AFTER the stt message,
      # and the user card html goes out BETWEEN stt and the assistant
      # fragments (stt → user card → assistant fragments).
      types = payloads.map { |p| p["type"] }
      expect(types.index("stt")).to be < types.index("html")
      expect(types.index("html")).to be < types.index("fragment")
      user_card = payloads.find { |p| p["type"] == "html" }
      expect(user_card["content"]).to include("role" => "user", "text" => "hi there")
      expect(payloads.find { |p| p["type"] == "fragment" }["content"]).to eq("assistant chunk")
    end

    it "buffers output_audio_transcript.delta while the gate is closed, streams it when open" do
      turn = fresh_turn
      state[:turn] = turn
      run_reader(host, state, [
                   { type: "response.output_audio_transcript.delta", delta: "gated" }
                 ])
      expect(parsed_broadcasts(host)).to be_empty
      expect(turn[:assistant_transcript]).to eq("gated")

      turn[:gate_open] = true
      run_reader(host, state, [
                   { type: "response.output_audio_transcript.delta", delta: "open" }
                 ])
      fragments = parsed_broadcasts(host).select { |p| p["type"] == "fragment" }
      expect(fragments.map { |f| f["content"] }).to eq(["open"])
    end

    it "maps output_audio_transcript.done to the html assistant card and persists it" do
      turn = fresh_turn
      state[:turn] = turn
      run_reader(host, state, [
                   { type: "response.output_audio_transcript.done", transcript: "assistant says hi" }
                 ])

      html = parsed_broadcasts(host).find { |p| p["type"] == "html" }
      expect(html).not_to be_nil
      card = html["content"]
      expect(card).to include(
        "role" => "assistant",
        "text" => "assistant says hi",
        "lang" => "en",
        "app_name" => "VoiceChatOpenAI",
        "active" => true
      )
      expect(card["mid"]).to match(/\A[0-9a-f]{8}\z/)
      expect(host.session[:messages].last).to eq(card)
      expect(turn[:assistant_finalized]).to be(true)
    end

    it "passes response.output_audio.delta through as sts_audio_delta with turn_id and sample rate" do
      state[:turn] = fresh_turn("tid42")
      run_reader(host, state, [
                   { type: "response.output_audio.delta", delta: "QkNERA==" }
                 ])
      msg = parsed_broadcasts(host).find { |p| p["type"] == "sts_audio_delta" }
      expect(msg).to include(
        "turn_id" => "tid42",
        "content" => "QkNERA==",
        "sample_rate" => 24_000
      )
    end

    it "maps response.done to sts_audio_done with turn_id and the usage hash" do
      state[:turn] = fresh_turn("tid7")
      usage = {
        "total_tokens" => 100,
        "input_token_details" => { "audio_tokens" => 60, "cached_tokens" => 10 },
        "output_token_details" => { "audio_tokens" => 30 }
      }
      run_reader(host, state, [
                   { type: "response.done", response: { usage: usage } }
                 ])
      msg = parsed_broadcasts(host).find { |p| p["type"] == "sts_audio_done" }
      expect(msg["turn_id"]).to eq("tid7")
      expect(msg["usage"]).to eq(usage)
    end

    it "maps response.cancelled to sts_audio_cancelled and finalizes the partial card as interrupted" do
      turn = fresh_turn("tid9")
      turn[:assistant_transcript] << "partial answer"
      state[:turn] = turn
      run_reader(host, state, [{ type: "response.cancelled" }])

      payloads = parsed_broadcasts(host)
      cancelled = payloads.find { |p| p["type"] == "sts_audio_cancelled" }
      expect(cancelled["turn_id"]).to eq("tid9")

      html = payloads.find { |p| p["type"] == "html" }
      expect(html["content"]).to include("text" => "partial answer", "interrupted" => true)
    end

    it "maps upstream error events to an error message without raising" do
      expect do
        run_reader(host, state, [
                     { type: "error", error: { message: "boom" } }
                   ])
      end.not_to raise_error
      msg = parsed_broadcasts(host).find { |p| p["type"] == "error" }
      expect(msg["content"]).to match(/boom/)
    end

    it "logs (and accepts) a session.created model mismatch without crashing" do
      state[:model] = "gpt-realtime-2.1"
      matched = host.send(:sts_validate_session_model,
                          { "session" => { "model" => "gpt-realtime-fallback" } }, state, "ws-test")
      expect(matched).to be(false)
      matched = host.send(:sts_validate_session_model,
                          { "session" => { "model" => "gpt-realtime-2.1" } }, state, "ws-test")
      expect(matched).to be(true)
    end
  end

  describe "order gate (task #6)" do
    it "releases buffered fragments on transcription.completed, stt first" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      Async do |_task|
        turn = host.send(:sts_start_new_turn, state, "tid-gate", "ws-test")
        conn = StsFakeConn.new([
                                 { type: "response.output_audio_transcript.delta", delta: "A1" }.to_json,
                                 { type: "response.output_audio_transcript.delta", delta: "A2" }.to_json,
                                 { type: "conversation.item.input_audio_transcription.completed", transcript: "user said" }.to_json
                               ])
        host.send(:sts_reader_loop, conn, state, "ws-test")

        types = parsed_broadcasts(host).map { |p| p["type"] }
        expect(types).to eq(%w[stt html fragment fragment])
        expect(turn[:gate_open]).to be(true)
        expect(turn[:gate_timer]).to be_nil # timer disarmed on completed
      end
    end

    it "releases buffered fragments after the timeout and logs the release" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      stub_const("WebSocketHelper::STS_GATE_TIMEOUT", 0.02)

      Async do |task|
        turn = host.send(:sts_start_new_turn, state, "tid-timeout", "ws-test")
        conn = StsFakeConn.new([
                                 { type: "response.output_audio_transcript.delta", delta: "held" }.to_json
                               ])
        host.send(:sts_reader_loop, conn, state, "ws-test")
        expect(parsed_broadcasts(host)).to be_empty

        task.sleep(0.06)

        fragments = parsed_broadcasts(host).select { |p| p["type"] == "fragment" }
        expect(fragments.map { |f| f["content"] }).to eq(["held"])
        expect(turn[:gate_open]).to be(true)
      end
    end

    it "stops the previous turn's gate timer when a new turn starts (no cross-turn fragment leak)" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      stub_const("WebSocketHelper::STS_GATE_TIMEOUT", 0.05)

      Async do |task|
        turn_a = host.send(:sts_start_new_turn, state, "tid-A", "ws-test")
        conn_a = StsFakeConn.new([
                                   { type: "response.output_audio_transcript.delta", delta: "OLD" }.to_json
                                 ])
        host.send(:sts_reader_loop, conn_a, state, "ws-test")
        expect(turn_a[:pending_fragments]).not_to be_empty

        # Barge-in → quick re-commit: turn B replaces A before A's timer fires.
        turn_b = host.send(:sts_start_new_turn, state, "tid-B", "ws-test")
        expect(turn_a[:gate_timer]).to be_nil

        task.sleep(0.12) # well past A's would-be timeout

        # A's buffered fragment must never reach the client (B's own timer
        # may still open B's empty gate — that is harmless and unrelated).
        fragments = parsed_broadcasts(host).select { |p| p["type"] == "fragment" }
        expect(fragments).to be_empty
      end
    end
  end

  describe "barge-in abort" do
    it "sends response.cancel upstream and emits sts_audio_cancelled + interrupted card" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      state[:session_ready] = true
      state[:seeded] = true
      turn = fresh_turn("tid-abort")
      turn[:assistant_transcript] << "partial"
      state[:turn] = turn
      host.session[:_sts] = state

      conn = StsFakeConn.new
      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        host.handle_sts_audio_abort(nil, {})
        task.sleep(0.02)
        state[:cmd_queue].enqueue(nil)
        writer.wait
      end

      expect(conn.parsed_writes).to include({ "type" => "response.cancel" })

      payloads = parsed_broadcasts(host)
      cancelled = payloads.find { |p| p["type"] == "sts_audio_cancelled" }
      expect(cancelled["turn_id"]).to eq("tid-abort")
      html = payloads.find { |p| p["type"] == "html" }
      expect(html["content"]).to include("text" => "partial", "interrupted" => true)
    end

    it "does not emit a duplicate sts_audio_cancelled when response.cancelled follows the abort" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      state[:session_ready] = true
      state[:seeded] = true
      state[:turn] = fresh_turn("tid-dup")
      host.session[:_sts] = state

      conn = StsFakeConn.new
      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        host.handle_sts_audio_abort(nil, {})
        task.sleep(0.02)
        # upstream confirms the cancel afterwards
        host.send(:sts_reader_loop,
                  StsFakeConn.new([{ type: "response.cancelled" }.to_json]), state, "ws-test")
        state[:cmd_queue].enqueue(nil)
        writer.wait
      end

      cancelled = parsed_broadcasts(host).select { |p| p["type"] == "sts_audio_cancelled" }
      expect(cancelled.length).to eq(1)
    end

    it "no-ops cleanly when no bridge state exists" do
      expect { build_host.handle_sts_audio_abort(nil, {}) }.not_to raise_error
    end

    it "disarms the gate timer and drops gated fragments on interrupted finalization" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      stub_const("WebSocketHelper::STS_GATE_TIMEOUT", 0.05)

      Async do |task|
        turn = host.send(:sts_start_new_turn, state, "tid-int", "ws-test")
        conn = StsFakeConn.new([
                                 { type: "response.output_audio_transcript.delta", delta: "held" }.to_json
                               ])
        host.send(:sts_reader_loop, conn, state, "ws-test")
        expect(turn[:pending_fragments]).not_to be_empty
        turn[:assistant_transcript] << "partial"

        host.send(:sts_finalize_interrupted_turn, state, turn, "ws-test")
        expect(turn[:gate_timer]).to be_nil
        expect(turn[:pending_fragments]).to be_empty

        task.sleep(0.12) # past the disarmed timer's would-be fire time

        fragments = parsed_broadcasts(host).select { |p| p["type"] == "fragment" }
        expect(fragments).to be_empty
        html = parsed_broadcasts(host).find { |p| p["type"] == "html" }
        expect(html["content"]["interrupted"]).to be(true)
        expect(html["content"]["text"]).to include("partial")
      end
    end
  end

  describe "writer: hold-chunks-until-session.updated then flush" do
    it "buffers appends until seeded, then flushes in order after the seed" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      conn = StsFakeConn.new

      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }

        state[:cmd_queue].enqueue([:append, "QUFB"])
        task.sleep(0.02)
        expect(conn.writes).to be_empty # session.updated not yet received

        state[:session_ready] = true
        state[:cmd_queue].enqueue([:seed])
        state[:cmd_queue].enqueue([:append, "QkJC"])
        wait_until(task) { conn.parsed_writes.any? { |w| w["type"] == "input_audio_buffer.append" } }

        appends = conn.parsed_writes.select { |w| w["type"] == "input_audio_buffer.append" }
        expect(appends.map { |a| a["audio"] }).to eq(%w[QUFB QkJC])
        expect(state[:seeded]).to be(true)

        state[:cmd_queue].enqueue(nil)
        writer.wait
      end
    end

    it "commit writes input_audio_buffer.commit + response.create and starts a new turn" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      state[:session_ready] = true
      state[:seeded] = true
      conn = StsFakeConn.new

      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        state[:cmd_queue].enqueue([:commit, "tid-commit"])
        wait_until(task) { conn.parsed_writes.any? { |w| w["type"] == "response.create" } }

        types = conn.parsed_writes.map { |w| w["type"] }
        expect(types.index("input_audio_buffer.commit")).to be < types.index("response.create")
        expect(state[:turn][:id]).to eq("tid-commit")

        state[:cmd_queue].enqueue(nil)
        writer.wait
      end
    end
  end

  describe "history seeding (task #8)" do
    let(:messages) do
      [
        { "role" => "system", "text" => "system prompt" },
        { "role" => "user", "text" => "u1" },
        { "role" => "assistant", "text" => "a1" },
        { "role" => "user", "text" => "u2" },
        { "role" => "assistant", "text" => "a2" }
      ]
    end

    def seed(host, state)
      conn = StsFakeConn.new
      host.send(:sts_seed_history, conn, state, "ws-test")
      conn.parsed_writes
    end

    it "seeds user/assistant text items only, applying the context_size sliding window" do
      host = build_host(params: { "context_size" => "2" }, messages: messages)
      items = seed(host, fresh_state)

      # Window keeps first + last 2 (system, u2, a2); the role filter then
      # drops the system item — exactly like the vendor helpers' context
      # assembly (first message + .last(context_size)).
      expect(items.map { |i| i.dig("item", "role") }).to eq(%w[user assistant])
      expect(items.map { |i| i.dig("item", "content", 0, "text") }).to eq(%w[u2 a2])
      expect(items.all? { |i| i["type"] == "conversation.item.create" }).to be(true)
      # user text uses input_text; assistant text uses text
      expect(items.first.dig("item", "content", 0, "type")).to eq("input_text")
      expect(items.last.dig("item", "content", 0, "type")).to eq("text")
    end

    it "skips non-user/assistant roles and empty texts" do
      msgs = [
        { "role" => "user", "text" => "hello" },
        { "role" => "system", "text" => "sys" },
        { "role" => "assistant", "text" => "  " },
        { "type" => "search", "role" => "assistant", "text" => "search card" }
      ]
      host = build_host(params: { "context_size" => "10" }, messages: msgs)
      items = seed(host, fresh_state)
      expect(items.map { |i| i.dig("item", "content", 0, "text") }).to eq(["hello"])
    end

    it "skips the in-progress turn's user message but seeds it once the turn finalized" do
      host = build_host(params: { "context_size" => "10" }, messages: messages)
      state = fresh_state
      turn = fresh_turn("tid-inprog")
      turn[:user_msg_ref] = messages[3] # "u2" was spoken this turn
      state[:turn] = turn

      items = seed(host, state)
      texts = items.map { |i| i.dig("item", "content", 0, "text") }
      expect(texts).not_to include("u2")

      turn[:assistant_finalized] = true
      items = seed(host, state)
      texts = items.map { |i| i.dig("item", "content", 0, "text") }
      expect(texts).to include("u2")
    end

    it "seeds everything when context_size is large enough" do
      host = build_host(params: { "context_size" => "50" }, messages: messages)
      items = seed(host, fresh_state)
      expect(items.map { |i| i.dig("item", "content", 0, "text") }).to eq(%w[u1 a1 u2 a2])
    end
  end

  describe "usage accounting (task #10)" do
    it "extracts audio/cached tokens and computes a cost estimate" do
      usage = {
        "input_token_details" => {
          "audio_tokens" => 1_000_000,
          "cached_tokens" => 500,
          "cached_tokens_details" => { "audio_tokens" => 400 }
        },
        "output_token_details" => { "audio_tokens" => 500_000 }
      }
      acct = host.send(:sts_usage_accounting, usage)
      expect(acct[:audio_input_tokens]).to eq(1_000_000)
      expect(acct[:audio_output_tokens]).to eq(500_000)
      expect(acct[:cached_tokens]).to eq(400)
      # $32/1M in + $64/1M out → 32 + 32 = 64
      expect(acct[:estimated_cost_usd]).to be_within(0.0001).of(64.0)
    end

    it "tolerates a missing/partial usage hash" do
      acct = host.send(:sts_usage_accounting, nil)
      expect(acct).to eq(audio_input_tokens: 0, audio_output_tokens: 0,
                         cached_tokens: 0, estimated_cost_usd: 0.0)
    end

    it "attaches server-computed accounting to sts_audio_done (rates stay server-side)" do
      state = fresh_state
      state[:turn] = fresh_turn("tid-acct")
      payload = {
        "response" => {
          "usage" => {
            "input_token_details" => {
              "audio_tokens" => 1_000_000,
              "cached_tokens_details" => { "audio_tokens" => 400 }
            },
            "output_token_details" => { "audio_tokens" => 500_000 }
          }
        }
      }

      host.send(:sts_handle_response_done, state, payload, "ws-test")

      done = parsed_broadcasts(host).find { |p| p["type"] == "sts_audio_done" }
      expect(done["turn_id"]).to eq("tid-acct")
      expect(done["usage"]).to be_a(Hash)
      expect(done["accounting"]).to include(
        "audio_input_tokens" => 1_000_000,
        "audio_output_tokens" => 500_000,
        "cached_tokens" => 400
      )
      # Upper bound: cached input is still priced at the full rate (32+32=64).
      expect(done["accounting"]["estimated_cost_usd"]).to be_within(0.0001).of(64.0)
    end
  end

  describe "constants and concurrency cap" do
    it "uses the OpenAI Realtime endpoint base URL" do
      expect(WebSocketHelper::REALTIME_STS_URL).to eq("wss://api.openai.com/v1/realtime")
    end

    it "defaults to gpt-realtime-2.1 / alloy" do
      expect(WebSocketHelper::REALTIME_STS_DEFAULT_MODEL).to eq("gpt-realtime-2.1")
      expect(WebSocketHelper::REALTIME_STS_DEFAULT_VOICE).to eq("alloy")
    end

    it "caps concurrent upstream WS connections at 4 by default" do
      expect(WebSocketHelper::STS_MAX_CONCURRENT).to eq(4)
    end

    it "exposes a singleton Async::Semaphore with the configured limit" do
      sem = WebSocketHelper.sts_semaphore
      expect(sem).to be_an(Async::Semaphore)
      expect(sem.limit).to eq(WebSocketHelper::STS_MAX_CONCURRENT)
      expect(WebSocketHelper.sts_semaphore).to equal(sem)
    end
  end

  describe "reconnect backoff (healthy-session reset)" do
    it "gives up after STS_MAX_RECONNECTS when connections die before the healthy threshold" do
      stub_const("CONFIG", { "OPENAI_API_KEY" => "sk-test" })
      stub_const("WebSocketHelper::STS_HEALTHY_SESSION_SECONDS", 3600) # unreachable here
      calls = 0
      sleeps = []
      allow(host).to receive(:sts_connect_and_run) do
        calls += 1
        raise StandardError, "flap"
      end
      allow(host).to receive(:sleep) { |d| sleeps << d }

      state = fresh_state
      host.session[:_sts] = state
      Async { host.send(:run_sts_bridge!, state, "ws-test") }.wait

      expect(calls).to eq(WebSocketHelper::STS_MAX_RECONNECTS + 1)
      expect(sleeps).to eq([1, 2, 3])
      errors = parsed_broadcasts(host).select { |p| p["type"] == "error" }
      expect(errors.last["content"]).to include("lost")
    end

    it "resets the backoff only for sessions that lived past the healthy threshold" do
      stub_const("CONFIG", { "OPENAI_API_KEY" => "sk-test" })
      stub_const("WebSocketHelper::STS_HEALTHY_SESSION_SECONDS", 0) # any handshake counts
      calls = 0
      sleeps = []
      allow(host).to receive(:sts_connect_and_run) do |state, _, _|
        calls += 1
        state[:session_ready] = true # handshake completed
        # Stop the bridge TASK (not `throw` — UncaughtThrowError is a
        # StandardError and would be swallowed by the loop's own rescue,
        # turning the test into an infinite loop).
        Async::Task.current.stop if calls > WebSocketHelper::STS_MAX_RECONNECTS + 2
        raise StandardError, "flap"
      end
      allow(host).to receive(:sleep) { |d| sleeps << d }

      state = fresh_state
      host.session[:_sts] = state
      Async { host.send(:run_sts_bridge!, state, "ws-test") }.wait

      # Exceeded the nominal cap WITHOUT giving up → the counter kept
      # resetting (constant 1s backoff, no exhaustion error).
      expect(calls).to eq(WebSocketHelper::STS_MAX_RECONNECTS + 3)
      expect(sleeps.uniq).to eq([1])
      exhaustion = parsed_broadcasts(host).select { |p| p["type"] == "error" && p["content"].include?("lost") }
      expect(exhaustion).to be_empty
    end
  end

  describe "full bridge (Async::WebSocket::Client.connect mocked, no network)" do
    it "runs chunk → session.updated → commit → upstream events end to end" do
      stub_const("CONFIG", { "OPENAI_API_KEY" => "sk-test" })
      host = build_host(params: {
                          "model" => "gpt-realtime-2.1",
                          "app_name" => "VoiceChatOpenAI",
                          "tts_voice" => "nova",
                          "context_size" => "10"
                        })
      conn = StsBlockingConn.new
      captured = {}

      allow(Async::WebSocket::Client).to receive(:connect) do |endpoint, headers:, &blk|
        captured[:url] = endpoint.url.to_s
        captured[:headers] = headers
        blk.call(conn)
      end

      Async do |task|
        host.handle_sts_audio_chunk(nil, { "content" => "QUJD" })
        state = host.session[:_sts]
        expect(state).not_to be_nil

        # session.update went out, model is in the URL, auth header set
        wait_until(task) { conn.parsed_writes.any? { |w| w["type"] == "session.update" } }
        expect(captured[:url]).to include("model=gpt-realtime-2.1")
        expect(captured[:headers]["Authorization"]).to eq("Bearer sk-test")
        update = conn.parsed_writes.find { |w| w["type"] == "session.update" }
        expect(update.dig("session", "audio", "output", "voice")).to eq("nova")

        # chunk held until session.updated
        expect(conn.parsed_writes.none? { |w| w["type"] == "input_audio_buffer.append" }).to be(true)
        conn.push({ type: "session.created", session: { model: "gpt-realtime-2.1" } })
        conn.push({ type: "session.updated" })
        wait_until(task) { conn.parsed_writes.any? { |w| w["type"] == "input_audio_buffer.append" } }

        # commit → upstream commit + response.create, new turn
        host.handle_sts_audio_commit(nil, {})
        wait_until(task) { conn.parsed_writes.any? { |w| w["type"] == "response.create" } }
        turn = state[:turn]
        expect(turn).not_to be_nil

        # upstream events → client messages
        conn.push({ type: "conversation.item.input_audio_transcription.completed", transcript: "hello" })
        conn.push({ type: "response.output_audio.delta", delta: "QUJD" })
        conn.push({ type: "response.output_audio_transcript.done", transcript: "hi there" })
        conn.push({ type: "response.done",
                    response: { usage: { "input_token_details" => { "audio_tokens" => 100 },
                                         "output_token_details" => { "audio_tokens" => 50 } } } })
        wait_until(task) { parsed_broadcasts(host).any? { |p| p["type"] == "sts_audio_done" } }

        types = parsed_broadcasts(host).map { |p| p["type"] }
        expect(types).to include("stt", "html", "sts_audio_delta", "sts_audio_done")
        audio_delta = parsed_broadcasts(host).find { |p| p["type"] == "sts_audio_delta" }
        expect(audio_delta["turn_id"]).to eq(turn[:id])
        expect(audio_delta["sample_rate"]).to eq(24_000)
        done = parsed_broadcasts(host).find { |p| p["type"] == "sts_audio_done" }
        expect(done.dig("usage", "input_token_details", "audio_tokens")).to eq(100)

        # user + assistant messages persisted
        roles = host.session[:messages].map { |m| m["role"] }
        expect(roles).to include("user", "assistant")

        state[:bridge_task]&.stop
      end
    end
  end
end
