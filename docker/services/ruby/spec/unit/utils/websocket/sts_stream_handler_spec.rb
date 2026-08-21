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
require 'monadic/utils/container_dependencies'

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

    it "requests audio output via the GA output_modalities key" do
      # The legacy `modalities` key is rejected by the GA API ("Unknown
      # parameter") — its earlier acceptance was a rolling-deployment tail.
      expect(session_cfg[:output_modalities]).to eq(%w[audio])
      expect(session_cfg).not_to have_key(:modalities)
    end

    it "pins input audio to audio/pcm @ 24kHz with server-VAD turns" do
      audio_in = session_cfg[:audio][:input]
      expect(audio_in[:format]).to eq({ type: "audio/pcm", rate: 24_000 })
      # Continuous mode: the server VAD segments turns (create_response /
      # interrupt_response default to true upstream — live-probed).
      expect(audio_in[:turn_detection]).to eq({ type: "server_vad" })
    end

    it "enables input audio transcription with gpt-4o-transcribe" do
      expect(session_cfg[:audio][:input][:transcription][:model]).to eq("gpt-4o-transcribe")
    end

    it "pins output audio to audio/pcm @ 24kHz and carries the voice" do
      audio_out = session_cfg[:audio][:output]
      expect(audio_out[:format]).to eq({ type: "audio/pcm", rate: 24_000 })
      expect(audio_out[:voice]).to eq("alloy")
    end

    it "carries instructions when provided (language directive appended)" do
      expect(session_cfg[:instructions]).to start_with("Speak slowly.")
      # With no explicit language, the auto language-matching directive is
      # appended — same LanguageConfig text as the typed pipeline.
      expect(session_cfg[:instructions]).to include("LANGUAGE MATCHING")
    end

    it "still sends the language directive when app instructions are blank" do
      p = host.send(:build_sts_session_update_payload,
                    { model: "m", voice: "alloy", instructions: "  " })
      expect(p[:session][:instructions]).to include("LANGUAGE MATCHING")
      expect(p[:session][:instructions]).not_to start_with("\n")
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
      # §39: the card exists only when the response was actually SPOKEN —
      # mark an audio frame as having arrived for this turn.
      turn[:spoken_response_ids] = { "r" => true }
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
      # §39: an interrupted card requires a spoken response (audio frame).
      turn[:spoken_response_ids] = { "r" => true }
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
        # §39: the interrupted card exists only for a SPOKEN response.
        turn[:spoken_response_ids] = { "r" => true }

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

  describe "initiate_from_assistant (STS_INITIATE)" do
    it "sends response.create with greeting instructions and opens the gate immediately" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state(instructions: "You are a friendly assistant.")
      state[:session_ready] = true
      state[:seeded] = true
      state[:bridge_task] = double(:bridge_task, finished?: false)
      host.session[:_sts] = state

      conn = StsFakeConn.new
      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        host.handle_sts_initiate(nil, {})
        task.sleep(0.02)
        state[:cmd_queue].enqueue(nil)
        writer.wait
      end

      create = conn.parsed_writes.find { |w| w["type"] == "response.create" }
      # GA's response.create REPLACES the session instructions for that
      # response — the greeting instructions must therefore CARRY the app
      # instructions (and the language prompt), or the greeting drops the
      # conversation language (dogfood: Japanese session greeted in English).
      greeting = create["response"]["instructions"]
      expect(greeting).to include("You are a friendly assistant.")
      expect(greeting).to include(WebSocketHelper::STS_INITIATE_INSTRUCTIONS)
      expect(greeting).to include(
        Monadic::Utils::LanguageConfig.system_prompt_for_language("auto"))
      # No input_audio_buffer.commit: an initiated turn carries no user audio
      expect(conn.parsed_writes.none? { |w| w["type"] == "input_audio_buffer.commit" }).to be(true)

      turn = state[:turn]
      expect(turn).not_to be_nil
      expect(turn[:gate_open]).to be(true)
      expect(turn[:gate_timer]).to be_nil # disarmed by the immediate open

      # An initiated turn has no user utterance: nothing is persisted as user
      user_msgs = host.session[:messages].select { |m| m["role"] == "user" }
      expect(user_msgs).to be_empty
    end

    it "restates the language prompt in the Gemini greeting nudge" do
      host = build_host(params: { "app_name" => "LiveConversationGemini" })
      state = fresh_state(instructions: "You are a friendly assistant.")
      state[:provider] = "gemini"
      state[:language] = "ja"
      state[:session_ready] = true
      state[:seeded] = true
      state[:bridge_task] = double(:bridge_task, finished?: false)
      host.session[:_sts] = state

      conn = StsFakeConn.new
      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        host.handle_sts_initiate(nil, {})
        task.sleep(0.02)
        state[:cmd_queue].enqueue(nil)
        writer.wait
      end

      content = conn.parsed_writes.find { |w| w["clientContent"] }
      nudge = content.dig("clientContent", "turns", 0, "parts", 0, "text")
      # An English-only nudge can pull the greeting's language even though
      # Gemini's systemInstruction stays in effect — the language directive
      # is restated right at generation time.
      expect(nudge).to include(WebSocketHelper::STS_INITIATE_INSTRUCTIONS)
      expect(nudge).to include(
        Monadic::Utils::LanguageConfig.system_prompt_for_language("ja"))
    end

    it "streams the assistant greeting as fragments without an stt message" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      Async do |_task|
        turn = host.send(:sts_start_new_turn, state, "tid-init", "ws-test")
        host.send(:sts_open_gate, turn, "ws-test", reason: "initiate")
        conn = StsFakeConn.new([
                                 { type: "response.output_audio_transcript.delta", delta: "Hi! " }.to_json,
                                 { type: "response.output_audio_transcript.delta", delta: "Nice to meet you." }.to_json,
                                 { type: "response.output_audio_transcript.done", transcript: "Hi! Nice to meet you." }.to_json
                               ])
        host.send(:sts_reader_loop, conn, state, "ws-test")

        types = parsed_broadcasts(host).map { |p| p["type"] }
        expect(types).to eq(%w[fragment fragment html])
        expect(host.session[:messages].last).to include("role" => "assistant", "text" => "Hi! Nice to meet you.")
      end
    end

    # Mic warm-up noise buffered before Start once got flushed after the
    # greeting; the VAD heard it as speech and barge-in-cancelled the
    # greeting (its transcript hallucinated into a stray sentence). The
    # conversation starts at :start — earlier audio is discarded.
    it "discards audio chunks buffered before :start" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      state[:session_ready] = true
      state[:seeded] = true

      conn = StsFakeConn.new
      state[:session_ready] = false # chunks before start are held, not sent
      state[:cmd_queue].enqueue([:append, "PRESTART"])
      state[:cmd_queue].enqueue([:start, false])
      state[:cmd_queue].enqueue([:append, "LIVE"])
      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        # Writer: PRESTART → pending, :start → clears pending, then parks in
        # sts_wait_for_ready. Release it and let LIVE flow.
        task.sleep(0.02)
        state[:session_ready] = true
        state[:ready].signal
        task.sleep(0.02)
        state[:cmd_queue].enqueue(nil)
        writer.wait
      end

      appended = conn.parsed_writes.select { |w| w["type"] == "input_audio_buffer.append" }
                     .map { |w| w["audio"] }
      expect(appended).to eq(["LIVE"])
    end

    # Review P3-1: pending discard is once per bridge too — a duplicate
    # STS_START mid-conversation must not throw away legitimate speech
    # buffered across a reconnect.
    it "keeps buffered audio on a duplicate :start" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      state[:session_ready] = true
      state[:seeded] = true
      state[:started] = true # first :start already happened

      conn = StsFakeConn.new
      state[:session_ready] = false
      state[:cmd_queue].enqueue([:append, "BUFFERED"])
      state[:cmd_queue].enqueue([:start, false])
      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        task.sleep(0.02)
        state[:session_ready] = true
        state[:ready].signal
        task.sleep(0.02)
        state[:cmd_queue].enqueue([:append, "LIVE"])
        task.sleep(0.02)
        state[:cmd_queue].enqueue(nil)
        writer.wait
      end

      appended = conn.parsed_writes.select { |w| w["type"] == "input_audio_buffer.append" }
                     .map { |w| w["audio"] }
      expect(appended).to eq(%w[BUFFERED LIVE])
    end

    # A duplicate STS_START (double-click, two tabs, retried message) must not
    # re-greet mid-conversation: the greeting fires once per bridge.
    it "greets only once for repeated [:start, true] commands" do
      host = build_host(params: { "app_name" => "VoiceChatOpenAI" })
      state = fresh_state
      state[:session_ready] = true
      state[:seeded] = true

      conn = StsFakeConn.new
      Async do |task|
        writer = task.async { host.send(:sts_writer_loop, conn, state, "ws-test") }
        state[:cmd_queue].enqueue([:start, true])
        state[:cmd_queue].enqueue([:start, true])
        task.sleep(0.02)
        state[:cmd_queue].enqueue(nil)
        writer.wait
      end

      creates = conn.parsed_writes.select { |w| w["type"] == "response.create" }
      expect(creates.size).to eq(1)
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
      # GA vocabulary (live-probed 2026-07-31): user items take input_text,
      # assistant items take output_text — the legacy "text" is rejected
      # ("Invalid value: 'text'. Value must be 'output_text'."), which
      # surfaced on the first mid-conversation reconnect re-seed.
      expect(items.first.dig("item", "content", 0, "type")).to eq("input_text")
      expect(items.last.dig("item", "content", 0, "type")).to eq("output_text")
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
                          "tts_voice" => "marin", # realtime-only voice: proves pass-through survives the whitelist
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
        expect(update.dig("session", "audio", "output", "voice")).to eq("marin")

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

# Realtime voices are a different vocabulary from the TTS voices, so the
# session state must never carry a TTS-only voice into session.update —
# OpenAI rejects it ("Invalid value: 'nova'") and the bridge dies on setup.
# 'coral' existing in both sets is what let earlier testing miss this.
RSpec.describe 'STS voice whitelist' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :ensure_sts_state!
      def get_session_params = session[:parameters]
    end.new
  end

  before do
    harness.session = { parameters: params }
    allow(harness).to receive(:run_sts_bridge!) # do not open a real bridge
    allow(Async).to receive(:call) if defined?(Async)
  end

  def state_for(params_hash)
    harness.session = { parameters: params_hash }
    allow(Thread.current).to receive(:[]).and_call_original
    harness.ensure_sts_state!({})
  end

  let(:params) { { 'model' => 'gpt-realtime-2.1' } }

  it 'keeps a voice the realtime API supports' do
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'tts_voice' => 'coral' })
    expect(st[:voice]).to eq('coral')
  end

  it 'falls back to the default for a TTS-only voice' do
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'tts_voice' => 'nova' })
    expect(st[:voice]).to eq(WebSocketHelper::REALTIME_STS_DEFAULT_VOICE)
  end

  it 'falls back to the default when no voice is set' do
    st = state_for({ 'model' => 'gpt-realtime-2.1' })
    expect(st[:voice]).to eq(WebSocketHelper::REALTIME_STS_DEFAULT_VOICE)
  end

  it 'every whitelisted voice passes through unchanged' do
    WebSocketHelper::REALTIME_STS_VOICES.each do |v|
      st = state_for({ 'model' => 'gpt-realtime-2.1', 'tts_voice' => v })
      expect(st[:voice]).to eq(v)
    end
  end
end

# ── Live Conversation continuous mode ────────────────────────────────────────
# The VAD-driven pieces: session start/stop handlers, per-app VAD tuning, and
# the reader's reaction to upstream speech events (turn creation, native
# barge-in finalization, state relays). Upstream is always faked.
RSpec.describe 'WebSocketHelper STS continuous mode' do
  let(:sent) { [] }

  let(:harness) do
    msgs = sent
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :sts_vad_config, :handle_sts_start, :handle_sts_stop,
             :sts_reader_loop, :ensure_sts_state!

      define_method(:send_or_broadcast) { |json, _sid| msgs << JSON.parse(json) }
      def get_session_params = session[:parameters]
      def sync_session_state!; end
      def detect_language(_t) = 'en'
    end.new
  end

  before do
    harness.session = { parameters: { 'app_name' => 'LiveConversationOpenAI',
                                      'model' => 'gpt-realtime-2.1' }, messages: [] }
    allow(Thread.current).to receive(:[]).and_call_original
  end

  describe '#sts_vad_config' do
    it 'defaults to bare server_vad (API defaults for tuning keys)' do
      stub_const('APPS', {})
      expect(harness.sts_vad_config).to eq({ type: 'server_vad' })
    end

    it 'passes through MDSL tuning keys when the app declares them' do
      app = double('app', settings: { sts_vad_silence_ms: 800, 'sts_vad_threshold' => 0.7 })
      stub_const('APPS', { 'LiveConversationOpenAI' => app })

      cfg = harness.sts_vad_config
      expect(cfg[:silence_duration_ms]).to eq(800)
      expect(cfg[:threshold]).to eq(0.7)
      expect(cfg[:type]).to eq('server_vad')
    end

    it 'switches to semantic_vad when the app opts in via MDSL' do
      app = double('app', settings: { sts_vad_type: 'semantic_vad', sts_vad_eagerness: 'low' })
      stub_const('APPS', { 'LiveConversationOpenAI' => app })

      expect(harness.sts_vad_config).to eq({ type: 'semantic_vad', eagerness: 'low' })
    end

    it 'accepts every valid eagerness value including medium' do
      %w[low medium high auto].each do |eag|
        app = double('app', settings: { sts_vad_type: 'semantic_vad', sts_vad_eagerness: eag })
        stub_const('APPS', { 'LiveConversationOpenAI' => app })
        expect(harness.sts_vad_config[:eagerness]).to eq(eag)
      end
    end

    it 'caps runaway millisecond values (sanity limit)' do
      app = double('app', settings: { sts_vad_silence_ms: 999_999 })
      stub_const('APPS', { 'LiveConversationOpenAI' => app })
      expect(harness.sts_vad_config).to eq({ type: 'server_vad' })
    end

    it 'drops an invalid eagerness value (API default applies)' do
      app = double('app', settings: { sts_vad_type: 'semantic_vad', sts_vad_eagerness: 'max' })
      stub_const('APPS', { 'LiveConversationOpenAI' => app })

      expect(harness.sts_vad_config).to eq({ type: 'semantic_vad' })
    end

    # Invalid tuning values would reach the upstream session.update and fail
    # with a silent 400 — validate here and fall back to API defaults.
    it 'ignores non-numeric, negative, and out-of-range tuning values' do
      app = double('app', settings: { sts_vad_threshold: 1.5,        # > 1
                                      sts_vad_prefix_ms: -100,       # negative
                                      sts_vad_silence_ms: 'long' })  # not a number
      stub_const('APPS', { 'LiveConversationOpenAI' => app })

      expect(harness.sts_vad_config).to eq({ type: 'server_vad' })
    end

    it 'lets session params override the MDSL vad type (§37-16)' do
      app = double('app', settings: { sts_vad_silence_ms: 800 })
      stub_const('APPS', { 'LiveConversationOpenAI' => app })
      harness.session[:parameters]['sts_vad_type'] = 'semantic_vad'
      harness.session[:parameters]['sts_vad_eagerness'] = 'high'

      cfg = harness.sts_vad_config
      expect(cfg).to eq({ type: 'semantic_vad', eagerness: 'high' })
    end

    it 'never mixes server_vad numeric keys into a semantic selection' do
      app = double('app', settings: { sts_vad_silence_ms: 800, sts_vad_threshold: 0.7 })
      stub_const('APPS', { 'LiveConversationOpenAI' => app })
      harness.session[:parameters]['sts_vad_type'] = 'semantic_vad'

      cfg = harness.sts_vad_config
      expect(cfg[:type]).to eq('semantic_vad')
      expect(cfg).not_to have_key(:silence_duration_ms)
      expect(cfg).not_to have_key(:threshold)
    end

    it 'falls back to the MDSL default when params are invalid' do
      app = double('app', settings: { sts_vad_type: 'semantic_vad', sts_vad_eagerness: 'low' })
      stub_const('APPS', { 'LiveConversationOpenAI' => app })
      harness.session[:parameters]['sts_vad_type'] = 'bogus'
      harness.session[:parameters]['sts_vad_eagerness'] = 'bogus'

      expect(harness.sts_vad_config).to eq({ type: 'semantic_vad', eagerness: 'low' })
    end

    it 'does not send eagerness with server_vad' do
      stub_const('APPS', {})
      harness.session[:parameters]['sts_vad_type'] = 'server_vad'
      harness.session[:parameters]['sts_vad_eagerness'] = 'low'

      expect(harness.sts_vad_config).to eq({ type: 'server_vad' })
    end
  end

  describe '#handle_sts_start' do
    it 'enqueues :start with the greet flag' do
      queue = Async::Queue.new
      harness.session[:_sts] = { cmd_queue: queue,
                                 bridge_task: double(finished?: false) }

      harness.handle_sts_start(nil, { 'greet' => true, 'chat_model' => 'gpt-realtime-2.1' })

      Sync { expect(queue.dequeue).to eq([:start, true]) }
    end

    it 'treats a missing greet flag as false (resume: no greeting)' do
      queue = Async::Queue.new
      harness.session[:_sts] = { cmd_queue: queue,
                                 bridge_task: double(finished?: false) }

      harness.handle_sts_start(nil, { 'chat_model' => 'gpt-realtime-2.1' })

      Sync { expect(queue.dequeue).to eq([:start, false]) }
    end

    # Fresh-vs-resume is decided here against the canonical
    # session[:messages] — the client's greet hint only reports the toggle.
    # A stale client-side messages array once suppressed the greeting on a
    # genuinely fresh conversation (dogfood round 4).
    it 'suppresses the greeting when the canon has conversation turns' do
      queue = Async::Queue.new
      harness.session[:messages] = [{ 'role' => 'user', 'text' => 'earlier' }]
      harness.session[:_sts] = { cmd_queue: queue,
                                 bridge_task: double(finished?: false) }

      harness.handle_sts_start(nil, { 'greet' => true })

      Sync { expect(queue.dequeue).to eq([:start, false]) }
    end

    # Review round 5, concern #1: after a fatal (e.g. xAI silent model
    # fallback) mic chunks still in flight must not respawn the bridge into
    # the same fatal — each respawn opens a billed upstream session.
    it 'refuses to respawn a bridge for the model that just failed fatally' do
      harness.session[:_sts_fatal] = 'grok-voice-think-fast-2.0'
      allow(harness).to receive(:run_sts_bridge!)

      state = harness.ensure_sts_state!({ 'chat_model' => 'grok-voice-think-fast-2.0' })

      expect(state).to be_nil
      expect(harness.session[:_sts]).to be_nil
    end

    it 'clears the fatal memory when a different model is requested' do
      harness.session[:_sts_fatal] = 'grok-voice-think-fast-2.0'
      # The bridge itself is not under test — spawning it would open a real
      # upstream connection from a unit spec.
      allow(harness).to receive(:run_sts_bridge!)

      state = harness.ensure_sts_state!({ 'chat_model' => 'gpt-realtime-2.1' })

      expect(state).not_to be_nil
      expect(harness.session[:_sts_fatal]).to be_nil
      harness.session[:_sts] && harness.session[:_sts][:bridge_task]&.stop
    end

    it 'records the merge span at Start (fresh per bridge)' do
      queue = Async::Queue.new
      harness.session[:messages] = [{ 'role' => 'system', 'text' => 'p' },
                                    { 'role' => 'user', 'text' => 'q' }]
      state = { cmd_queue: queue, bridge_task: double(finished?: false) }
      harness.session[:_sts] = state

      harness.handle_sts_start(nil, {})

      expect(state[:canon_start]).to eq(2)
    end

    # Review P1-A: session start ALWAYS appends the system prompt to the
    # canon before Start can be pressed, so an emptiness check never greeted.
    # Fresh means no user/assistant turns — system messages do not count.
    it 'still greets when the canon holds only the system prompt' do
      queue = Async::Queue.new
      harness.session[:messages] = [{ 'role' => 'system', 'text' => 'You are…' }]
      harness.session[:_sts] = { cmd_queue: queue,
                                 bridge_task: double(finished?: false) }

      harness.handle_sts_start(nil, { 'greet' => true })

      Sync { expect(queue.dequeue).to eq([:start, true]) }
    end
  end

  describe '#handle_sts_stop' do
    it 'finalizes the in-flight turn, tears down, and reports stopped' do
      turn = { id: 't1', assistant_transcript: +'partial words', assistant_finalized: false,
               cancel_notified: false, gate_timer: nil, pending_fragments: [], gate_open: true,
               user_partial: +'', user_msg_ref: nil, spoken_response_ids: { 'r' => true } }
      queue = Async::Queue.new
      task = double('task', finished?: false, stop: nil)
      harness.session[:_sts] = { cmd_queue: queue, bridge_task: task, turn: turn,
                                 ready: Async::Condition.new }

      Sync { harness.handle_sts_stop(nil, {}) }

      types = sent.map { |m| m['type'] }
      expect(types).to include('html')                 # interrupted card
      expect(types).to include('sts_audio_cancelled')  # client discards audio
      expect(types.last).to eq('sts_session')
      expect(sent.last['state']).to eq('stopped')
      expect(harness.session[:_sts]).to be_nil         # torn down
    end

    it 'is a safe no-op without a bridge (still reports stopped)' do
      expect { Sync { harness.handle_sts_stop(nil, {}) } }.not_to raise_error
      expect(sent.last).to eq({ 'type' => 'sts_session', 'state' => 'stopped',
                                'merged' => false })
    end
  end

  # Stop-time consolidation: VAD-split turns leave consecutive same-role
  # cards; the saved conversation should read as alternating turns.
  describe '#sts_merge_conversation_fragments!' do
    it 'folds consecutive same-role messages within the conversation span' do
      harness.session[:messages] = [
        { 'role' => 'system', 'text' => 'prompt' },
        { 'role' => 'user', 'text' => 'The' },
        { 'role' => 'user', 'text' => 'Odyssey by Homer.' },
        { 'role' => 'assistant', 'text' => 'Nice, that sounds', 'interrupted' => true },
        { 'role' => 'assistant', 'text' => 'A classic indeed.' }
      ]
      state = { canon_start: 1 }

      changed = harness.send(:sts_merge_conversation_fragments!, harness.session, state)

      expect(changed).to be true
      msgs = harness.session[:messages]
      expect(msgs.length).to eq(3)
      expect(msgs[1]['text']).to eq("The

Odyssey by Homer.")
      # A later completed piece supersedes the interrupted stub
      expect(msgs[2]['text']).to eq("Nice, that sounds

A classic indeed.")
      expect(msgs[2]).not_to have_key('interrupted')
    end

    it 'never rewrites messages before the span (loaded history is sacred)' do
      harness.session[:messages] = [
        { 'role' => 'user', 'text' => 'old A' },
        { 'role' => 'user', 'text' => 'old B' },
        { 'role' => 'user', 'text' => 'new fragment' }
      ]
      state = { canon_start: 2 }

      harness.send(:sts_merge_conversation_fragments!, harness.session, state)

      expect(harness.session[:messages][0]['text']).to eq('old A')
      expect(harness.session[:messages][1]['text']).to eq('old B')
    end

    it 'keeps the interrupted marker when the LAST piece was interrupted' do
      harness.session[:messages] = [
        { 'role' => 'assistant', 'text' => 'first part' },
        { 'role' => 'assistant', 'text' => 'cut off', 'interrupted' => true }
      ]
      state = { canon_start: 0 }

      harness.send(:sts_merge_conversation_fragments!, harness.session, state)

      expect(harness.session[:messages].first['interrupted']).to be true
    end

    it 'reports false when the span is already alternating' do
      harness.session[:messages] = [
        { 'role' => 'user', 'text' => 'q' },
        { 'role' => 'assistant', 'text' => 'a' }
      ]
      state = { canon_start: 0 }

      expect(harness.send(:sts_merge_conversation_fragments!, harness.session, state)).to be false
    end

    # Review round 4, P2: an unrecorded span must mean NO span. Defaulting
    # nil to 0 claimed the whole canon — a stray STS_STOP against a bridge
    # that never saw STS_START would have folded the loaded history.
    it 'treats a missing canon_start as no span (never folds the whole canon)' do
      harness.session[:messages] = [
        { 'role' => 'user', 'text' => 'old A' },
        { 'role' => 'user', 'text' => 'old B' }
      ]

      changed = harness.send(:sts_merge_conversation_fragments!, harness.session, {})

      expect(changed).to be false
      expect(harness.session[:messages].length).to eq(2)
    end

    it 'reports false for an empty span (Start then immediate Stop)' do
      harness.session[:messages] = [{ 'role' => 'user', 'text' => 'earlier' }]
      state = { canon_start: 1 }

      expect(harness.send(:sts_merge_conversation_fragments!, harness.session, state)).to be false
    end
  end

  # Review round 4, P1: replacing the canon (import / LOAD) while a bridge
  # is live must tear the bridge down — otherwise its merge span points into
  # the OLD canon and Stop folds the imported history.
  describe 'teardown from non-WebSocket contexts' do
    it 'exposes a class-method teardown for the HTTP import route' do
      task = double('task', finished?: false, stop: nil)
      sess = { _sts: { cmd_queue: Async::Queue.new, bridge_task: task,
                       ready: Async::Condition.new } }

      Sync { WebSocketHelper.teardown_sts_session_for(sess) }

      expect(sess[:_sts]).to be_nil
      expect(task).to have_received(:stop)
    end
  end

  # P2-1 (review finding): RESET clears the canon, so a live bridge must not
  # survive it — it would keep the upstream socket (and billing) alive and
  # keep speaking into a conversation that no longer exists.
  describe 'RESET tears down a live bridge' do
    it 'removes session[:_sts] and reports stopped' do
      task = double('task', finished?: false, stop: nil)
      harness.session[:_sts] = { cmd_queue: Async::Queue.new, bridge_task: task,
                                 ready: Async::Condition.new, turn: nil }

      Sync { harness.send(:handle_ws_reset, harness.session) }

      expect(harness.session[:_sts]).to be_nil
      expect(sent).to include({ 'type' => 'sts_session', 'state' => 'stopped' })
    end

    it 'does not emit sts_session traffic when no bridge exists' do
      Sync { harness.send(:handle_ws_reset, harness.session) }

      expect(sent.map { |m| m['type'] }).not_to include('sts_session')
    end
  end

  describe 'reader VAD events' do
    def run_reader(events, state)
      conn = Class.new do
        def initialize(frames) = @frames = frames
        def read = @frames.shift
        def write(_b); end
        def flush; end
      end.new(events.map(&:to_json))
      Sync do
        harness.sts_reader_loop(conn, state, 'sid')
        # Disarm the current turn's gate-timeout timer: Sync waits for all
        # child tasks, so an armed 5s timer both slows every example AND
        # fires sts_open_gate after the frames ended, corrupting gate-state
        # assertions.
        timer = state[:turn] && state[:turn][:gate_timer]
        if timer
          timer.stop
          state[:turn][:gate_timer] = nil
        end
      end
    end

    let(:base_state) do
      { session_ready: true, ready: Async::Condition.new, turn: nil,
        cmd_queue: Async::Queue.new }
    end

    it 'opens a turn and relays speech_started' do
      run_reader([{ type: 'input_audio_buffer.speech_started' }], base_state)

      expect(base_state[:turn]).not_to be_nil
      expect(sent).to include({ 'type' => 'sts_vad', 'event' => 'speech_started' })
    end

    it 'relays speech_stopped' do
      run_reader([{ type: 'input_audio_buffer.speech_stopped' }], base_state)

      expect(sent).to include({ 'type' => 'sts_vad', 'event' => 'speech_stopped' })
    end

    # Native barge-in: the user talks over the assistant. Upstream will cancel
    # the response, but its event arrives after speech_started has replaced
    # state[:turn] — so the interrupted card must be finalized here, while the
    # old turn is still in hand.
    it 'finalizes the interrupted assistant turn at speech_started (barge-in)' do
      old_turn = { id: 'old', assistant_transcript: +'I was saying', assistant_finalized: false,
                   cancel_notified: false, gate_timer: nil, pending_fragments: [],
                   gate_open: true, user_partial: +'', user_msg_ref: nil,
                   response_id: 'resp-old', spoken_response_ids: { 'resp-old' => true } }
      state = base_state.merge(turn: old_turn, responses: { 'resp-old' => old_turn })

      run_reader([{ type: 'input_audio_buffer.speech_started' }], state)

      types = sent.map { |m| m['type'] }
      expect(types).to include('html')                # interrupted card
      expect(types).to include('sts_audio_cancelled')
      cancelled = sent.find { |m| m['type'] == 'sts_audio_cancelled' }
      expect(cancelled['turn_id']).to eq('old')
      expect(state[:turn][:id]).not_to eq('old')      # fresh turn opened
    end

    # P1-2 (review finding): the gate is open only after the user's stt card
    # has been delivered, but a barge-in can land while transcription still
    # lags. Gate state must not decide whether the interrupted card exists.
    it 'finalizes at speech_started even when the order gate is still closed' do
      old_turn = { id: 'old', assistant_transcript: +'gated words', assistant_finalized: false,
                   cancel_notified: false, gate_timer: nil, pending_fragments: ['gated words'],
                   gate_open: false, user_partial: +'', user_msg_ref: nil,
                   response_id: 'resp-old', spoken_response_ids: { 'resp-old' => true } }
      state = base_state.merge(turn: old_turn, responses: { 'resp-old' => old_turn })

      run_reader([{ type: 'input_audio_buffer.speech_started' }], state)

      types = sent.map { |m| m['type'] }
      expect(types).to include('html')
      expect(types).to include('sts_audio_cancelled')
      expect(old_turn[:assistant_finalized]).to be true
    end

    # Double-speech edge: two speech_started with no response in between. The
    # first turn never had a response, so there is no audio to cancel — and a
    # cancelled notice for it would make the client discard audio the turn
    # never gets.
    it 'does not notify cancelled for a turn that never had a response' do
      run_reader([{ type: 'input_audio_buffer.speech_started' },
                  { type: 'input_audio_buffer.speech_started' }], base_state)

      expect(sent.map { |m| m['type'] }).not_to include('sts_audio_cancelled')
    end

    # Review P2-1: a spontaneous response.create (greeting) races the user's
    # first utterance — its response.created can arrive AFTER speech_started
    # replaced state[:turn], and binding to the current turn would address
    # the greeting's audio/done/cancelled to the wrong turn.
    it 'binds a correlated response to the turn that requested it' do
      state = base_state
      greet_turn = { id: 'greet', assistant_transcript: +'', assistant_finalized: false,
                     cancel_notified: false, gate_timer: nil, pending_fragments: [],
                     gate_open: true, user_partial: +'', user_msg_ref: nil }
      state[:turn] = greet_turn
      state[:pending_response_turn] = greet_turn

      run_reader([{ type: 'input_audio_buffer.speech_started' },
                  { type: 'response.created', response: { id: 'resp-greet' } }], state)

      expect(state[:responses]['resp-greet']).to equal(greet_turn)
      expect(state[:responses]['resp-greet']).not_to equal(state[:turn])
      expect(state[:pending_response_turn]).to be_nil
    end

    # P1-1 (review finding, barge-in killer): upstream's response.cancelled
    # arrives AFTER speech_started has replaced state[:turn]. Attributing it
    # to the current turn sent sts_audio_cancelled with the NEW turn's id, and
    # the client then discarded that turn's audio forever. Response-scoped
    # events resolve their turn through the response_id map instead.
    it 'attributes a late response.cancelled to the OLD turn, not the new one' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'response.output_audio_transcript.delta', response_id: 'resp-1',
                    delta: 'first answer' },
                  { type: 'input_audio_buffer.speech_started' },
                  { type: 'response.cancelled', response_id: 'resp-1' }], state)

      cancelled = sent.select { |m| m['type'] == 'sts_audio_cancelled' }
      expect(cancelled.map { |m| m['turn_id'] }.uniq.size).to eq(1)
      expect(cancelled.first['turn_id']).not_to eq(state[:turn][:id])
    end

    it 'routes late audio deltas to their own turn id after a barge-in swap' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'input_audio_buffer.speech_started' },
                  { type: 'response.output_audio.delta', response_id: 'resp-1', delta: 'QUJD' }],
                 state)

      delta = sent.find { |m| m['type'] == 'sts_audio_delta' }
      expect(delta['turn_id']).not_to eq(state[:turn][:id]) # old turn's id, so the
      # client's cancelled-set (keyed by old id) can discard it
    end

    # Review P2-2: utterance A's transcription.completed can arrive after
    # utterance B's speech_started. Opening B's order gate with A's
    # completed would let B's assistant fragments out before B's own user
    # card — the exact inversion the gate exists to prevent.
    it 'does not open the new turn gate with the previous utterance completed' do
      state = base_state
      run_reader([{ type: 'input_audio_buffer.speech_started' },
                  { type: 'conversation.item.input_audio_transcription.delta',
                    item_id: 'item-A', delta: 'first utterance' },
                  { type: 'input_audio_buffer.speech_started' },
                  { type: 'conversation.item.input_audio_transcription.completed',
                    item_id: 'item-A', transcript: 'first utterance' }], state)

      expect(state[:turn][:gate_open]).to be false
      # A's user card still goes out
      user_cards = sent.select { |m| m['type'] == 'html' && m.dig('content', 'role') == 'user' }
      expect(user_cards.size).to eq(1)
    end

    # P2-4: a cancelled response can emit BOTH response.cancelled and a
    # response.done — one accounting message per response, and the late
    # transcript.done must not re-emit a card over the interrupted one.
    # THE GA cancel path (live-probed 2026-08-01): no response.cancelled
    # event exists — cancellation arrives ONLY as response.done with
    # status="cancelled". The interrupted card and the client-side audio
    # discard must both come from this event.
    it 'treats response.done(status=cancelled) as the cancellation signal' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'response.output_audio.delta', response_id: 'resp-1', delta: 'QUJD' },
                  { type: 'response.output_audio_transcript.delta', response_id: 'resp-1',
                    delta: 'partial words' },
                  { type: 'response.done',
                    response: { id: 'resp-1', status: 'cancelled', usage: {} } }], state)

      types = sent.map { |m| m['type'] }
      expect(types).to include('sts_audio_cancelled')
      card = sent.find { |m| m['type'] == 'html' }
      expect(card['content']['interrupted']).to be true
      expect(sent.count { |m| m['type'] == 'sts_audio_done' }).to eq(1)
    end

    it 'sends exactly one sts_audio_done per response' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'response.done', response: { id: 'resp-1', usage: {} } },
                  { type: 'response.done', response: { id: 'resp-1', usage: {} } }], state)

      expect(sent.count { |m| m['type'] == 'sts_audio_done' }).to eq(1)
    end

    it 'does not re-emit a card when transcript.done follows a finalized turn' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'response.output_audio.delta', response_id: 'resp-1', delta: 'QUJD' },
                  { type: 'response.output_audio_transcript.delta', response_id: 'resp-1',
                    delta: 'partial' },
                  { type: 'input_audio_buffer.speech_started' },
                  { type: 'response.output_audio_transcript.done', response_id: 'resp-1',
                    transcript: 'partial answer full text' }], state)

      cards = sent.select { |m| m['type'] == 'html' }
      expect(cards.size).to eq(1) # only the interrupted card from the barge-in
    end

    # Audio deltas run ahead of transcript deltas, so the interrupted card
    # freezes mid-word while the heard audio ran further (dogfood round 5).
    # The late transcript.done refreshes the card body in place.
    it 'updates the interrupted card text from the late transcript.done' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'response.output_audio.delta', response_id: 'resp-1', delta: 'QUJD' },
                  { type: 'response.output_audio_transcript.delta', response_id: 'resp-1',
                    delta: 'partial answ' },
                  { type: 'input_audio_buffer.speech_started' },
                  { type: 'response.output_audio_transcript.done', response_id: 'resp-1',
                    transcript: 'partial answer, full sentence.' }], state)

      card = sent.find { |m| m['type'] == 'html' }
      update = sent.find { |m| m['type'] == 'sts_card_text' }
      expect(update).not_to be_nil
      expect(update['mid']).to eq(card['content']['mid'])
      expect(update['content']).to eq('partial answer, full sentence.')
      # The canonical message text follows too
      msg = harness.session[:messages].find { |m| m['mid'] == card['content']['mid'] }
      expect(msg['text']).to eq('partial answer, full sentence.')
    end

    # Review P2-3: a barge-in before any transcript arrived leaves nothing
    # to put on a card, but the turn IS interrupted — the late
    # transcript.done must carry the interrupted marker, not masquerade as
    # a completed turn. (The model DID speak — audio ran ahead of the
    # transcript — so under §39 the card exists and carries the marker.)
    it 'marks the late-done card interrupted when the barge-in preceded any transcript' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'response.output_audio.delta', response_id: 'resp-1', delta: 'QUJD' },
                  { type: 'input_audio_buffer.speech_started' },
                  { type: 'response.output_audio_transcript.done', response_id: 'resp-1',
                    transcript: 'what the model had generated' }], state)

      card = sent.find { |m| m['type'] == 'html' }
      expect(card).not_to be_nil
      expect(card['content']['interrupted']).to be true
    end

    it 'ignores a stale transcript that is a prefix of the frozen text' do
      state = base_state
      run_reader([{ type: 'response.created', response: { id: 'resp-1' } },
                  { type: 'response.output_audio_transcript.delta', response_id: 'resp-1',
                    delta: 'the full text already' },
                  { type: 'input_audio_buffer.speech_started' },
                  { type: 'response.output_audio_transcript.done', response_id: 'resp-1',
                    transcript: 'the full' }], state)

      # A prefix of what's already shown is strictly older information —
      # the card stays untouched (§37-11: it never shrinks, either).
      expect(sent.select { |m| m['type'] == 'sts_card_text' }).to be_empty
    end

    # The client's fragment handler repositions the streaming temp-card only
    # on is_first — STS fragments without it left the in-progress assistant
    # card stranded above newer user cards (dogfood round 6).
    it 'stamps is_first on the first fragment of each turn only' do
      state = base_state
      turn = { id: 't', assistant_transcript: +'', assistant_finalized: false,
               cancel_notified: false, gate_timer: nil, pending_fragments: [],
               gate_open: true, user_partial: +'', user_msg_ref: nil }
      state[:turn] = turn
      run_reader([{ type: 'response.output_audio_transcript.delta', delta: 'Hello ' },
                  { type: 'response.output_audio_transcript.delta', delta: 'there.' }], state)

      frags = sent.select { |m| m['type'] == 'fragment' }
      expect(frags.length).to eq(2)
      expect(frags[0]['is_first']).to be true
      expect(frags[1]).not_to have_key('is_first')
    end

    it 'reports started on session.updated (single source, covers reconnect)' do
      run_reader([{ type: 'session.updated' }], base_state)

      expect(sent).to include({ 'type' => 'sts_session', 'state' => 'started' })
    end

    it 'opens a turn on response.created only when none exists' do
      run_reader([{ type: 'response.created' }], base_state)
      first = base_state[:turn]
      expect(first).not_to be_nil

      run_reader([{ type: 'response.created' }], base_state)
      expect(base_state[:turn]).to equal(first)
    end
  end
end

# xAI dialect (all shapes live-probed 2026-08-01). The turn machinery is
# shared; what the profile encapsulates is connection facts, the session
# payload shape, the cumulative transcription event, the fatal
# model-mismatch guard (silent fallback to think-fast-1.0) and per-minute
# accounting.
RSpec.describe 'xAI realtime provider profile' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session

      public :build_sts_session_update_payload, :sts_provider_for, :sts_usage_accounting
      def get_session_params = {}
      def sync_session_state!; end
    end.new
  end

  it 'routes grok-* models to the xai profile, everything else to openai' do
    expect(harness.sts_provider_for('grok-voice-think-fast-2.0')).to eq('xai')
    expect(harness.sts_provider_for('grok-voice-latest')).to eq('xai')
    expect(harness.sts_provider_for('gpt-realtime-2.1')).to eq('openai')
  end

  it 'declares xAI connection facts (URL, key env, voices, fatal mismatch)' do
    profile = WebSocketHelper::STS_PROVIDER_PROFILES['xai']
    expect(profile[:url]).to eq('wss://api.x.ai/v1/realtime')
    expect(profile[:api_key_env]).to eq('XAI_API_KEY')
    # 26 IDs (5 original + 21 added 2026-07), validated against TTS REST
    # 2026-08-01. The profile list is the fallback for model_spec sts_voices.
    expect(profile[:voices].size).to eq(26)
    expect(profile[:voices]).to include('eve', 'ara', 'rex', 'sal', 'leo', 'luna', 'atlas')
    expect(profile[:model_mismatch_fatal]).to be true
  end

  describe 'session.update payload (xAI shape, live-probed 2026-08-01)' do
    let(:payload) do
      stub_const('APPS', {})
      harness.build_sts_session_update_payload(
        { provider: 'xai', model: 'grok-voice-think-fast-2.0', voice: 'eve',
          instructions: 'Be brief.', language: 'ja' }
      )
    end
    let(:session_cfg) { payload[:session] }

    it 'puts voice and turn_detection at session level (no realtime type / output_modalities)' do
      expect(session_cfg[:voice]).to eq('eve')
      expect(session_cfg[:turn_detection][:type]).to eq('server_vad')
      expect(session_cfg).not_to have_key(:type)
      expect(session_cfg).not_to have_key(:output_modalities)
    end

    it 'requests auto response + barge-in explicitly (xAI defaults are off)' do
      expect(session_cfg[:turn_detection][:create_response]).to be true
      expect(session_cfg[:turn_detection][:interrupt_response]).to be true
    end

    it 'pins 24kHz PCM on both directions and passes the language hint (BCP-47)' do
      expect(session_cfg.dig(:audio, :input, :format)).to eq({ type: 'audio/pcm', rate: 24_000 })
      expect(session_cfg.dig(:audio, :output, :format)).to eq({ type: 'audio/pcm', rate: 24_000 })
      expect(session_cfg.dig(:audio, :input, :transcription, :language_hint)).to eq('ja')
    end

    it 'appends the same language directive as the typed pipeline' do
      expect(session_cfg[:instructions]).to start_with('Be brief.')
      expect(session_cfg[:instructions]).to include('Japanese')
    end

    it 'carries no tools key by default (tools are opt-in)' do
      expect(session_cfg).not_to have_key(:tools)
    end

    it 'never injects the removed native search entries (2026-08-03, user decision)' do
      on = harness.build_sts_session_update_payload(
        { provider: 'xai', model: 'grok-voice-think-fast-2.0', voice: 'eve',
          instructions: '', websearch: true } # legacy state key is ignored
      )
      tools = on.dig(:session, :tools)
      expect(tools).to be_nil
    end

    it 'omits the language hint in auto mode' do
      stub_const('APPS', {})
      p2 = harness.build_sts_session_update_payload(
        { provider: 'xai', voice: 'eve', instructions: '', language: 'auto' }
      )
      expect(p2.dig(:session, :audio, :input)).not_to have_key(:transcription)
    end

    it 'validates VAD tuning against xAI ranges' do
      app = double('app', settings: { sts_vad_threshold: 0.05,   # below 0.1 → dropped
                                      sts_vad_silence_ms: 20_000 }) # above 10s → dropped
      stub_const('APPS', { 'LiveConversationGrok' => app })
      harness2 = Class.new do
        include WebSocketHelper
        public :build_sts_session_update_payload
        def get_session_params = { 'app_name' => 'LiveConversationGrok' }
      end.new
      p3 = harness2.build_sts_session_update_payload(
        { provider: 'xai', voice: 'eve', instructions: '', language: 'auto' }
      )
      td = p3.dig(:session, :turn_detection)
      expect(td).not_to have_key(:threshold)
      expect(td).not_to have_key(:silence_duration_ms)
    end
  end

  describe 'per-minute accounting (usage is empty on xAI)' do
    it 'estimates cost from wall clock between accounting marks' do
      state = { provider: 'xai',
                billing_mark: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 120 }
      acct = harness.sts_usage_accounting({}, state)

      expect(acct[:billing_basis]).to eq('per_minute')
      expect(acct[:estimated_cost_usd]).to be_within(0.01).of(2 * WebSocketHelper::XAI_STS_RATE_PER_MINUTE)
      expect(acct[:audio_input_tokens]).to eq(0)
    end

    it 'does not touch the OpenAI token-based path' do
      acct = harness.sts_usage_accounting(
        { 'input_token_details' => { 'audio_tokens' => 1_000_000 } },
        { provider: 'openai' }
      )
      expect(acct[:audio_input_tokens]).to eq(1_000_000)
      expect(acct).not_to have_key(:billing_basis)
    end
  end
end

RSpec.describe 'xAI dialect in the reader' do
  let(:sent) { [] }
  let(:harness) do
    msgs = sent
    Class.new do
      include WebSocketHelper
      attr_accessor :session

      public :sts_reader_loop
      define_method(:send_or_broadcast) { |json, _sid| msgs << JSON.parse(json) }
      def get_session_params = {}
      def sync_session_state!; end
      def detect_language(_t) = 'en'
    end.new
  end

  before { harness.session = { parameters: {}, messages: [] } }

  def run_reader(events, state)
    conn = Class.new do
      def initialize(frames) = @frames = frames
      def read = @frames.shift
      def write(_b); end
      def flush; end
    end.new(events.map(&:to_json))
    Sync do
      harness.sts_reader_loop(conn, state, 'sid')
      timer = state[:turn] && state[:turn][:gate_timer]
      if timer
        timer.stop
        state[:turn][:gate_timer] = nil
      end
    end
  end

  let(:base_state) do
    { session_ready: true, ready: Async::Condition.new, turn: nil,
      cmd_queue: Async::Queue.new, provider: 'xai', model: 'grok-voice-think-fast-2.0' }
  end

  # xAI sends CUMULATIVE transcripts (.updated), not deltas — appending
  # would duplicate the prefix on every event.
  it 'replaces (not appends) the user partial on transcription.updated' do
    run_reader([{ type: 'input_audio_buffer.speech_started' },
                { type: 'conversation.item.input_audio_transcription.updated',
                  item_id: 'i1', transcript: 'こんにちは' },
                { type: 'conversation.item.input_audio_transcription.updated',
                  item_id: 'i1', transcript: 'こんにちは、今日は' }], base_state)

    partials = sent.select { |m| m['type'] == 'stt_partial' }.map { |m| m['content'] }
    expect(partials).to eq(['こんにちは', 'こんにちは、今日は'])
    expect(base_state[:turn][:user_partial]).to eq('こんにちは、今日は')
  end

  # Live-probed: unknown models silently become think-fast-1.0. Running the
  # conversation on a model the user did not pick is a misrepresentation.
  it 'stops fatally when the session reports a different model' do
    run_reader([{ type: 'session.created',
                  session: { model: 'grok-voice-think-fast-1.0' } }], base_state)

    err = sent.find { |m| m['type'] == 'error' }
    expect(err['content']).to include('silent fallback')
    expect(base_state[:fatal]).to be true
  end

  # Review round 5, P2: without the signal a writer parked in
  # sts_wait_for_ready blocked up to 15s and surfaced a second, misleading
  # "setup timeout" error after the fatal card.
  it 'signals ready and records the session-level fatal memory on mismatch' do
    ready = base_state[:ready]
    signalled = false
    allow(ready).to receive(:signal) { signalled = true }

    run_reader([{ type: 'session.created',
                  session: { model: 'grok-voice-think-fast-1.0' } }], base_state)

    expect(signalled).to be true
    expect(harness.session[:_sts_fatal]).to eq('grok-voice-think-fast-2.0')
  end

  # Review round 5, P3-1: a straggler cumulative update for utterance A must
  # not repaint anything once A's card is final AND the conversation has
  # moved on to turn B.
  it 'ignores late transcription.updated for a finalized PREVIOUS turn' do
    turn_a = { id: 'a', user_partial: +'', user_msg_ref: { 'mid' => 'm' },
               assistant_transcript: +'', gate_open: false, pending_fragments: [],
               assistant_finalized: false, cancel_notified: false, gate_timer: nil }
    turn_b = { id: 'b', user_partial: +'', user_msg_ref: nil,
               assistant_transcript: +'', gate_open: false, pending_fragments: [],
               assistant_finalized: false, cancel_notified: false, gate_timer: nil }
    state = base_state.merge(turn: turn_b, items: { 'item-A' => turn_a })

    run_reader([{ type: 'conversation.item.input_audio_transcription.updated',
                  item_id: 'item-A', transcript: 'stale straggler' }], state)

    expect(sent.select { |m| m['type'] == 'stt_partial' }).to be_empty
    expect(turn_a[:user_partial]).to eq('')
    expect(turn_b[:user_partial]).to eq('')
  end

  # Dogfood (Grok round 1): xAI emits completed REPEATEDLY per utterance
  # with growing cumulative snapshots. One turn owns ONE user message that
  # grows in place — appending each snapshot produced duplicated-paragraph
  # user cards.
  it 'grows one user message in place across repeated completed events' do
    state = base_state
    run_reader([{ type: 'input_audio_buffer.speech_started' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i1', transcript: 'Nothing special.' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i1', transcript: 'Nothing special so far. So good.' }], state)

    user_msgs = harness.session[:messages].select { |m| m['role'] == 'user' }
    expect(user_msgs.length).to eq(1)
    expect(user_msgs.first['text']).to eq('Nothing special so far. So good.')
    update = sent.find { |m| m['type'] == 'sts_card_text' }
    expect(update['content']).to eq('Nothing special so far. So good.')
  end

  # OpenAI dogfood: a continuation utterance whose speech_started went
  # missing resolved to the PREVIOUS turn (user card final) and the grow
  # path dropped its shorter text silently — spoken words vanished from the
  # record. A different-item completed must always produce its own card.
  it 'creates a fresh card for a different-item completed on a spent turn' do
    state = base_state
    run_reader([{ type: 'input_audio_buffer.speech_started' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i1', transcript: 'What do you think of the Odyssey, which has been' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i2', transcript: 'The theme for many films, novels, plays, etc.' }],
               state)

    user_msgs = harness.session[:messages].select { |m| m['role'] == 'user' }
    expect(user_msgs.length).to eq(2)
    expect(user_msgs.last['text']).to eq('The theme for many films, novels, plays, etc.')
    expect(sent.count { |m| m['type'] == 'html' && m.dig('content', 'role') == 'user' }).to eq(2)
  end

  # Trailing-silence hallucinations transcribe as bare punctuation and made
  # empty-looking user cards (dogfood: a card containing just ".").
  it 'suppresses punctuation-only transcripts (no card, empty stt)' do
    state = base_state
    run_reader([{ type: 'input_audio_buffer.speech_started' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i1', transcript: ' . ' }], state)

    expect(harness.session[:messages].select { |m| m['role'] == 'user' }).to be_empty
    expect(sent.select { |m| m['type'] == 'html' }).to be_empty
    expect(sent.find { |m| m['type'] == 'stt' }['content']).to eq('')
  end

  it 'ignores an identical repeated completed (no duplicate card, no update)' do
    state = base_state
    run_reader([{ type: 'input_audio_buffer.speech_started' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i1', transcript: 'Hey, what is up?' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i1', transcript: 'Hey, what is up?' }], state)

    user_msgs = harness.session[:messages].select { |m| m['role'] == 'user' }
    expect(user_msgs.length).to eq(1)
    expect(sent.select { |m| m['type'] == 'sts_card_text' }).to be_empty
  end

  it 'keeps updating the CURRENT turn partial after an intermediate completed' do
    state = base_state
    run_reader([{ type: 'input_audio_buffer.speech_started' },
                { type: 'conversation.item.input_audio_transcription.completed',
                  item_id: 'i1', transcript: 'Nothing special.' },
                { type: 'conversation.item.input_audio_transcription.updated',
                  item_id: 'i1', transcript: 'Nothing special so f' }], state)

    partials = sent.select { |m| m['type'] == 'stt_partial' }.map { |m| m['content'] }
    expect(partials.last).to eq('Nothing special so f')
  end

  it 'accepts the session when the model echo matches' do
    run_reader([{ type: 'session.created',
                  session: { model: 'grok-voice-think-fast-2.0' } }], base_state)

    expect(sent.select { |m| m['type'] == 'error' }).to be_empty
    expect(base_state[:fatal]).to be_nil
  end
end

# Gemini Live dialect (all shapes live-probed 2026-08-01). Gemini is a
# genuinely different protocol (BidiGenerateContent) — the translator maps
# its serverContent stream onto the internal (OpenAI-GA-shaped) event
# vocabulary so the shared turn machinery stays provider-blind.
RSpec.describe 'Gemini Live provider' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session

      public :build_sts_session_update_payload, :sts_translate_events,
             :sts_usage_accounting, :sts_provider_for, :sts_append_frame
      def get_session_params = {}
      def sync_session_state!; end
    end.new
  end

  it 'declares Gemini connection facts (query-key auth, 16kHz input)' do
    profile = WebSocketHelper::STS_PROVIDER_PROFILES['gemini']
    expect(profile[:api_key_env]).to eq('GEMINI_API_KEY')
    expect(profile[:auth]).to eq(:query_key)
    expect(profile[:input_rate]).to eq(16_000)
    expect(profile[:default_voice]).to eq('Kore')
  end

  it 'resolves the provider from the model_spec sts_provider field' do
    expect(harness.sts_provider_for('gemini-3.1-flash-live-preview')).to eq('gemini')
    expect(harness.sts_provider_for('grok-voice-think-fast-2.0')).to eq('xai')
    expect(harness.sts_provider_for('gpt-realtime-2.1')).to eq('openai')
  end

  describe 'setup payload (live-probed shape)' do
    let(:payload) do
      stub_const('APPS', {})
      harness.build_sts_session_update_payload(
        { provider: 'gemini', model: 'gemini-3.1-flash-live-preview',
          voice: 'Kore', instructions: 'Be brief.', language: 'ja' }
      )
    end

    it 'names the model in the setup frame and enables both transcriptions' do
      setup = payload[:setup]
      expect(setup[:model]).to eq('models/gemini-3.1-flash-live-preview')
      expect(setup[:generationConfig][:responseModalities]).to eq(['AUDIO'])
      expect(setup[:generationConfig].dig(:speechConfig, :voiceConfig,
                                          :prebuiltVoiceConfig, :voiceName)).to eq('Kore')
      expect(setup).to have_key(:inputAudioTranscription)
      expect(setup).to have_key(:outputAudioTranscription)
    end

    it 'carries the language directive inside systemInstruction' do
      text = payload.dig(:setup, :systemInstruction, :parts, 0, :text)
      expect(text).to start_with('Be brief.')
      expect(text).to include('Japanese')
    end

    it 'carries no tools key by default (tools are opt-in)' do
      expect(payload[:setup]).not_to have_key(:tools)
    end

    it 'never injects the removed google_search entry (2026-08-03, user decision)' do
      on = harness.build_sts_session_update_payload(
        { provider: 'gemini', model: 'gemini-3.1-flash-live-preview',
          voice: 'Kore', instructions: '', websearch: true } # legacy state key is ignored
      )
      expect(on.dig(:setup, :tools)).to be_nil
    end
  end

  it 'wraps audio chunks in realtimeInput frames with the 16kHz mime' do
    frame = JSON.parse(harness.sts_append_frame({ provider: 'gemini' }, 'QUJD'))
    expect(frame.dig('realtimeInput', 'audio', 'data')).to eq('QUJD')
    expect(frame.dig('realtimeInput', 'audio', 'mimeType')).to eq('audio/pcm;rate=16000')
  end

  describe '#sts_translate_events' do
    let(:state) { { provider: 'gemini', turn: nil } }

    it 'passes non-Gemini payloads through unchanged' do
      raw = { 'type' => 'response.created' }
      expect(harness.sts_translate_events({ provider: 'openai' }, raw)).to eq([raw])
    end

    it 'maps setupComplete to session.updated' do
      events = harness.sts_translate_events(state, { 'setupComplete' => {} })
      expect(events).to eq([{ 'type' => 'session.updated' }])
    end

    it 'opens a turn and emits transcription deltas for user speech' do
      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'inputTranscription' => { 'text' => 'こん' } } }
      )
      expect(events.map { |e| e['type'] }).to eq(
        %w[input_audio_buffer.speech_started conversation.item.input_audio_transcription.delta]
      )
      expect(events.last['delta']).to eq('こん')
    end

    it 'synthesizes user-completed + response.created when the model starts answering' do
      state[:turn] = { assistant_finalized: false, user_msg_ref: nil }
      state[:gem] = { resp_open: false, resp_seq: 0, item_seq: 1, item_id: 'gitem-1', usage: nil }

      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'modelTurn' => { 'parts' => [
          { 'inlineData' => { 'data' => 'QUJD' } }
        ] } } }
      )

      types = events.map { |e| e['type'] }
      expect(types).to eq(%w[input_audio_buffer.speech_stopped
                             conversation.item.input_audio_transcription.completed
                             response.created response.output_audio.delta])
      expect(events[1]['item_id']).to eq('gitem-1')
      expect(events[3]['response_id']).to eq('gresp-1')
    end

    it 'closes the generation on turnComplete with the stashed usage' do
      state[:gem] = { resp_open: true, resp_seq: 1, rid: 'gresp-1', item_seq: 1,
                      item_id: 'gitem-1', usage: { 'promptTokenCount' => 5 } }

      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'turnComplete' => true } }
      )

      expect(events.map { |e| e['type'] }).to eq(
        %w[response.output_audio_transcript.done response.done]
      )
      expect(events.last.dig('response', 'status')).to eq('completed')
      expect(events.last.dig('response', 'usage')).to eq({ 'promptTokenCount' => 5 })
      expect(state[:gem][:resp_open]).to be false
    end

    it 'translates the interrupted flag into the internal cancel shape' do
      state[:gem] = { resp_open: true, resp_seq: 1, rid: 'gresp-1', item_seq: 1,
                      item_id: 'gitem-1', usage: nil }

      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'interrupted' => true } }
      )

      expect(events.length).to eq(1)
      expect(events.first.dig('response', 'status')).to eq('cancelled')
      expect(state[:gem][:resp_open]).to be false
    end

    # Review round 6, P1-1: Gemini keeps delivering the PREVIOUS utterance's
    # transcription after the answer starts. That is NOT barge-in — treating
    # it as one cancelled healthy responses mid-air. Real barge-in announces
    # itself via the interrupted flag.
    it 'does not treat late input transcription during an open generation as barge-in' do
      state[:turn] = { assistant_finalized: false, interrupted: nil, user_msg_ref: { 'mid' => 'm' } }
      state[:gem] = { resp_open: true, resp_seq: 1, rid: 'gresp-1', item_seq: 1,
                      item_id: 'gitem-1', usage: nil }

      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'inputTranscription' => { 'text' => ' tail' } } }
      )

      types = events.map { |e| e['type'] }
      expect(types).not_to include('input_audio_buffer.speech_started')
      expect(types).not_to include('response.done')
      expect(state[:gem][:resp_open]).to be true
    end

    # Review round 6, P1-2: an interrupted turn with an empty transcript
    # never sets assistant_finalized — the interrupted flag must open the
    # next utterance's turn, or utterance B merges into turn A.
    it 'opens a new turn after an interrupted (but not finalized) turn' do
      state[:turn] = { assistant_finalized: false, interrupted: true, user_msg_ref: { 'mid' => 'm' } }
      state[:gem] = { resp_open: false, resp_seq: 1, rid: 'gresp-1', item_seq: 1,
                      item_id: 'gitem-1', usage: nil }

      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'inputTranscription' => { 'text' => 'next utterance' } } }
      )

      expect(events.map { |e| e['type'] }).to include('input_audio_buffer.speech_started')
      expect(events.last['item_id']).to eq('gitem-2')
    end

    # Review round 6, P2: a turn can complete with NO model content (safety
    # filter). The user side must close so the next utterance does not merge
    # into the open turn.
    it 'closes the user turn when turnComplete arrives without any response' do
      state[:turn] = { assistant_finalized: false, interrupted: nil, user_msg_ref: nil }
      state[:gem] = { resp_open: false, resp_seq: 0, item_seq: 1, item_id: 'gitem-1', usage: nil }

      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'turnComplete' => true } }
      )

      expect(events.map { |e| e['type'] }).to eq(
        %w[input_audio_buffer.speech_stopped conversation.item.input_audio_transcription.completed]
      )
      expect(state[:gem][:closed_without_response]).to be true

      follow = harness.sts_translate_events(
        state, { 'serverContent' => { 'inputTranscription' => { 'text' => 'again' } } }
      )
      expect(follow.map { |e| e['type'] }).to include('input_audio_buffer.speech_started')
    end

    it 'attaches the stashed usage to a cancelled generation (log fidelity)' do
      state[:gem] = { resp_open: true, resp_seq: 1, rid: 'gresp-1', item_seq: 1,
                      item_id: 'gitem-1', usage: { 'promptTokenCount' => 7 } }

      events = harness.sts_translate_events(
        state, { 'serverContent' => { 'interrupted' => true } }
      )

      expect(events.first.dig('response', 'usage')).to eq({ 'promptTokenCount' => 7 })
      expect(state[:gem][:usage]).to be_nil
    end
  end

  # Sequence pin from the live probe (2026-08-01): a full healthy turn in
  # probe order, run through the REAL reader so translation and the shared
  # turn machinery are exercised together.
  describe 'probe-order sequence through the reader' do
    let(:sent) { [] }
    let(:seq_harness) do
      msgs = sent
      Class.new do
        include WebSocketHelper
        attr_accessor :session

        public :sts_reader_loop
        define_method(:send_or_broadcast) { |json, _sid| msgs << JSON.parse(json) }
        def get_session_params = {}
        def sync_session_state!; end
        def detect_language(_t) = 'ja'
      end.new
    end

    it 'produces one user card, ordered fragments, and one assistant card' do
      seq_harness.session = { parameters: {}, messages: [] }
      state = { session_ready: true, ready: Async::Condition.new, turn: nil,
                cmd_queue: Async::Queue.new, provider: 'gemini',
                model: 'gemini-3.1-flash-live-preview' }

      frames = [
        { 'setupComplete' => {} },
        { 'serverContent' => { 'inputTranscription' => { 'text' => 'こん' } } },
        { 'serverContent' => { 'inputTranscription' => { 'text' => 'にちは' } } },
        { 'serverContent' => { 'modelTurn' => { 'parts' => [{ 'inlineData' => { 'data' => 'QUJD' } }] } } },
        { 'serverContent' => { 'outputTranscription' => { 'text' => 'そう' } } },
        { 'serverContent' => { 'outputTranscription' => { 'text' => 'ですね!' } } },
        { 'usageMetadata' => { 'promptTokenCount' => 10, 'responseTokenCount' => 4 } },
        { 'serverContent' => { 'turnComplete' => true } }
      ]
      conn = Class.new do
        def initialize(f) = @f = f
        def read = @f.shift
        def write(_b); end
        def flush; end
      end.new(frames.map(&:to_json))
      Sync do
        seq_harness.sts_reader_loop(conn, state, 'sid')
        timer = state[:turn] && state[:turn][:gate_timer]
        timer&.stop
      end

      types = sent.map { |m| m['type'] }
      user_cards = sent.select { |m| m['type'] == 'html' && m.dig('content', 'role') == 'user' }
      asst_cards = sent.select { |m| m['type'] == 'html' && m.dig('content', 'role') == 'assistant' }
      expect(user_cards.length).to eq(1)
      expect(user_cards.first.dig('content', 'text')).to eq('こんにちは')
      expect(asst_cards.length).to eq(1)
      expect(asst_cards.first.dig('content', 'text')).to eq('そうですね!')
      # order gate: the user's stt precedes every assistant fragment
      expect(types.index('stt')).to be < types.index('fragment')
      # audio flows with the synthesized response id's turn
      expect(sent.find { |m| m['type'] == 'sts_audio_delta' }['turn_id']).not_to be_nil
      # accounting is unpriced with the stashed token counts
      done = sent.find { |m| m['type'] == 'sts_audio_done' }
      expect(done['accounting']['billing_basis']).to eq('unpriced')
      expect(done['accounting']['audio_input_tokens']).to eq(10)
    end
  end

  it 'reports token counts unpriced (no fabricated audio rate)' do
    acct = harness.sts_usage_accounting(
      { 'promptTokenCount' => 100, 'responseTokenCount' => 40 },
      { provider: 'gemini' }
    )
    expect(acct[:audio_input_tokens]).to eq(100)
    expect(acct[:audio_output_tokens]).to eq(40)
    expect(acct[:estimated_cost_usd]).to eq(0.0)
    expect(acct[:billing_basis]).to eq('unpriced')
  end
end

# Wire-level tools invariant: whatever the app loader injects into
# settings[:tools], the realtime session config must never carry a tools key
# (Live Conversation is a no-tools app family by design).
RSpec.describe 'STS session config carries no tools' do
  it 'enables near-field input noise reduction (fewer phantom VAD turns)' do
    harness = Class.new do
      include WebSocketHelper
      public :build_sts_session_update_payload
      def get_session_params = {}
    end.new
    payload = harness.build_sts_session_update_payload({ voice: 'marin', instructions: '' })
    expect(payload.dig(:session, :audio, :input, :noise_reduction)).to eq({ type: 'near_field' })
  end

  it 'build_sts_session_update_payload has no tools key (OpenAI: never, even with websearch on)' do
    harness = Class.new do
      include WebSocketHelper
      public :build_sts_session_update_payload
      def get_session_params = {}
    end.new
    payload = harness.build_sts_session_update_payload({ voice: 'marin', instructions: '' })
    expect(payload[:session]).not_to have_key(:tools)
    on = harness.build_sts_session_update_payload({ voice: 'marin', instructions: '', websearch: true })
    expect(on[:session]).not_to have_key(:tools)
  end
end

# Dogfood round 3: the user's conversation-language setting (Japanese) never
# reached the bridge — the transcriber auto-detected Japanese speech as
# Korean, and the assistant drifted Korean → English. The language must pin
# BOTH sides: input transcription and response instructions.
RSpec.describe 'STS session config carries the conversation language' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      public :build_sts_session_update_payload
      def get_session_params = {}
    end.new
  end

  it 'pins the input-transcription language and appends the language directive' do
    payload = harness.build_sts_session_update_payload(
      { voice: 'marin', instructions: 'Be brief.', language: 'ja' }
    )

    expect(payload.dig(:session, :audio, :input, :transcription, :language)).to eq('ja')
    expect(payload.dig(:session, :instructions)).to include('Be brief.')
    expect(payload.dig(:session, :instructions)).to include('Japanese')
  end

  it 'auto mode: no transcription pin, language-matching directive instead' do
    payload = harness.build_sts_session_update_payload(
      { voice: 'marin', instructions: 'Be brief.', language: 'auto' }
    )

    expect(payload.dig(:session, :audio, :input, :transcription)).not_to have_key(:language)
    expect(payload.dig(:session, :instructions)).to include('LANGUAGE MATCHING')
  end
end

RSpec.describe 'STS voice SSOT resolution (model_spec → profile fallback)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :ensure_sts_state!
      def get_session_params = session[:parameters]
    end.new
  end

  before do
    allow(harness).to receive(:run_sts_bridge!)
    allow(Thread.current).to receive(:[]).and_call_original
  end

  def state_for(params_hash)
    harness.session = { parameters: params_hash }
    harness.ensure_sts_state!({})
  end

  it 'sts_voice (LC selector) wins over the legacy tts_voice key' do
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'sts_voice' => 'marin', 'tts_voice' => 'coral' })
    expect(st[:voice]).to eq('marin')
  end

  it 'reads the candidate list from model_spec before the profile constant' do
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property) do |_model, prop|
      next ['alpha'] if prop == 'sts_voices'
      next 'alpha' if prop == 'sts_voice'
      nil
    end
    st = state_for({ 'model' => 'gpt-realtime-2.1' })
    expect(st[:voice]).to eq('alpha')
  end

  it 'falls back to the profile constant when model_spec has no sts_voices' do
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_return(nil)
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'sts_voice' => 'marin' })
    expect(st[:voice]).to eq('marin')
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'sts_voice' => 'not-a-voice' })
    expect(st[:voice]).to eq(WebSocketHelper::REALTIME_STS_DEFAULT_VOICE)
  end

  it 'accepts the expanded xAI voice registry (26) and defaults to eve' do
    st = state_for({ 'model' => 'grok-voice-think-fast-2.0', 'sts_voice' => 'luna' })
    expect(st[:voice]).to eq('luna')
    st = state_for({ 'model' => 'grok-voice-think-fast-2.0', 'sts_voice' => 'bogus' })
    expect(st[:voice]).to eq('eve')
  end

  it 'accepts the expanded Gemini voice registry (30) and defaults to Kore' do
    st = state_for({ 'model' => 'gemini-3.1-flash-live-preview', 'sts_voice' => 'Aoede' })
    expect(st[:voice]).to eq('Aoede')
    st = state_for({ 'model' => 'gemini-3.1-flash-live-preview', 'sts_voice' => 'bogus' })
    expect(st[:voice]).to eq('Kore')
  end
end

RSpec.describe 'STS speed (OpenAI only)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :ensure_sts_state!, :build_sts_session_update_payload
      def get_session_params = session[:parameters]
    end.new
  end

  before do
    allow(harness).to receive(:run_sts_bridge!)
    allow(Thread.current).to receive(:[]).and_call_original
  end

  def state_for(params_hash)
    harness.session = { parameters: params_hash }
    harness.ensure_sts_state!({})
  end

  it 'carries a valid sts_speed for OpenAI into state and the payload' do
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'sts_speed' => '1.25' })
    expect(st[:speed]).to eq(1.25)
    payload = harness.build_sts_session_update_payload(st)
    expect(payload.dig(:session, :audio, :output, :speed)).to eq(1.25)
  end

  it 'clamps out-of-range speed to 0.25-1.5' do
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'sts_speed' => '9.9' })
    expect(st[:speed]).to eq(1.5)
    st = state_for({ 'model' => 'gpt-realtime-2.1', 'sts_speed' => '0.01' })
    expect(st[:speed]).to eq(0.25)
  end

  it 'omits speed entirely for xAI and Gemini (never sent)' do
    st = state_for({ 'model' => 'grok-voice-think-fast-2.0', 'sts_speed' => '1.25' })
    expect(st[:speed]).to be_nil
    st = state_for({ 'model' => 'gemini-3.1-flash-live-preview', 'sts_speed' => '1.25' })
    expect(st[:speed]).to be_nil
  end

  it 'omits speed when unset (no key in the payload output)' do
    st = state_for({ 'model' => 'gpt-realtime-2.1' })
    expect(st[:speed]).to be_nil
    payload = harness.build_sts_session_update_payload(st)
    expect(payload.dig(:session, :audio, :output).key?(:speed)).to be(false)
  end
end

RSpec.describe 'STS voice data consistency (model_spec ↔ profile fallback)' do
  {
    'gpt-realtime-2.1' => 'openai',
    'grok-voice-think-fast-2.0' => 'xai',
    'gemini-3.1-flash-live-preview' => 'gemini'
  }.each do |model, provider|
    it "#{provider}: model_spec sts_voices matches the profile fallback, default is a member" do
      spec_voices = Monadic::Utils::ModelSpec.get_model_property(model, 'sts_voices')
      profile = WebSocketHelper::STS_PROVIDER_PROFILES[provider]

      expect(spec_voices).to be_a(Array)
      expect(spec_voices).to eq(profile[:voices])

      spec_default = Monadic::Utils::ModelSpec.get_model_property(model, 'sts_voice')
      expect(spec_voices).to include(spec_default)
      expect(spec_default).to eq(profile[:default_voice])
    end
  end
end

RSpec.describe 'Gemini session continuity (compression + resumption + goAway)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      public :build_sts_session_update_payload, :sts_translate_gemini
    end.new
  end

  let(:state) { { provider: 'gemini', model: 'gemini-3.1-flash-live-preview',
                  voice: 'Kore', instructions: '', language: 'auto' } }

  it 'adds compression and an empty sessionResumption by default' do
    stub_const('APPS', {})
    payload = harness.build_sts_session_update_payload(state)
    expect(payload.dig(:setup, :contextWindowCompression, :triggerTokens))
      .to eq(WebSocketHelper::STS_GEMINI_COMPRESSION_TRIGGER_TOKENS)
    expect(payload.dig(:setup, :sessionResumption)).to eq({})
  end

  it 'sends the stored handle and marks the attempt when one exists' do
    stub_const('APPS', {})
    st = state.merge(resumption_handle: 'H-123')
    payload = harness.build_sts_session_update_payload(st)
    expect(payload.dig(:setup, :sessionResumption)).to eq({ handle: 'H-123' })
    expect(st[:resume_attempted]).to be(true)
  end

  it 'never sends continuity fields on the OpenAI payload' do
    stub_const('APPS', {})
    payload = harness.build_sts_session_update_payload(
      { provider: 'openai', model: 'gpt-realtime-2.1', voice: 'marin',
        instructions: '', language: 'auto', resumption_handle: 'H-123' }
    )
    expect(payload[:session]).not_to have_key(:contextWindowCompression)
    expect(payload[:session]).not_to have_key(:sessionResumption)
  end

  it 'captures sessionResumptionUpdate into state' do
    harness.sts_translate_gemini(state, { 'sessionResumptionUpdate' => { 'newHandle' => 'H-9', 'resumable' => true } })
    expect(state[:resumption_handle]).to eq('H-9')
  end

  it 'marks resumed+seeded on setupComplete after a resume attempt (skips canon re-seed)' do
    state[:resume_attempted] = true
    harness.sts_translate_gemini(state, { 'setupComplete' => {} })
    expect(state[:resumed]).to be(true)
    expect(state[:seeded]).to be(true)
    expect(state[:resume_attempted]).to be(false)
  end

  it 'sets go_away on a goAway frame without emitting internal events' do
    events = harness.sts_translate_gemini(state, { 'goAway' => { 'timeLeft' => '30s' } })
    expect(state[:go_away]).to be(true)
    expect(events).to be_empty
  end

  it 'drops the handle and the attempt on error (fallback to canon re-seed)' do
    state[:resumption_handle] = 'H-STALE'
    state[:resume_attempted] = true
    harness.sts_translate_gemini(state, { 'error' => { 'message' => 'handle expired' } })
    expect(state[:resumption_handle]).to be_nil
    expect(state[:resume_attempted]).to be(false)
  end
end

RSpec.describe 'xAI payload has no continuity fields (symmetric with the OpenAI pin)' do
  it 'omits contextWindowCompression and sessionResumption even with a handle in state' do
    harness = Class.new do
      include WebSocketHelper
      public :build_sts_session_update_payload
      def get_session_params = {}
    end.new
    stub_const('APPS', {})
    payload = harness.build_sts_session_update_payload(
      { provider: 'xai', model: 'grok-voice-think-fast-2.0', voice: 'eve',
        instructions: '', language: 'auto', resumption_handle: 'H-123' }
    )
    expect(payload[:session]).not_to have_key(:contextWindowCompression)
    expect(payload[:session]).not_to have_key(:sessionResumption)
  end
end

RSpec.describe 'STS function calling (wave 1)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session, :broadcasts
      public :build_sts_session_update_payload, :sts_ga_tools, :sts_gemini_tools, :sts_spawn_tool_execution,
             :sts_handle_tool_call_detected, :sts_send_tool_result,
             :sts_cancel_pending_tools, :sts_translate_gemini,
             :sts_append_tools_guidance
      def get_session_params = session[:parameters]
      def initialize
        @broadcasts = []
      end
      def send_or_broadcast(json, _sid = nil)
        @broadcasts << JSON.parse(json)
      end
      def sync_session_state!; end
    end.new
  end

  def state_for(provider:, tools_enabled: false, model: nil)
    {
      provider: provider,
      model: model || { 'openai' => 'gpt-realtime-2.1', 'xai' => 'grok-voice-think-fast-2.0',
                        'gemini' => 'gemini-3.1-flash-live-preview' }[provider],
      voice: 'alloy', instructions: 'Be brief.', language: 'auto',
      tools_enabled: tools_enabled
    }
  end

  describe 'payload generation' do
    before { stub_const('APPS', {}) }

    it 'openai: no tools key when disabled (no-tools invariant, bit-identical)' do
      payload = harness.build_sts_session_update_payload(state_for(provider: 'openai'))
      expect(payload[:session]).not_to have_key(:tools)
    end

    it 'openai: injects GA function tools when enabled (search_web included)' do
      stub_const('CONFIG', { 'TAVILY_API_KEY' => 'tvly-x' })
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).and_return(false)
      payload = harness.build_sts_session_update_payload(state_for(provider: 'openai', tools_enabled: true))
      tools = payload.dig(:session, :tools)
      expect(tools).not_to be_nil
      names = tools.map { |t| t[:name] }
      expect(names).to include('get_current_time', 'search_web')
      expect(names).not_to include('library_search', 'run_code') # containers down
      expect(tools.first[:type]).to eq('function')
      expect(tools.first[:parameters][:type]).to eq('object')
    end

    it 'xai: one shared toolset — search_web included, no native search entry' do
      stub_const('CONFIG', { 'TAVILY_API_KEY' => 'tvly-x' })
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).and_return(false)
      payload = harness.build_sts_session_update_payload(
        state_for(provider: 'xai', tools_enabled: true)
      )
      tools = payload.dig(:session, :tools)
      types = tools.map { |t| t[:type] }
      # The native web_search/x_search toggle was removed (2026-08-03, user
      # decision): the shared search_web function tool covers web search.
      expect(types).not_to include('web_search', 'x_search')
      names = tools.map { |t| t[:name] }
      expect(names).to include('get_current_time', 'search_web')
    end

    it 'gemini: emits sanitized functionDeclarations, no google_search entry' do
      stub_const('CONFIG', { 'TAVILY_API_KEY' => 'tvly-x' })
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).and_return(false)
      payload = harness.build_sts_session_update_payload(
        state_for(provider: 'gemini', tools_enabled: true)
      )
      tools = payload.dig(:setup, :tools)
      expect(tools.length).to eq(1)
      decls = tools.first[:functionDeclarations]
      names = decls.map { |d| d[:name] }
      expect(names).to include('get_current_time', 'search_web')
    end

    it 'gemini: strips additionalProperties and folds default into the description' do
      stub_const('CONFIG', { 'TAVILY_API_KEY' => 'tvly-x' })
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).and_return(false)
      payload = harness.build_sts_session_update_payload(
        state_for(provider: 'gemini', tools_enabled: true)
      )
      decls = payload.dig(:setup, :tools, 0, :functionDeclarations)
      # Live log 2026-08-03: additionalProperties in parameters is a FATAL
      # setup error (1007 close). The whole tree must be free of it, and of
      # `default` (also unsupported — folded into the description instead).
      json = JSON.generate(decls)
      expect(json).not_to include('additionalProperties')
      expect(json).not_to include('"default"')

      search = decls.find { |d| d[:name] == 'search_web' }
      max_results = search[:parameters][:properties][:max_results]
      expect(max_results[:description]).to include('(default: 5)')
      expect(search[:parameters][:required]).to eq(['query'])
    end

    it 'omits the tools key entirely when nothing is available' do
      stub_const('CONFIG', {})
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).and_return(false)
      payload = harness.build_sts_session_update_payload(state_for(provider: 'openai', tools_enabled: true))
      # only get_current_time needs no container — it IS available
      names = payload.dig(:session, :tools)&.map { |t| t[:name] }
      expect(names).to eq(['get_current_time'])
    end

    it 'appends tool guidance to instructions only when enabled' do
      stub_const('CONFIG', {})
      allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).and_return(false)
      off = harness.build_sts_session_update_payload(state_for(provider: 'openai'))
      expect(off.dig(:session, :instructions)).not_to include('tools available')
      on = harness.build_sts_session_update_payload(state_for(provider: 'openai', tools_enabled: true))
      expect(on.dig(:session, :instructions)).to include('tools available')
    end
  end

  describe 'detection and execution' do
    it 'registers pending and enqueues [:tool_call] with parsed arguments' do
      state = { tools_enabled: true, cmd_queue: Async::Queue.new }
      harness.sts_handle_tool_call_detected(state,
        { 'response_id' => 'r1', 'call_id' => 'call-1', 'name' => 'search_web', 'arguments' => '{"query":"news"}' }, 'ws')
      expect(state[:pending_tool_calls]).to eq({ 'r1' => { 'call-1' => true } })
      type, call = state[:cmd_queue].dequeue
      expect(type).to eq(:tool_call)
      expect(call[:rid]).to eq('r1')
      expect(call[:parsed_arguments]).to eq({ 'query' => 'news' })
    end

    it 'sends function_call_output + response.create on result (GA)' do
      conn = []
      def conn.write(s); (self << s) && true; end
      def conn.flush; true; end
      state = { provider: 'openai', pending_tool_calls: { 'r1' => { 'call-1' => true } } }
      harness.sts_send_tool_result(conn, state, { rid: 'r1', call_id: 'call-1', name: 'get_current_time', output: 'now' }, 'ws')
      frames = conn.map { |f| JSON.parse(f) }
      expect(frames[0].dig('item', 'type')).to eq('function_call_output')
      expect(frames[0].dig('item', 'call_id')).to eq('call-1')
      expect(frames[1]['type']).to eq('response.create')
      expect(state[:pending_tool_calls]).to be_empty
    end

    it 'sends toolResponse on result (Gemini)' do
      conn = []
      def conn.write(s); (self << s) && true; end
      def conn.flush; true; end
      state = { provider: 'gemini', pending_tool_calls: { 'gtc-1' => { 'id-1' => true } } }
      harness.sts_send_tool_result(conn, state, { rid: 'gtc-1', call_id: 'id-1', name: 'get_current_time', output: 'now' }, 'ws')
      frames = conn.map { |f| JSON.parse(f) }
      expect(frames.size).to eq(1)
      expect(frames[0].dig('toolResponse', 'functionResponses', 0, 'id')).to eq('id-1')
      expect(frames[0].dig('toolResponse', 'functionResponses', 0, 'response', 'result')).to eq('now')
    end

    it 'drops results whose call was cancelled' do
      conn = []
      def conn.write(s); (self << s) && true; end
      def conn.flush; true; end
      state = { provider: 'openai', pending_tool_calls: {} }
      harness.sts_send_tool_result(conn, state, { call_id: 'gone', name: 'x', output: 'y' }, 'ws')
      expect(conn).to be_empty
    end

    it 'translates a Gemini toolCall into GA-shape detection events (sequential)' do
      state = {}
      events = harness.sts_translate_gemini(state, {
        'toolCall' => { 'functionCalls' => [
          { 'id' => 'fc1', 'name' => 'get_current_time', 'args' => {} },
          { 'id' => 'fc2', 'name' => 'search_web', 'args' => { 'query' => 'x' } }
        ] }
      })
      expect(events.size).to eq(2)
      expect(events[0]['type']).to eq('response.function_call_arguments.done')
      expect(events[1]['call_id']).to eq('fc2')
      expect(JSON.parse(events[1]['arguments'])).to eq({ 'query' => 'x' })
      # One toolCall frame = one batch (§37-9 P2): all calls share a
      # synthetic response id so their results go back in ONE toolResponse.
      expect(events.map { |e| e['response_id'] }.uniq).to eq(['gtc-1'])
    end

    it 'clears pending tool calls on toolCallCancellation' do
      state = { pending_tool_calls: { 'fc1' => true } }
      harness.sts_translate_gemini(state, { 'toolCallCancellation' => {} })
      expect(state[:pending_tool_calls]).to be_empty
    end

    it 'executes get_current_time end-to-end in a thread and enqueues the result' do
      state = { cmd_queue: Async::Queue.new }
      call = { call_id: 'c1', name: 'get_current_time', parsed_arguments: {} }
      harness.sts_spawn_tool_execution(state, call, 'ws')
      deadline = Time.now + 5
      sleep 0.01 while state[:cmd_queue].empty? && Time.now < deadline
      type, result = state[:cmd_queue].dequeue
      expect(type).to eq(:tool_result)
      expect(result[:call_id]).to eq('c1')
      expect(result[:output]).to include('Current date and time:')
    end
  end
end

RSpec.describe 'STS function calling — audit P1 fixes' do
  it 'the tool host resolves run_code through MonadicApp#run_code (super chain exists)' do
    expect(WebSocketHelper.sts_tool_host.ancestors).to include(MonadicApp)
    host = WebSocketHelper.sts_tool_host.new
    # Validation rejects before super is invoked, but resolution must exist:
    expect(host.run_code(code: '', command: 'ruby', extension: 'rb', session: nil)).to be_a(Hash)
  end

  # The host class must NOT be built at file-load time: this handler loads
  # (via websocket.rb) before app.rb defines MonadicApp, and a load-time
  # subclassing killed `rake server:debug` while every spec stayed green
  # (specs load app.rb first). Pin the lazy shape itself.
  it 'builds the tool host lazily, not at load time' do
    expect(WebSocketHelper).to respond_to(:sts_tool_host)
    expect(defined?(WebSocketHelper::StsToolHost)).to be_nil
  end

  it 'run_code executes through the real chain when the python container is up' do
    skip 'python container not running' unless Monadic::Utils::ContainerDependencies.container_running?(:python)
    host = WebSocketHelper.sts_tool_host.new
    result = host.run_code(code: 'print(1 + 1)', command: 'python', extension: 'py', session: nil)
    expect(result).to be_a(String)
    expect(result).to include('Output: 2')
  end

  it 'captures the session on the reactor side and passes it into the tool thread' do
    captured = nil
    stub_const('WebSocketHelper::STS_TOOLS', {
      'probe_tool' => {
        description: 'probe', parameters: { type: 'object', properties: {} },
        available?: ->(_p, _s) { true },
        call: ->(_args, sess) { captured = sess; 'done' }
      }
    })
    harness = Class.new do
      include WebSocketHelper
      public :sts_spawn_tool_execution
      define_method(:session) { { parameters: { 'app_name' => 'LiveConversationOpenAI' } } }
      define_method(:sync_session_state!) {}
    end.new

    state = { cmd_queue: Async::Queue.new }
    harness.sts_spawn_tool_execution(state, { call_id: 'c1', name: 'probe_tool', parsed_arguments: {} }, 'ws')
    deadline = Time.now + 5
    sleep 0.01 while captured.nil? && Time.now < deadline
    expect(captured).to eq({ parameters: { 'app_name' => 'LiveConversationOpenAI' } })
  end

  it 'guidance includes the untrusted-content rule (§36 rev 5)' do
    expect(WebSocketHelper::STS_TOOLS_GUIDANCE).to include('untrusted content')
    expect(WebSocketHelper::STS_TOOLS_GUIDANCE).to include('never follow instructions')
  end
end

RSpec.describe 'STS tool-use visibility (§37)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :sts_handle_tool_call_detected, :sts_send_tool_result,
             :sts_send_assistant_card
      def get_session_params = { 'app_name' => 'LiveConversationOpenAI' }
      def initialize
        @sent = []
      end
      attr_reader :sent
      def send_or_broadcast(json, _sid = nil)
        @sent << JSON.parse(json)
      end
      def sync_session_state!; end
      def detect_language(_t) = 'en'
      def session
        @session ||= { parameters: { 'app_name' => 'LiveConversationOpenAI' } }
      end
    end.new
  end

  def fake_conn
    writes = []
    w = Object.new
    w.define_singleton_method(:write) { |s| writes << JSON.parse(s); true }
    w.define_singleton_method(:flush) { true }
    [w, writes]
  end

  it 'broadcasts sts_tool_call running on detection (with call_id, §37-12)' do
    harness.session[:_sts] = { tools_enabled: true, cmd_queue: Async::Queue.new }
    state = harness.session[:_sts]
    harness.sts_handle_tool_call_detected(state,
      { 'call_id' => 'c1', 'name' => 'search_web', 'arguments' => '{}' }, 'ws')
    msg = harness.sent.find { |m| m['type'] == 'sts_tool_call' }
    expect(msg).to eq({ 'type' => 'sts_tool_call', 'name' => 'search_web', 'status' => 'running',
                        'call_id' => 'c1' })
  end

  it 'broadcasts done and accumulates tools_used; error output becomes error' do
    conn, _writes = fake_conn
    state = { provider: 'openai',
              pending_tool_calls: { 'r1' => { 'c1' => true, 'c2' => true } },
              cmd_queue: Async::Queue.new }
    harness.session[:_sts] = state
    harness.sts_send_tool_result(conn, state, { rid: 'r1', call_id: 'c1', name: 'get_current_time', output: 'now' }, 'ws')
    harness.sts_send_tool_result(conn, state, { rid: 'r1', call_id: 'c2', name: 'run_code', output: '❌ boom' }, 'ws')
    calls = harness.sent.select { |m| m['type'] == 'sts_tool_call' }
    expect(calls.map { |c| [c['name'], c['status'], c['call_id']] })
      .to eq([['get_current_time', 'done', 'c1'], ['run_code', 'error', 'c2']])
    expect(state[:tools_used_since_card].map { |t| t['status'] }).to eq(%w[done error])
  end

  it 'attaches tools_used to the next assistant card and clears' do
    state = { tools_used_since_card: [{ 'name' => 'get_current_time', 'status' => 'done' }] }
    harness.session[:_sts] = state
    turn = {}
    harness.sts_send_assistant_card(state, turn, 'answer', 'ws', interrupted: false)
    card = harness.sent.find { |m| m['type'] == 'html' }
    expect(card.dig('content', 'tools_used')).to eq([{ 'name' => 'get_current_time', 'status' => 'done' }])
    expect(state[:tools_used_since_card]).to be_empty
    # canon: text untouched by metadata
    expect(card.dig('content', 'text')).to eq('answer')
  end

  it 'does not broadcast or accumulate for a cancelled result' do
    conn, _writes = fake_conn
    state = { provider: 'openai', pending_tool_calls: {}, cmd_queue: Async::Queue.new }
    harness.session[:_sts] = state
    harness.sts_send_tool_result(conn, state, { call_id: 'gone', name: 'x', output: 'y' }, 'ws')
    expect(harness.sent.select { |m| m['type'] == 'sts_tool_call' }).to be_empty
    expect(state[:tools_used_since_card]).to be_nil
  end
end

RSpec.describe 'STS tool-bridged fold (§37-2)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :sts_send_tool_result, :sts_fold_tool_continuation,
             :sts_update_interrupted_card, :sts_handle_assistant_transcript_done,
             :sts_turn_for_response
      def get_session_params = { 'app_name' => 'LiveConversationOpenAI' }
      def initialize
        @sent = []
      end
      attr_reader :sent
      def send_or_broadcast(json, _sid = nil)
        @sent << JSON.parse(json)
      end
      def sync_session_state!; end
      def session
        @session ||= { parameters: { 'app_name' => 'LiveConversationOpenAI' } }
      end
    end.new
  end

  def fake_conn
    w = Object.new
    w.define_singleton_method(:write) { |s| JSON.parse(s); true }
    w.define_singleton_method(:flush) { true }
    w
  end

  it 'marks the CURRENT TURN as the continuation target when a GA tool result resumes' do
    turn = { assistant_finalized: true }
    state = { provider: 'openai',
              pending_tool_calls: { 'r1' => { 'c1' => true } },
              tool_batch_turns: { 'r1' => turn }, turn: turn }
    harness.sts_send_tool_result(fake_conn, state,
                                 { rid: 'r1', call_id: 'c1', name: 'search_web', output: 'results' }, 'ws')
    expect(state[:tool_continuation_turn]).to equal(turn)
  end

  it 'folds the post-tool answer into the bridge card (append + tools_used persist + stream)' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'Let me check…', 'active' => true }
    turn = { assistant_msg: msg, assistant_finalized: true, spoken_response_ids: { 'resp-1' => true } }
    state = { tool_continuation_turn: turn,
              tools_used_since_card: [{ 'name' => 'search_web', 'status' => 'done' }] }
    harness.session[:_sts] = state
    harness.session[:messages] = [msg]

    harness.sts_fold_tool_continuation(state, turn, { 'response_id' => 'resp-1', 'transcript' => 'Tomorrow in Osaka will be sunny.' }, 'ws')

    # §37-3: the continuation starts a NEW paragraph, and each tools_used
    # entry carries `at` = the paragraph index where the tool ran (= the
    # bridge part's paragraph count).
    expect(msg['text']).to eq("Let me check…\n\nTomorrow in Osaka will be sunny.")
    expect(msg['tools_used']).to eq([{ 'name' => 'search_web', 'status' => 'done', 'at' => 1 }])
    out = harness.sent.find { |m| m['type'] == 'sts_card_text' }
    expect(out['content']).to eq(msg['text'])
    expect(out['tools_used']).to eq(msg['tools_used'])
    expect(state[:tool_continuation_turn]).to be_nil
    expect(state[:tools_used_since_card]).to be_empty
    # no new card is created on the fold path
    expect(harness.sent.select { |m| m['type'] == 'html' }).to be_empty
  end

  # A multi-tool chain can fold into the same turn more than once; each
  # fold must UNION into tools_used (an assignment dropped batch one — the
  # earlier tools' badges vanished from the final card).
  it 'unions tools_used across repeated folds of the same turn' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'Checking…', 'active' => true }
    turn = { assistant_msg: msg, assistant_finalized: true, spoken_response_ids: { 'resp-1' => true } }
    state = { tool_continuation_turn: turn,
              tools_used_since_card: [{ 'name' => 'get_current_time', 'status' => 'done' }] }
    harness.session[:_sts] = state
    harness.session[:messages] = [msg]

    harness.sts_fold_tool_continuation(state, turn, { 'response_id' => 'resp-1', 'transcript' => 'It is noon.' }, 'ws')

    state[:tool_continuation_turn] = turn
    state[:tools_used_since_card] = [{ 'name' => 'search_web', 'status' => 'done' }]
    harness.sts_fold_tool_continuation(state, turn, { 'response_id' => 'resp-1', 'transcript' => 'And it is sunny.' }, 'ws')

    expect(msg['text']).to eq("Checking…\n\nIt is noon.\n\nAnd it is sunny.")
    expect(msg['tools_used']).to eq([
      { 'name' => 'get_current_time', 'status' => 'done', 'at' => 1 },
      { 'name' => 'search_web', 'status' => 'done', 'at' => 2 }
    ])
  end

  it 'routes transcript.done to the fold ONLY for the marked turn, else to the replace path' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'bridge', 'active' => true }
    turn = { assistant_msg: msg, assistant_finalized: true, spoken_response_ids: { 'resp-1' => true } }
    state = { tool_continuation_turn: turn,
              tools_used_since_card: [{ 'name' => 'search_web', 'status' => 'done' }] }
    harness.session[:_sts] = state
    harness.session[:messages] = [msg]
    allow(harness).to receive(:sts_turn_for_response).and_return(turn)

    harness.sts_handle_assistant_transcript_done(state, { 'response_id' => 'resp-1', 'transcript' => 'answer' }, 'ws')
    expect(msg['text']).to eq("bridge\n\nanswer")

    # done for a DIFFERENT finalized turn → the interrupted-card path (not
    # the fold). Unrelated content is APPENDED as a new paragraph (§37-11).
    msg2 = { 'mid' => 'm2', 'role' => 'assistant', 'text' => 'x', 'active' => true }
    turn2 = { assistant_msg: msg2, assistant_finalized: true, spoken_response_ids: { 'resp-1' => true } }
    allow(harness).to receive(:sts_turn_for_response).and_return(turn2)
    harness.sts_handle_assistant_transcript_done(state, { 'response_id' => 'resp-1', 'transcript' => 'longer replacement' }, 'ws')
    expect(msg2['text']).to eq("x\n\nlonger replacement")
  end

  # §37-11: one response can carry TWO spoken messages (log 2026-08-03,
  # session 1541a03f). Replace only when the late transcript extends the
  # SAME utterance (starts with the frozen text); an unrelated second
  # message is appended as a new paragraph instead of replacing the first.
  it 'replaces when the late transcript extends the same utterance (prefix)' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'partial answ', 'active' => true }
    turn = { assistant_msg: msg, assistant_finalized: true, spoken_response_ids: { 'resp-1' => true } }
    harness.session[:messages] = [msg]

    harness.sts_update_interrupted_card(turn, { 'response_id' => 'resp-1', 'transcript' => 'partial answer, full sentence.' }, 'ws')

    expect(msg['text']).to eq('partial answer, full sentence.')
    out = harness.sent.find { |m| m['type'] == 'sts_card_text' }
    expect(out['content']).to eq('partial answer, full sentence.')
  end

  it 'appends as a new paragraph when the late transcript is a different message' do
    msg = { 'mid' => 'm1', 'role' => 'assistant',
            'text' => '少しだけ時間がかかるから、夕方以降の天気を調べてから話すね。', 'active' => true }
    turn = { assistant_msg: msg, assistant_finalized: true, spoken_response_ids: { 'resp-1' => true } }
    harness.session[:messages] = [msg]

    harness.sts_update_interrupted_card(turn, { 'response_id' => 'resp-1', 'transcript' => 'どこの天気を知りたいのか教えてもらえる？' }, 'ws')

    expect(msg['text']).to eq("少しだけ時間がかかるから、夕方以降の天気を調べてから話すね。\n\nどこの天気を知りたいのか教えてもらえる？")
    out = harness.sent.find { |m| m['type'] == 'sts_card_text' }
    expect(out['content']).to eq(msg['text'])
    # one turn = one card: no second html card is created
    expect(harness.sent.select { |m| m['type'] == 'html' }).to be_empty
  end

  # A repeated done for the message already appended must not duplicate the
  # paragraph (xAI re-sends the same `.completed` for one item on the input
  # side, so an output-side repeat is not unthinkable).
  it 'does not append the same message twice' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'first message', 'active' => true }
    turn = { assistant_msg: msg, assistant_finalized: true, spoken_response_ids: { 'resp-1' => true } }
    harness.session[:messages] = [msg]

    harness.sts_update_interrupted_card(turn, { 'response_id' => 'resp-1', 'transcript' => 'second message' }, 'ws')
    harness.sts_update_interrupted_card(turn, { 'response_id' => 'resp-1', 'transcript' => 'second message' }, 'ws')

    expect(msg['text']).to eq("first message\n\nsecond message")
  end

  # A continuation that dies with NO transcript (barge-in before any words)
  # must not leave a marker that folds a LATER turn's late transcript into
  # the wrong card: the marker is turn-scoped, so another turn NEVER matches
  # (a bare boolean flag failed exactly this way in audit).
  it 'never folds a different turn even when the marker is still set' do
    bridge_msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'bridge', 'active' => true }
    bridge_turn = { assistant_msg: bridge_msg, assistant_finalized: true }
    other_msg = { 'mid' => 'm2', 'role' => 'assistant', 'text' => 'part', 'active' => true }
    other_turn = { assistant_msg: other_msg, assistant_finalized: true,
                   spoken_response_ids: { 'resp-1' => true } }
    state = { tool_continuation_turn: bridge_turn, tools_used_since_card: [] }
    harness.session[:_sts] = state
    harness.session[:messages] = [bridge_msg, other_msg]
    allow(harness).to receive(:sts_turn_for_response).and_return(other_turn)

    harness.sts_handle_assistant_transcript_done(state, { 'response_id' => 'resp-1', 'transcript' => 'partial words full' }, 'ws')

    expect(other_msg['text']).to eq('partial words full') # replaced, not appended
    expect(bridge_msg['text']).to eq('bridge')            # untouched
  end
end

RSpec.describe 'STS merge preserves tools_used (dogfood: badge vanished)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      public :sts_merge_conversation_fragments!
      def sync_session_state!; end
    end.new
  end

  it 'unions tools_used across folded fragments' do
    sess = { messages: [
      { 'role' => 'user', 'text' => 'q1' },
      { 'role' => 'assistant', 'text' => 'a1', 'tools_used' => [{ 'name' => 'get_current_time', 'status' => 'done' }] },
      { 'role' => 'assistant', 'text' => 'a2', 'tools_used' => [{ 'name' => 'search_web', 'status' => 'done' }] }
    ] }
    state = { canon_start: 0 }
    harness.sts_merge_conversation_fragments!(sess, state)

    expect(sess[:messages].length).to eq(2)
    merged = sess[:messages].last
    expect(merged['text']).to eq("a1\n\na2")
    expect(merged['tools_used'].map { |t| t['name'] }).to eq(%w[get_current_time search_web])
    # §37-3: the folded-in fragment's tool is positioned at the fragment's
    # first paragraph (= the predecessor's paragraph count before the join);
    # the predecessor's own entry keeps whatever it had (header badge only).
    expect(merged['tools_used'][0]).not_to have_key('at')
    expect(merged['tools_used'][1]['at']).to eq(1)
  end

  it 'passes an existing `at` through (fold path) instead of recomputing it' do
    sess = { messages: [
      { 'role' => 'assistant', 'text' => "p1\n\np2",
        'tools_used' => [{ 'name' => 'search_web', 'status' => 'done', 'at' => 1 }] },
      { 'role' => 'assistant', 'text' => 'p3',
        'tools_used' => [{ 'name' => 'get_current_time', 'status' => 'done' }] }
    ] }
    state = { canon_start: 0 }
    harness.sts_merge_conversation_fragments!(sess, state)

    tools = sess[:messages].last['tools_used']
    expect(tools[0]['at']).to eq(1) # fold path value preserved
    expect(tools[1]['at']).to eq(2) # p3 starts at paragraph index 2
  end

  it 'does not add tools_used when no fragment used a tool' do
    sess = { messages: [
      { 'role' => 'assistant', 'text' => 'a1' },
      { 'role' => 'assistant', 'text' => 'a2' }
    ] }
    state = { canon_start: 0 }
    harness.sts_merge_conversation_fragments!(sess, state)
    expect(sess[:messages].last).not_to have_key('tools_used')
  end
end

# §37-8: Gemini input transcription arrives word-separated even for
# Japanese ("でも 最近 あの 辺 って"). The translator normalizes spacing at
# the delta source (drop a space only when one neighbor is CJK and neither
# is a Latin letter), so partials, finals, cards, and history are all clean.
RSpec.describe 'Gemini input transcription spacing (§37-8)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      public :sts_translate_events
    end.new
  end

  # Feed the texts as consecutive inputTranscription events of ONE utterance
  # and return the joined normalized deltas.
  def deltas_for(texts)
    state = { provider: 'gemini', turn: { assistant_finalized: false, interrupted: nil } }
    texts.flat_map do |t|
      harness.sts_translate_events(state, { 'serverContent' => { 'inputTranscription' => { 'text' => t } } })
    end.select { |e| e['type'] == 'conversation.item.input_audio_transcription.delta' }
     .map { |e| e['delta'] }.join
  end

  it 'joins word-separated Japanese' do
    expect(deltas_for(['でも 最近 あの 辺 って'])).to eq('でも最近あの辺って')
  end

  it 'joins digits next to CJK (9 月 / ９ 月)' do
    expect(deltas_for(['9 月'])).to eq('9月')
    expect(deltas_for(['９ 月'])).to eq('９月')
  end

  it 'keeps the space next to Latin letters (Hello 世界 / 世界 Hello)' do
    expect(deltas_for(['Hello 世界'])).to eq('Hello 世界')
    expect(deltas_for(['世界 Hello'])).to eq('世界 Hello')
  end

  it 'keeps English word spacing untouched' do
    expect(deltas_for(['the cat sat'])).to eq('the cat sat')
  end

  it 'removes a space straddling a delta boundary' do
    expect(deltas_for(['でも', ' 最近'])).to eq('でも最近')
  end

  it 'keeps a boundary space between Latin words' do
    expect(deltas_for(['Hello', ' world'])).to eq('Hello world')
  end

  # Gemini opens an English utterance with a leading space (" Hello world").
  # Keeping it would make every English transcript start with whitespace —
  # the CJK rule alone says "keep" here because the right neighbor is Latin.
  it 'drops leading whitespace at the start of an utterance' do
    expect(deltas_for([' Hello world'])).to eq('Hello world')
    expect(deltas_for([' でも 最近'])).to eq('でも最近')
  end

  it 'resets the spacing context at a new utterance' do
    state = { provider: 'gemini', turn: { assistant_finalized: true, interrupted: nil } }
    # Utterance 1 ends with a Latin letter. If the tail leaked into the next
    # utterance, the boundary space would be KEPT (latin neighbor); after a
    # reset the decision sees only the CJK right side and drops it.
    harness.sts_translate_events(state, { 'serverContent' => { 'inputTranscription' => { 'text' => 'Hello' } } })
    events = harness.sts_translate_events(state, { 'serverContent' => { 'inputTranscription' => { 'text' => ' 世界' } } })
    expect(events.map { |e| e['type'] }).to include('input_audio_buffer.speech_started')
    delta = events.find { |e| e['type'] == 'conversation.item.input_audio_transcription.delta' }
    expect(delta['delta']).to eq('世界')
  end
end

# §37-9: one upstream response can carry several function calls; a create
# per result produced two overlapping spoken answers (dogfood, xAI).
RSpec.describe 'STS tool response.create batching (§37-9)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :sts_send_tool_result, :sts_maybe_create_tool_response,
             :sts_create_tool_continuation, :sts_handle_response_done
      def get_session_params = { 'app_name' => 'LiveConversationGrok' }
      def initialize
        @sent = []
      end
      attr_reader :sent
      def send_or_broadcast(json, _sid = nil)
        @sent << JSON.parse(json)
      end
      def sync_session_state!; end
      def session
        @session ||= { parameters: { 'app_name' => 'LiveConversationGrok' } }
      end
    end.new
  end

  def fake_conn
    w = Object.new
    writes = []
    w.define_singleton_method(:write) { |s| writes << JSON.parse(s); true }
    w.define_singleton_method(:flush) { true }
    w.define_singleton_method(:parsed_writes) { writes }
    w
  end

  def creates(conn)
    conn.parsed_writes.select { |w| w['type'] == 'response.create' }
  end

  def outputs(conn)
    conn.parsed_writes.select { |w| w['type'] == 'conversation.item.create' }
  end

  it '(a) sends ONE response.create for a two-call batch, after the last output' do
    conn = fake_conn
    turn = { id: 't1', assistant_finalized: true }
    state = { provider: 'xai', turn: turn,
              tool_batch_turns: { 'rA' => turn },
              pending_tool_calls: { 'rA' => { 'c0' => true, 'c1' => true } } }

    harness.sts_send_tool_result(conn, state, { rid: 'rA', call_id: 'c0', name: 'get_current_time', output: 'noon' }, 'ws')
    expect(outputs(conn).length).to eq(1)
    expect(creates(conn)).to be_empty # first result never creates

    harness.sts_send_tool_result(conn, state, { rid: 'rA', call_id: 'c1', name: 'search_web', output: 'sunny' }, 'ws')
    expect(outputs(conn).length).to eq(2)
    expect(creates(conn).length).to eq(1) # exactly one, after the last
    expect(state[:tool_continuation_turn]).to equal(turn)
  end

  # The exact dogfood P2 path: batch A is still executing when the user
  # barges in and UPSTREAM opens response B with its own call. A flat
  # pending set merged the batches and swallowed B's create (silence).
  it 'interleaved batches each complete and create independently' do
    conn = fake_conn
    turn_a = { id: 'tA', assistant_finalized: true }
    turn_b = { id: 'tB' }
    state = { provider: 'xai', turn: turn_b, # user already moved on
              tool_batch_turns: { 'rA' => turn_a, 'rB' => turn_b },
              pending_tool_calls: { 'rA' => { 'c2' => true }, 'rB' => { 'c3' => true } } }

    # A completes: stale (turn moved to B) → output only, no create.
    harness.sts_send_tool_result(conn, state, { rid: 'rA', call_id: 'c2', name: 'search_web', output: 'old' }, 'ws')
    expect(outputs(conn).length).to eq(1)
    expect(creates(conn)).to be_empty

    # B completes: its OWN turn is current → create fires (no silence).
    harness.sts_send_tool_result(conn, state, { rid: 'rB', call_id: 'c3', name: 'search_web', output: 'new' }, 'ws')
    expect(outputs(conn).length).to eq(2)
    expect(creates(conn).length).to eq(1)
    expect(state[:tool_continuation_turn]).to equal(turn_b)
  end

  it '(b) sends the output but NO create when a new user turn owns the bridge' do
    conn = fake_conn
    batch_turn = { id: 't1', assistant_finalized: true }
    new_turn = { id: 't2' }
    state = { provider: 'xai', turn: new_turn,
              tool_batch_turns: { 'rA' => batch_turn },
              pending_tool_calls: { 'rA' => { 'c1' => true } } }

    harness.sts_send_tool_result(conn, state, { rid: 'rA', call_id: 'c1', name: 'search_web', output: 'sunny' }, 'ws')
    expect(outputs(conn).length).to eq(1)  # protocol still gets the result
    expect(creates(conn)).to be_empty      # but no generation of our own
    expect(state[:tool_continuation_turn]).to be_nil
  end

  it '(c) parks the create while a response is open and flushes it when it closes' do
    conn = fake_conn
    turn = { id: 't1', assistant_finalized: true }
    state = { provider: 'xai', turn: turn,
              tool_batch_turns: { 'rA' => turn },
              pending_tool_calls: { 'rA' => { 'c1' => true } },
              response_open: true, cmd_queue: Async::Queue.new }

    harness.sts_send_tool_result(conn, state, { rid: 'rA', call_id: 'c1', name: 'search_web', output: 'sunny' }, 'ws')
    expect(creates(conn)).to be_empty
    expect(state[:tool_create_debt]).to eq({ 'rA' => true })

    # response.done wakes the writer via the queue…
    harness.sts_handle_response_done(state, { 'response' => { 'id' => 'r9', 'status' => 'completed' } }, 'ws')
    expect(state[:response_open]).to be(false)
    type, rid = state[:cmd_queue].dequeue
    expect([type, rid]).to eq([:tool_create_due, 'rA'])

    # …and the writer branch re-runs the decision, which now creates.
    (state[:tool_create_debt] || {}).delete(rid)
    harness.sts_maybe_create_tool_response(conn, state, rid)
    expect(creates(conn).length).to eq(1)
    expect(state[:tool_continuation_turn]).to equal(turn)
  end

  it 'clears batches, debts, turns, and buffered outputs on cancel (barge-in)' do
    state = { pending_tool_calls: { 'rA' => { 'c1' => true } },
              tool_create_debt: { 'rA' => true },
              tool_batch_turns: { 'rA' => {} },
              gemini_tool_outputs: { 'rA' => [{ id: 'c1' }] } }
    harness.send(:sts_cancel_pending_tools, state)
    expect(state[:pending_tool_calls]).to eq({})
    expect(state[:tool_create_debt]).to eq({})
    expect(state[:tool_batch_turns]).to eq({})
    expect(state[:gemini_tool_outputs]).to eq({})
  end

  it 'gemini: ONE toolResponse frame carrying the whole batch, sent on the last result' do
    conn = fake_conn
    turn = { id: 't1' }
    state = { provider: 'gemini', turn: turn,
              tool_batch_turns: { 'gtc-1' => turn },
              pending_tool_calls: { 'gtc-1' => { 'c0' => true, 'c1' => true } } }

    harness.sts_send_tool_result(conn, state, { rid: 'gtc-1', call_id: 'c0', name: 'get_current_time', output: 'noon' }, 'ws')
    expect(conn.parsed_writes).to be_empty # nothing until the batch completes

    harness.sts_send_tool_result(conn, state, { rid: 'gtc-1', call_id: 'c1', name: 'search_web', output: 'sunny' }, 'ws')
    frames = conn.parsed_writes.select { |w| w['toolResponse'] }
    expect(frames.length).to eq(1)
    responses = frames.first.dig('toolResponse', 'functionResponses')
    expect(responses.map { |r| r['id'] }).to eq(%w[c0 c1])
    expect(state[:gemini_tool_outputs]).to eq({})
  end
end

# §37-13C: fragments and audio deltas carry the upstream response id as
# segment_id so the client's speech highlight can map playback time onto
# text per segment (tool-bridge silence is not covered by any segment).
RSpec.describe 'STS segment ids on fragments and audio deltas (§37-13C)' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_reader :session, :broadcasts
      def initialize
        @session = { parameters: {}, messages: [] }
        @broadcasts = []
      end
      def send_or_broadcast(payload, _sid) = (@broadcasts << JSON.parse(payload))
      def sync_session_state!; end
      def detect_language(_t) = 'en'
    end.new
  end

  def run_reader(events, state)
    conn = Class.new do
      def initialize(frames) = @frames = frames
      def read = @frames.shift
      def write(_b); end
      def flush; end
    end.new(events.map(&:to_json))
    Sync { host.send(:sts_reader_loop, conn, state, "sid") }
  end

  def bare_turn(gate_open: true)
    { id: 't1', user_partial: +'', assistant_transcript: +'', gate_open: gate_open,
      pending_fragments: [], user_msg_ref: nil, assistant_finalized: false,
      cancel_notified: false, gate_timer: nil }
  end

  it 'marks fragments and audio deltas with the response segment id' do
    turn = bare_turn
    state = { turn: turn, responses: { 'resp-1' => turn } }
    run_reader([
      { type: 'response.output_audio_transcript.delta', response_id: 'resp-1', delta: 'Hello. ' },
      { type: 'response.output_audio.delta', response_id: 'resp-1', delta: 'QUJD' }
    ], state)

    frag = host.broadcasts.find { |m| m['type'] == 'fragment' }
    expect(frag['segment_id']).to eq('resp-1')
    audio = host.broadcasts.find { |m| m['type'] == 'sts_audio_delta' }
    expect(audio['segment_id']).to eq('resp-1')
  end

  it 'keeps the segment id through the order gate buffer' do
    turn = bare_turn(gate_open: false)
    state = { turn: turn, responses: { 'resp-1' => turn } }
    run_reader([
      { type: 'response.output_audio_transcript.delta', response_id: 'resp-1', delta: 'Held. ' }
    ], state)
    expect(host.broadcasts.none? { |m| m['type'] == 'fragment' }).to be(true)

    host.send(:sts_open_gate, turn, 'sid', reason: 'test')
    frag = host.broadcasts.find { |m| m['type'] == 'fragment' }
    expect(frag['segment_id']).to eq('resp-1')
  end
end

# §39: a transcript fragment can exist without a single audio frame (the
# model's cut-off thought — the log shows audio_out=0). A response that was
# never heard must never become a card; the card must match what was
# actually said. The marker is a per-turn SET of response ids with audio.
RSpec.describe 'STS zero-audio responses never become cards (§39)' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_reader :session, :broadcasts
      public :sts_finalize_interrupted_turn, :sts_update_interrupted_card, :sts_reader_loop
      def initialize
        @session = { parameters: { 'app_name' => 'LiveConversationOpenAI' }, messages: [] }
        @broadcasts = []
      end
      def send_or_broadcast(payload, _sid) = (@broadcasts << JSON.parse(payload))
      def sync_session_state!; end
      def detect_language(_t) = 'en'
      def get_session_params = session[:parameters]
    end.new
  end

  def run_reader(events, state)
    conn = Class.new do
      def initialize(frames) = @frames = frames
      def read = @frames.shift
      def write(_b); end
      def flush; end
    end.new(events.map(&:to_json))
    Sync { host.sts_reader_loop(conn, state, 'sid') }
  end

  def bare_turn(overrides = {})
    { id: 't1', user_partial: +'', assistant_transcript: +'', gate_open: true,
      pending_fragments: [], user_msg_ref: nil, assistant_finalized: false,
      cancel_notified: false, gate_timer: nil, spoken_response_ids: nil,
      response_id: 'resp-1' }.merge(overrides)
  end

  it '(a/b/c) no card when transcript deltas arrived but no audio frame did' do
    turn = bare_turn(gate_timer: double(stop: nil),
                     assistant_transcript: +'そう言ってく',
                     pending_fragments: [['そう言ってく', 'resp-1']])
    state = { turn: turn, responses: { 'resp-1' => turn } }

    host.sts_finalize_interrupted_turn(state, turn, 'sid')

    # (a) no card…
    expect(host.broadcasts.none? { |m| m['type'] == 'html' }).to be(true)
    # (b) …but the turn is still marked interrupted (no dressing up later)
    expect(turn[:interrupted]).to be(true)
    # (c) and the gate state is cleared FIRST, so nothing leaks into the
    # next turn's card
    expect(turn[:gate_timer]).to be_nil
    expect(turn[:pending_fragments]).to be_empty
  end

  it 'creates the interrupted card when at least one audio frame arrived (control)' do
    turn = bare_turn(assistant_transcript: +'そう言ってく',
                     spoken_response_ids: { 'resp-1' => true })
    state = { turn: turn, responses: {} }

    host.sts_finalize_interrupted_turn(state, turn, 'sid')

    card = host.broadcasts.find { |m| m['type'] == 'html' }
    expect(card).not_to be_nil
    expect(card.dig('content', 'interrupted')).to be(true)
    expect(card.dig('content', 'text')).to eq('そう言ってく')
  end

  it 'does not append a late transcript from an unspoken response to the card' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'spoken part', 'active' => true }
    turn = bare_turn(assistant_msg: msg, assistant_finalized: true,
                     spoken_response_ids: { 'resp-1' => true })
    host.session[:messages] = [msg]

    host.sts_update_interrupted_card(turn,
      { 'response_id' => 'resp-2', 'transcript' => 'unspoken continuation' }, 'sid')

    expect(msg['text']).to eq('spoken part')
    expect(host.broadcasts.none? { |m| m['type'] == 'sts_card_text' }).to be(true)
  end

  # sts_turn_for_response treats a missing response id as "the current
  # turn". The §39 guard must use the SAME granularity: dropping the update
  # whenever the id is absent would silently disable in-place card
  # extension for any dialect that omits it.
  it 'still extends the card when the event carries no response id but the turn was spoken' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'spoken part', 'active' => true }
    turn = bare_turn(assistant_msg: msg, assistant_finalized: true,
                     spoken_response_ids: { 'resp-1' => true })
    host.session[:messages] = [msg]

    host.sts_update_interrupted_card(turn, { 'transcript' => 'spoken part, extended' }, 'sid')

    expect(msg['text']).to eq('spoken part, extended')
  end

  it 'suppresses an id-less update when the turn never produced audio' do
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'spoken part', 'active' => true }
    turn = bare_turn(assistant_msg: msg, assistant_finalized: true)
    host.session[:messages] = [msg]

    host.sts_update_interrupted_card(turn, { 'transcript' => 'never heard' }, 'sid')

    expect(msg['text']).to eq('spoken part')
  end

  it 'reader path: barge-in after transcript-only deltas produces no card' do
    turn = bare_turn
    state = { session_ready: true, ready: Async::Condition.new, turn: turn,
              responses: { 'resp-1' => turn }, cmd_queue: Async::Queue.new }

    run_reader([
      { type: 'response.output_audio_transcript.delta', response_id: 'resp-1', delta: 'そう言ってく' },
      { type: 'input_audio_buffer.speech_started' },
      { type: 'response.done', response: { id: 'resp-1', status: 'cancelled' } }
    ], state)

    expect(host.broadcasts.none? { |m| m['type'] == 'html' }).to be(true)
    expect(turn[:interrupted]).to be(true)
  end

  it 'reader path: the audio delta itself is what marks the response spoken' do
    turn = bare_turn(assistant_finalized: true)
    state = { session_ready: true, ready: Async::Condition.new, turn: turn,
              responses: { 'resp-1' => turn }, cmd_queue: Async::Queue.new }

    run_reader([
      { type: 'response.output_audio.delta', response_id: 'resp-1', delta: 'QUJD' }
    ], state)

    expect(turn[:spoken_response_ids]).to eq({ 'resp-1' => true })
  end
end

# §40: is_first is turn-scoped, so the first fragment of a tool
# continuation (same turn, NEW response) carried no boundary signal — the
# client could not anchor the paragraph break or the badge. The response-id
# change within a turn IS the tool boundary; the server marks it.
RSpec.describe 'STS tool continuation fragments carry tool_break (§40)' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_reader :broadcasts
      public :sts_send_fragment
      def initialize = @broadcasts = []
      def send_or_broadcast(payload, _sid) = (@broadcasts << JSON.parse(payload))
    end.new
  end

  def fragments = host.broadcasts.select { |m| m['type'] == 'fragment' }

  it 'marks the first fragment of a NEW response within the turn, and only that one' do
    turn = { fragment_sent: false, fragment_rid: nil }
    host.sts_send_fragment(turn, 'bridge a', 'sid', 'resp-1')
    host.sts_send_fragment(turn, 'bridge b', 'sid', 'resp-1')
    host.sts_send_fragment(turn, 'answer a', 'sid', 'resp-2')
    host.sts_send_fragment(turn, 'answer b', 'sid', 'resp-2')

    expect(fragments.map { |f| f['is_first'] }).to eq([true, nil, nil, nil])
    expect(fragments.map { |f| f['tool_break'] }).to eq([nil, nil, true, nil])
  end

  it 'never marks tool_break on the turn-opening fragment even without a prior rid' do
    turn = { fragment_sent: false, fragment_rid: nil }
    host.sts_send_fragment(turn, 'first', 'sid', 'resp-1')
    expect(fragments.first['tool_break']).to be_nil
  end

  it 'a second continuation (multi-tool chain) marks its own boundary too' do
    turn = { fragment_sent: false, fragment_rid: nil }
    host.sts_send_fragment(turn, 'bridge', 'sid', 'resp-1')
    host.sts_send_fragment(turn, 'answer', 'sid', 'resp-2')
    host.sts_send_fragment(turn, 'more', 'sid', 'resp-3')
    expect(fragments.map { |f| f['tool_break'] }).to eq([nil, true, true])
  end
end

# §39 follow-up: the late transcript.done after a zero-audio barge-in must
# not resurrect the response as a card on the done path either.
RSpec.describe 'STS zero-audio late done stays silent (§39 done path)' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_reader :session, :broadcasts
      public :sts_reader_loop
      def initialize
        @session = { parameters: { 'app_name' => 'LiveConversationOpenAI' }, messages: [] }
        @broadcasts = []
      end
      def send_or_broadcast(payload, _sid) = (@broadcasts << JSON.parse(payload))
      def sync_session_state!; end
      def detect_language(_t) = 'en'
      def get_session_params = session[:parameters]
    end.new
  end

  def run_reader(events, state)
    conn = Class.new do
      def initialize(frames) = @frames = frames
      def read = @frames.shift
      def write(_b); end
      def flush; end
    end.new(events.map(&:to_json))
    Sync { host.sts_reader_loop(conn, state, 'sid') }
  end

  it 'barge-in then late transcript.done for a zero-audio response: no card, no flush' do
    turn = { id: 't1', user_partial: +'', assistant_transcript: +'そう言ってく',
             gate_open: false, pending_fragments: [['そう言ってく', 'resp-1']],
             user_msg_ref: nil, assistant_finalized: false, cancel_notified: false,
             gate_timer: nil, spoken_response_ids: nil, response_id: 'resp-1' }
    state = { session_ready: true, ready: Async::Condition.new, turn: turn,
              responses: { 'resp-1' => turn }, cmd_queue: Async::Queue.new }

    run_reader([
      { type: 'input_audio_buffer.speech_started' }, # barge-in: finalize (zero-audio → no card)
      { type: 'response.output_audio_transcript.done', response_id: 'resp-1',
        transcript: 'そう言ってくれてありがとう' }
    ], state)

    expect(host.broadcasts.none? { |m| m['type'] == 'html' }).to be(true)
    expect(host.broadcasts.none? { |m| m['type'] == 'fragment' }).to be(true)
    expect(turn[:pending_fragments]).to be_empty
  end
end

# §39 residual-risk detector: a SPOKEN assistant card emitted before its own
# user card (transcription.completed lag) is logged — observation only, so
# dogfood can measure whether a card-ordering gate is ever worth building.
RSpec.describe 'STS card-before-user-card detector (§39 observation)' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      attr_reader :session, :broadcasts
      public :sts_send_assistant_card
      def initialize
        @session = { parameters: { 'app_name' => 'LiveConversationOpenAI' }, messages: [] }
        @broadcasts = []
      end
      def send_or_broadcast(payload, _sid) = (@broadcasts << JSON.parse(payload))
      def sync_session_state!; end
      def detect_language(_t) = 'en'
      def get_session_params = session[:parameters]
    end.new
  end

  def bare_turn(overrides = {})
    { id: 't1', user_partial: +'', assistant_transcript: +'', gate_open: true,
      pending_fragments: [], user_msg_ref: nil, assistant_finalized: false,
      cancel_notified: false, gate_timer: nil, spoken_response_ids: nil }.merge(overrides)
  end

  def logged_lines
    lines = []
    allow(Monadic::Utils::ExtraLogger).to receive(:log) { |msg, &blk| lines << (blk ? blk.call : msg) }
    yield
    lines.compact
  end

  it 'logs when the user spoke but their card has not been emitted yet' do
    turn = bare_turn(user_partial: +'大丈夫ですから')
    lines = logged_lines do
      host.sts_send_assistant_card({}, turn, 'reply', 'sid', interrupted: false)
    end
    expect(lines.any? { |l| l.include?('assistant card emitted before user card') }).to be(true)
    # Observation only: the card itself still goes out unchanged.
    expect(host.broadcasts.any? { |m| m['type'] == 'html' }).to be(true)
  end

  it 'stays silent on the greeting turn (no user utterance at all)' do
    lines = logged_lines do
      host.sts_send_assistant_card({}, bare_turn, 'greeting', 'sid', interrupted: false)
    end
    expect(lines.none? { |l| l.include?('assistant card emitted before user card') }).to be(true)
  end

  it 'stays silent when the user card already exists' do
    turn = bare_turn(user_partial: +'spoken', user_msg_ref: { 'mid' => 'u1' })
    lines = logged_lines do
      host.sts_send_assistant_card({}, turn, 'reply', 'sid', interrupted: false)
    end
    expect(lines.none? { |l| l.include?('assistant card emitted before user card') }).to be(true)
  end
end

# §39 fold path: a continuation cancelled before its first audio frame
# takes the fold route for its late done (the turn is already finalized).
# The unspoken text must not fold in, but the tool badge stays — the tool
# genuinely ran.
RSpec.describe 'STS fold suppresses unspoken continuation text (§39)' do
  let(:harness) do
    Class.new do
      include WebSocketHelper
      attr_accessor :session
      public :sts_fold_tool_continuation
      def get_session_params = { 'app_name' => 'LiveConversationOpenAI' }
      def initialize
        @sent = []
      end
      attr_reader :sent
      def send_or_broadcast(json, _sid = nil)
        @sent << JSON.parse(json)
      end
      def sync_session_state!; end
      def session
        @session ||= { parameters: { 'app_name' => 'LiveConversationOpenAI' } }
      end
    end.new
  end

  def setup_fold(spoken:)
    msg = { 'mid' => 'm1', 'role' => 'assistant', 'text' => 'Let me check…', 'active' => true }
    turn = { assistant_msg: msg, assistant_finalized: true,
             spoken_response_ids: spoken }
    state = { tool_continuation_turn: turn,
              tools_used_since_card: [{ 'name' => 'search_web', 'status' => 'done' }] }
    harness.session[:_sts] = state
    harness.session[:messages] = [msg]
    [msg, turn]
  end

  it 'suppresses the unspoken text but keeps the tool badge' do
    msg, turn = setup_fold(spoken: { 'resp-1' => true })
    harness.sts_fold_tool_continuation(harness.session[:_sts], turn,
      { 'response_id' => 'resp-2', 'transcript' => 'unspoken answer' }, 'ws')

    expect(msg['text']).to eq('Let me check…') # no unspoken text folded in
    expect(msg['tools_used']).to eq([{ 'name' => 'search_web', 'status' => 'done', 'at' => 1 }])
    out = harness.sent.find { |m| m['type'] == 'sts_card_text' }
    expect(out['content']).to eq('Let me check…')
    expect(out['tools_used']).to eq(msg['tools_used']) # badge still streams
  end

  it 'suppresses everything when nothing was ever spoken (id-less, empty set)' do
    msg, turn = setup_fold(spoken: {})
    harness.session[:_sts][:tools_used_since_card] = [] # no badge to attach either
    harness.sts_fold_tool_continuation(harness.session[:_sts], turn,
      { 'transcript' => 'unspoken answer' }, 'ws')

    expect(msg['text']).to eq('Let me check…')
    expect(msg).not_to have_key('tools_used')
    expect(harness.sent).to be_empty
  end

  it 'folds normally for an id-less done when the turn WAS spoken (resolver parity)' do
    msg, turn = setup_fold(spoken: { 'resp-1' => true })
    harness.sts_fold_tool_continuation(harness.session[:_sts], turn,
      { 'transcript' => 'spoken answer' }, 'ws')

    expect(msg['text']).to eq("Let me check…\n\nspoken answer")
  end
end
