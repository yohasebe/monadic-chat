# frozen_string_literal: true

# Streaming speech-to-speech (STS) bridge to OpenAI's Realtime endpoint.
#
# Unlike audio_stream_handler.rb (transcription-only upstream session), this
# bridge keeps a full duplex realtime session: the client streams mic audio
# up, and the server relays synthesized assistant audio plus transcripts back.
#
# Client → server wire format:
#   { "message": "AUDIO_CHUNK", "content": "<b64 PCM16 mono 24kHz>" }
#   { "message": "AUDIO_COMMIT" }   # end of user turn → commit + response.create
#   { "message": "AUDIO_ABORT" }    # barge-in → response.cancel upstream
# (Same envelope as the STT bridge; the routing layer picks this handler when
# the session model supports speech-to-speech — see #sts_session_capable?.)
#
# Server → client:
#   { "type": "stt_partial", "content": "<accumulated user transcript>" }
#   { "type": "stt", "content": "<final user transcript>", "logprob": null }
#   { "type": "fragment", "content": "<assistant transcript delta>" }
#   { "type": "html", "content": { ...assistant card... } }
#   { "type": "sts_audio_delta", "turn_id": "<id>", "content": "<b64>",
#     "sample_rate": 24000 }
#   { "type": "sts_audio_done", "turn_id": "<id>", "usage": { ... } }
#   { "type": "sts_audio_cancelled", "turn_id": "<id>" }
#   { "type": "error", "content": "<message>" }
#
# UI honesty rule: on upstream error this bridge reports `error` and stops.
# It NEVER silently falls back to the legacy batch pipeline.
#
# Design notes carried over from the STT bridge (Phase 0 spike):
#  * Force HTTP/1.1 ALPN — async-http picks HTTP/2 by default and OpenAI 405s.
#  * Hold AUDIO_CHUNK locally until session.updated arrives, then flush.
#  * The provider session is a rebuildable derivative of session[:messages]
#    (the source of truth); on reconnect the history is re-seeded.

require 'async'
require 'async/queue'
require 'async/condition'
require 'async/semaphore'
require 'async/http/endpoint'
require 'async/websocket/client'
require 'json'
require 'securerandom'
require 'uri'

module WebSocketHelper
  REALTIME_STS_URL = "wss://api.openai.com/v1/realtime"
  REALTIME_STS_DEFAULT_MODEL = "gpt-realtime-2.1"
  REALTIME_STS_DEFAULT_VOICE = "alloy"
  # Voices the realtime API accepts (live-probed 2026-07-31). This is NOT the
  # TTS voice list: reusing params["tts_voice"] verbatim broke session setup
  # for any TTS-only voice ("Invalid value: 'nova'"), and the failure only
  # missed earlier testing because 'coral' happens to exist in both sets.
  REALTIME_STS_VOICES = %w[alloy ash ballad coral echo sage shimmer verse marin cedar].freeze
  # Input-side transcription runs on a dedicated transcribe model so the
  # user transcript (stt_partial / stt) streams independently of the
  # speech-to-speech model's own output.
  REALTIME_STS_TRANSCRIPTION_MODEL = "gpt-4o-transcribe"
  REALTIME_STS_COMMIT_TIMEOUT = 15 # seconds — bound the wait for session.updated
  REALTIME_STS_SAMPLE_RATE = 24_000

  # Order gate: assistant `fragment` messages must not reach the client
  # before the user's final `stt` message (contract §4). Transcript deltas
  # are buffered per turn until input_audio_transcription.completed arrives;
  # if it never does, the gate opens after this timeout so the assistant
  # text is not lost.
  STS_GATE_TIMEOUT = 5 # seconds

  # Upstream reconnect attempts before giving up and surfacing an error.
  STS_MAX_RECONNECTS = 3

  # Instruction sent with response.create for initiate_from_assistant in
  # STS mode: asks the model to open the conversation. The app's system
  # prompt (session instructions) still governs style and language.
  STS_INITIATE_INSTRUCTIONS =
    "Greet the user briefly and start the conversation, following your system instructions.".freeze

  # A reconnected session must live at least this long (with the handshake
  # completed) to count as healthy and reset the reconnect backoff.
  # Resetting on handshake alone would flap forever under conditions that
  # kill the socket right after session.updated (quota, network policy).
  STS_HEALTHY_SESSION_SECONDS = 60

  # Audio token rates used for the per-turn cost ESTIMATE (USD per 1M
  # tokens). NOTE: text tokens inside the same usage object are billed at
  # different (lower) rates, so this is an estimate, not an invoice figure.
  STS_AUDIO_INPUT_RATE_PER_MTOK = 32.0
  STS_AUDIO_OUTPUT_RATE_PER_MTOK = 64.0

  # Cap on concurrent upstream WebSocket connections to OpenAI's Realtime
  # speech-to-speech endpoint. Same rationale as REALTIME_STT_MAX_CONCURRENT:
  # each engaging tab opens its own upstream socket.
  STS_MAX_CONCURRENT = (ENV["STS_MAX_CONCURRENT"] || "4").to_i

  # NOTE on scope: Async::Semaphore is per-process. Falcon currently runs
  # a single worker, so STS_MAX_CONCURRENT is the effective cap. If Falcon
  # ever moves to multi-worker (configure: count > 1), the cluster-wide cap
  # becomes N × STS_MAX_CONCURRENT — divide the configured value down
  # accordingly, or add an out-of-process limiter here.
  def self.sts_semaphore
    @sts_semaphore ||= Async::Semaphore.new(STS_MAX_CONCURRENT)
  end

  # True when the current model supports speech-to-speech.
  # `sess` is the session hash; `obj`, when given, is the inbound audio
  # message and may carry a `chat_model` hint (see route_audio_mode) that
  # takes precedence over the session parameters — the session copy can be
  # stale when the UPDATE_PARAMS broadcast was silently dropped.
  # Duck-typed session access (`respond_to?(:[])`) mirrors
  # BaseVendorHelper#privacy_enabled_for?: production Rack sessions are not
  # Hash subclasses but do support `[]`.
  def sts_session_capable?(sess, obj = nil)
    model = obj.respond_to?(:[]) ? (obj["chat_model"] || obj[:chat_model]) : nil
    if model.to_s.strip.empty? && sess.respond_to?(:[])
      params = sess[:parameters] || sess["parameters"] || {}
      model = params.respond_to?(:[]) ? (params["model"] || params[:model]) : nil
    end
    return false if model.nil? || model.to_s.strip.empty?

    Monadic::Utils::ModelSpec.supports_speech_to_speech?(model)
  rescue StandardError
    # ModelSpec.supports_speech_to_speech? is provided by a parallel
    # workstream; treat its absence (or any spec failure) as "not capable".
    false
  end

  def handle_sts_audio_chunk(_connection, obj)
    state = ensure_sts_state!(obj)
    queue = state[:cmd_queue]
    return unless queue

    queue.enqueue([:append, obj["content"].to_s])
  end

  def handle_sts_audio_commit(_connection, _obj)
    state = session[:_sts]
    unless state && state[:cmd_queue]
      # Same defensive surface as the STT bridge: commit without any prior
      # chunk means the bridge never opened; tell the client so the UI resets.
      forward_sts_error("No audio captured", Thread.current[:websocket_session_id])
      return
    end

    # Fresh turn id per commit; the writer stamps it on the new turn.
    state[:cmd_queue].enqueue([:commit, SecureRandom.hex(8)])
  end

  def handle_sts_audio_abort(_connection, _obj)
    state = session[:_sts]
    return unless state && state[:cmd_queue]

    # Barge-in: do NOT tear the bridge down (the conversation continues);
    # the writer sends response.cancel upstream and the turn is finalized
    # as interrupted. Bump :abort_seq and signal :ready so a commit blocked
    # in sts_wait_for_ready wakes up immediately instead of waiting out the
    # 15s timeout (same fast-abort race as the STT bridge).
    state[:abort_seq] = (state[:abort_seq] || 0) + 1
    state[:ready].signal
    state[:cmd_queue].enqueue([:abort])
  end

  # VAD configuration for the continuous session. Reads optional MDSL feature
  # keys from the app settings so noise-sensitive deployments can tune turn
  # segmentation (our own bench measured babble keeping the default VAD from
  # ever closing a turn). Only explicitly-set keys are sent.
  def sts_vad_config
    cfg = { type: "server_vad" }
    settings = sts_app_settings
    if settings
      { threshold: :sts_vad_threshold,
        prefix_padding_ms: :sts_vad_prefix_ms,
        silence_duration_ms: :sts_vad_silence_ms }.each do |api_key, mdsl_key|
        value = settings[mdsl_key] || settings[mdsl_key.to_s]
        cfg[api_key] = value if value
      end
    end
    cfg
  end

  def sts_app_settings
    params = get_session_params
    app_name = params["app_name"] || params[:app_name]
    return nil unless defined?(APPS) && app_name && APPS[app_name]

    APPS[app_name].settings
  rescue StandardError
    nil
  end

  # Start a Live Conversation session. `greet` asks the assistant to open the
  # conversation (fresh sessions); resumes seed silently and wait listening.
  def handle_sts_start(_connection, obj)
    state = ensure_sts_state!(obj)
    queue = state[:cmd_queue]
    return unless queue

    greet = obj["greet"] == true || obj["greet"] == "true"
    queue.enqueue([:start, greet])
  end

  # Stop a Live Conversation session: finalize any in-flight turn as
  # interrupted (its card carries the transcript so far), notify the client,
  # and tear the bridge down. The next Start rebuilds from session[:messages].
  def handle_sts_stop(_connection, _obj)
    sess = session
    state = sess[:_sts]
    ws_session_id = Thread.current[:websocket_session_id]
    if state && (turn = state[:turn])
      sts_finalize_interrupted_turn(state, turn, ws_session_id)
      sts_notify_cancelled(turn, ws_session_id)
    end
    teardown_sts_session(sess)
    send_or_broadcast({ "type" => "sts_session", "state" => "stopped" }.to_json, ws_session_id)
  end

  # Entry point for initiate_from_assistant in STS mode. Driving the normal
  # pipeline would 404 on a realtime-only model, so the client signals
  # initiation with STS_INITIATE instead; the bridge then asks the model to
  # greet (response.create with instructions). Same defensive surface as a
  # bare commit: with no bridge state there is nothing to do.
  def handle_sts_initiate(_connection, obj)
    state = ensure_sts_state!(obj)
    queue = state[:cmd_queue]
    return unless queue

    # Fresh turn id per initiation; the writer stamps it on the new turn.
    queue.enqueue([:initiate, SecureRandom.hex(8)])
  end

  # Tear down the STS bridge for a session whose client WebSocket has closed.
  # Unlike the STT bridge (which ends with each commit), the STS bridge is
  # long-lived by design — without this the upstream OpenAI socket would
  # outlive the client connection. Safe to call when no bridge exists.
  def teardown_sts_session(sess)
    state = sess[:_sts]
    return unless state

    sess[:_sts] = nil
    state[:ready]&.signal
    begin
      # nil is the writer loop's stop sentinel.
      state[:cmd_queue]&.enqueue(nil)
    rescue StandardError
      nil
    end
    state[:bridge_task]&.stop
  end

  private

  def ensure_sts_state!(obj)
    state = session[:_sts]
    return state if state && state[:cmd_queue] && state[:bridge_task] && !state[:bridge_task].finished?

    params = get_session_params
    hint = obj.respond_to?(:[]) ? (obj["chat_model"] || obj[:chat_model]).to_s : ""
    model = hint.strip.empty? ? (params["model"] || params[:model]).to_s : hint
    model = REALTIME_STS_DEFAULT_MODEL if model.strip.empty?
    voice = (params["tts_voice"] || params[:tts_voice]).to_s
    unless REALTIME_STS_VOICES.include?(voice)
      Monadic::Utils::ExtraLogger.log do
        "[STS] tts_voice #{voice.inspect} is not a realtime voice; using #{REALTIME_STS_DEFAULT_VOICE}"
      end unless voice.strip.empty?
      voice = REALTIME_STS_DEFAULT_VOICE
    end
    instructions = params["initial_prompt"] || params[:initial_prompt]

    state = {
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
    session[:_sts] = state

    ws_session_id = Thread.current[:websocket_session_id]
    state[:bridge_task] = Async do
      run_sts_bridge!(state, ws_session_id)
    end
    state
  end

  def run_sts_bridge!(state, ws_session_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    if api_key.nil? || api_key.empty?
      forward_sts_error("OPENAI_API_KEY is not configured", ws_session_id)
      return
    end

    semaphore = WebSocketHelper.sts_semaphore
    if semaphore.blocking?
      Monadic::Utils::ExtraLogger.log do
        "[STS session=#{ws_session_id}] waiting for upstream WS slot (cap=#{STS_MAX_CONCURRENT})"
      end
    end

    semaphore.acquire do
      Monadic::Utils::ExtraLogger.log do
        "[STS session=#{ws_session_id}] bridge open model=#{state[:model]} voice=#{state[:voice]}"
      end

      attempts = 0
      loop do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          sts_connect_and_run(state, ws_session_id, api_key)
        rescue StandardError => e
          Monadic::Utils::ExtraLogger.log do
            "[STS session=#{ws_session_id}] connection error: #{e.class}: #{e.message}"
          end
        end
        lived = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        # :abort is barge-in and never reaches here (the writer stays in its
        # loop), so any return means the upstream socket went away.
        #
        # Healthy = handshake completed AND the connection actually lived a
        # while: only then does the backoff reset, so a long-lived bridge is
        # not killed by cumulative failures spread over hours. Resetting on
        # handshake alone would loop forever (1s backoff, cap never reached,
        # nothing surfaced) when the socket dies right after session.updated.
        attempts = 0 if state[:session_ready] && lived >= STS_HEALTHY_SESSION_SECONDS
        attempts += 1
        if attempts > STS_MAX_RECONNECTS
          Monadic::Utils::ExtraLogger.log do
            "[STS session=#{ws_session_id}] reconnect attempts exhausted (#{STS_MAX_RECONNECTS})"
          end
          forward_sts_error("Speech-to-speech connection lost", ws_session_id)
          break
        end

        # Reset the handshake gates; the new upstream session must be
        # re-configured (session.update) and re-seeded from session[:messages]
        # before any further audio is appended.
        state[:session_ready] = false
        state[:seeded] = false
        send_or_broadcast({ "type" => "sts_session", "state" => "reconnecting" }.to_json, ws_session_id)
        Monadic::Utils::ExtraLogger.log do
          "[STS session=#{ws_session_id}] upstream disconnected; rebuilding session (attempt #{attempts}/#{STS_MAX_RECONNECTS})"
        end
        sleep attempts
      end
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] bridge error: #{e.class}: #{e.message}"
    end
    forward_sts_error("Speech-to-speech failed: #{e.message}", ws_session_id)
  ensure
    session[:_sts] = nil if session[:_sts].equal?(state)
  end

  def sts_connect_and_run(state, ws_session_id, api_key)
    url = "#{REALTIME_STS_URL}?model=#{URI.encode_www_form_component(state[:model])}"
    # Force HTTP/1.1 ALPN — see file header (OpenAI 405s on HTTP/2 upgrade).
    endpoint = Async::HTTP::Endpoint.parse(url, alpn_protocols: ["http/1.1"])
    headers = { "Authorization" => "Bearer #{api_key}" }

    Async::WebSocket::Client.connect(endpoint, headers: headers) do |conn|
      send_sts_session_update(conn, state)

      reader = Async do
        sts_reader_loop(conn, state, ws_session_id)
      end

      sts_writer_loop(conn, state, ws_session_id)
      reader.stop
    end
  end

  # Pure-ish payload builder kept separate from the write so specs can pin
  # the wire contract without a connection.
  def build_sts_session_update_payload(state)
    audio_input = {
      format: { type: "audio/pcm", rate: REALTIME_STS_SAMPLE_RATE },
      # Continuous conversation: the server VAD segments turns, auto-creates
      # responses and auto-cancels them on barge-in (create_response /
      # interrupt_response default to true — live-probed 2026-07-31).
      # Tunable per app via MDSL features (sts_vad_* keys); omitted keys use
      # the API defaults (threshold 0.5 / prefix 300ms / silence 500ms).
      turn_detection: sts_vad_config,
      transcription: { model: REALTIME_STS_TRANSCRIPTION_MODEL }
    }

    session_cfg = {
      type: "realtime",
      # GA name (live-probed 2026-07-31): the legacy `modalities` key is now
      # rejected as an unknown parameter — its acceptance on 2026-07-30 was
      # the tail of a rolling deployment. Transcript events
      # (output_audio_transcript.*) accompany audio output regardless, so
      # audio-only is the right setting here.
      output_modalities: %w[audio],
      audio: {
        input: audio_input,
        output: {
          format: { type: "audio/pcm", rate: REALTIME_STS_SAMPLE_RATE },
          voice: state[:voice]
        }
      }
    }
    instructions = state[:instructions].to_s
    session_cfg[:instructions] = instructions unless instructions.strip.empty?

    { type: "session.update", session: session_cfg }
  end

  def send_sts_session_update(conn, state)
    body = build_sts_session_update_payload(state).to_json
    Monadic::Utils::ExtraLogger.log { "[STS] session.update payload: #{body}" }
    conn.write(body)
    conn.flush
  end

  def sts_reader_loop(conn, state, ws_session_id)
    while (msg = conn.read)
      payload = sts_parse_payload(msg)
      next unless payload

      event_type = payload["type"]
      Monadic::Utils::ExtraLogger.log do
        "[STS session=#{ws_session_id}] event=#{event_type}"
      end

      case event_type
      when "session.created"
        sts_validate_session_model(payload, state, ws_session_id)
      when "session.updated"
        state[:session_ready] = true
        state[:ready].signal
        # Single source for the client's "live" state — also covers the
        # transparent reconnect path (reconnecting → started again).
        send_or_broadcast({ "type" => "sts_session", "state" => "started" }.to_json, ws_session_id)
        # Seed (or re-seed after rebuild) before any audio append: the
        # writer processes :seed in queue order and no-ops if already seeded.
        state[:cmd_queue].enqueue([:seed])
      when "input_audio_buffer.speech_started"
        # The user started talking. Two jobs:
        # 1. Barge-in: if the assistant is mid-response, upstream will cancel
        #    it (interrupt_response default) — but its cancelled event arrives
        #    AFTER this one, and the new turn replaces state[:turn]. Finalize
        #    the interrupted card NOW while the reference is still in hand
        #    (both finalize and notify are idempotent, so the later
        #    response.cancelled event is a harmless no-op).
        # 2. Open a new turn so the incoming utterance's transcription deltas
        #    have a home (they can arrive before response.created).
        if (turn = state[:turn]) && !turn[:assistant_finalized] && turn[:gate_open]
          sts_finalize_interrupted_turn(state, turn, ws_session_id)
          sts_notify_cancelled(turn, ws_session_id)
        end
        sts_start_new_turn(state, SecureRandom.hex(8), ws_session_id)
        send_or_broadcast({ "type" => "sts_vad", "event" => "speech_started" }.to_json, ws_session_id)
      when "input_audio_buffer.speech_stopped"
        send_or_broadcast({ "type" => "sts_vad", "event" => "speech_stopped" }.to_json, ws_session_id)
      when "response.created"
        # With server VAD the turn normally exists already (opened at
        # speech_started); a response arriving with no turn (e.g. an
        # upstream-initiated one) still needs a home for its fragments.
        sts_start_new_turn(state, SecureRandom.hex(8), ws_session_id) unless state[:turn]
      when "conversation.item.input_audio_transcription.delta"
        delta = payload["delta"].to_s
        next if delta.empty?
        turn = state[:turn]
        next unless turn
        turn[:user_partial] << delta
        send_or_broadcast({ "type" => "stt_partial", "content" => turn[:user_partial].dup }.to_json, ws_session_id)
      when "conversation.item.input_audio_transcription.completed"
        sts_handle_transcription_completed(state, payload, ws_session_id)
      when "response.output_audio_transcript.delta"
        delta = payload["delta"].to_s
        next if delta.empty?
        turn = state[:turn]
        next unless turn
        turn[:assistant_transcript] << delta
        if turn[:gate_open]
          send_or_broadcast({ "type" => "fragment", "content" => delta }.to_json, ws_session_id)
        else
          # Order gate (task #6): hold assistant text until the user's
          # final stt message has been delivered.
          turn[:pending_fragments] << delta
        end
      when "response.output_audio_transcript.done"
        sts_handle_assistant_transcript_done(state, payload, ws_session_id)
      when "response.output_audio.delta"
        turn = state[:turn]
        next unless turn
        send_or_broadcast({
          "type" => "sts_audio_delta",
          "turn_id" => turn[:id],
          "content" => payload["delta"].to_s,
          "sample_rate" => REALTIME_STS_SAMPLE_RATE
        }.to_json, ws_session_id)
      when "response.done"
        sts_handle_response_done(state, payload, ws_session_id)
      when "response.cancelled"
        turn = state[:turn]
        sts_finalize_interrupted_turn(state, turn, ws_session_id) if turn
        sts_notify_cancelled(turn, ws_session_id) if turn
      when "error"
        err = payload["error"] || {}
        Monadic::Utils::ExtraLogger.log do
          "[STS session=#{ws_session_id}] OpenAI error: #{err.inspect}"
        end
        # Never auto-fallback to the legacy pipeline — report honestly.
        forward_sts_error("Speech-to-speech: #{err['message'] || 'unknown error'}", ws_session_id)
        state[:ready].signal
      end
    end
  rescue Async::Stop
    # writer requested stop; not an error
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] reader exited: #{e.class}: #{e.message}"
    end
  ensure
    # Wake the writer so it breaks out of dequeue and the outer loop can
    # rebuild the session. nil is the writer's stop sentinel.
    state[:cmd_queue].enqueue(nil) if state[:cmd_queue]
  end

  def sts_writer_loop(conn, state, ws_session_id)
    pending = []
    queue = state[:cmd_queue]

    loop do
      cmd = queue.dequeue
      break if cmd.nil? # upstream disconnected (reader's ensure) — rebuild
      type, payload = cmd

      case type
      when :append
        if state[:session_ready] && state[:seeded]
          sts_flush_pending_appends(conn, pending)
          conn.write({ type: "input_audio_buffer.append", audio: payload }.to_json)
          conn.flush
        else
          pending << payload
        end
      when :seed
        next if state[:seeded]
        sts_seed_history(conn, state, ws_session_id)
        state[:seeded] = true
        sts_flush_pending_appends(conn, pending)
      when :commit
        next unless sts_wait_for_ready(state, ws_session_id)
        unless state[:seeded]
          sts_seed_history(conn, state, ws_session_id)
          state[:seeded] = true
        end
        sts_flush_pending_appends(conn, pending)
        conn.write({ type: "input_audio_buffer.commit" }.to_json)
        conn.flush
        conn.write({ type: "response.create" }.to_json)
        conn.flush
        sts_start_new_turn(state, payload, ws_session_id)
      when :start
        # Live Conversation session start. Ready + seed, tell the client the
        # session is live, and greet only when asked (fresh conversation).
        # With no greeting the VAD simply starts listening — the first
        # user utterance opens the first turn via upstream events.
        next unless sts_wait_for_ready(state, ws_session_id)
        unless state[:seeded]
          sts_seed_history(conn, state, ws_session_id)
          state[:seeded] = true
        end
        if payload # greet flag
          turn = sts_start_new_turn(state, SecureRandom.hex(8), ws_session_id)
          # Greeting turns have no user utterance, so there is no stt card
          # to order fragments against: open the gate at once (this also
          # disarms the gate timer).
          sts_open_gate(turn, ws_session_id, reason: "greet")
          conn.write({
            type: "response.create",
            response: { instructions: STS_INITIATE_INSTRUCTIONS }
          }.to_json)
          conn.flush
        end
      when :initiate
        # Legacy alias for [:start, true] (kept so the message type remains
        # honored; Live Conversation clients send STS_START).
        state[:cmd_queue].enqueue([:start, true])
      when :abort
        Monadic::Utils::ExtraLogger.log { "[STS session=#{ws_session_id}] barge-in (response.cancel)" }
        if state[:session_ready]
          conn.write({ type: "response.cancel" }.to_json)
          conn.flush
        end
        turn = state[:turn]
        if turn
          sts_finalize_interrupted_turn(state, turn, ws_session_id)
          sts_notify_cancelled(turn, ws_session_id)
        end
        # Intentionally no break: barge-in cancels the current response but
        # the upstream session (and this writer) lives on for the next turn.
      end
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] writer error: #{e.class}: #{e.message}"
    end
  end

  def sts_flush_pending_appends(conn, pending)
    return if pending.empty?
    pending.each do |chunk|
      conn.write({ type: "input_audio_buffer.append", audio: chunk }.to_json)
    end
    conn.flush
    pending.clear
  end

  def sts_wait_for_ready(state, ws_session_id)
    return true if state[:session_ready]
    seq = state[:abort_seq]
    Async::Task.current.with_timeout(REALTIME_STS_COMMIT_TIMEOUT) do
      state[:ready].wait
    end
    return false if state[:abort_seq] != seq # aborted while waiting
    true
  rescue Async::TimeoutError
    return false if state[:abort_seq] != seq
    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] session.updated never arrived; aborting commit"
    end
    forward_sts_error("Speech-to-speech session setup timeout", ws_session_id)
    false
  end

  def sts_parse_payload(msg)
    raw = msg.respond_to?(:buffer) ? msg.buffer : msg.to_s
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def forward_sts_error(message, ws_session_id)
    payload = { "type" => "error", "content" => message }.to_json
    send_or_broadcast(payload, ws_session_id)
  end

  # --- Session bootstrap helpers -------------------------------------------

  # Some providers silently fall back to a different model than requested;
  # surface that in the log instead of discovering it from weird behavior.
  # Returns true when the upstream session reports the requested model.
  def sts_validate_session_model(payload, state, ws_session_id)
    reported = payload.dig("session", "model").to_s
    requested = state[:model].to_s
    matched = reported.empty? || reported == requested
    unless matched
      Monadic::Utils::ExtraLogger.log do
        "[STS session=#{ws_session_id}] model mismatch: requested=#{requested} reported=#{reported} (provider silently fell back)"
      end
    end
    matched
  end

  # History seed/rebuild (task #8): session[:messages] is the source of
  # truth; the provider session is a rebuildable derivative. Sends prior
  # user/assistant text as conversation.item.create items, applying the
  # same context_size sliding window the vendor helpers apply at request
  # time (first message + last N — see e.g. openai_helper.rb's context
  # assembly). There is no shared truncation function in the codebase —
  # each vendor helper inlines that window — so this mirrors it verbatim.
  def sts_seed_history(conn, state, ws_session_id)
    messages = session[:messages] || []
    params = get_session_params
    context_size = (params["context_size"] || params[:context_size]).to_i

    context = [messages.first].compact
    if messages.length > 1 && context_size > 0
      context += messages[1..].last(context_size).compact
    end

    dropped = messages.length - context.length
    if dropped.positive?
      Monadic::Utils::ExtraLogger.log do
        "[STS session=#{ws_session_id}] history seed truncated: dropped #{dropped} of #{messages.length} messages (context_size=#{context_size})"
      end
    end

    # Skip the in-progress turn: its user message was already appended to
    # session[:messages] on transcription.completed but the upstream turn
    # it belongs to died with the old socket. Once the turn has completed
    # (assistant card finalized) its user message seeds normally.
    active_turn = state[:turn]
    skip_ref = active_turn && !active_turn[:assistant_finalized] ? active_turn[:user_msg_ref] : nil

    seeded = 0
    context.each do |m|
      next unless m.is_a?(Hash)
      next if m["type"] == "search" # search cards are UI artifacts (cf. html_handler.rb)
      role = m["role"]
      next unless %w[user assistant].include?(role)
      next if skip_ref && m.equal?(skip_ref)
      text = m["text"].to_s
      next if text.strip.empty?

      content_type = role == "user" ? "input_text" : "text"
      item = {
        type: "conversation.item.create",
        item: {
          type: "message",
          role: role,
          content: [{ type: content_type, text: text }]
        }
      }
      conn.write(item.to_json)
      seeded += 1
    end
    conn.flush if seeded.positive?

    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] history seeded: #{seeded} items"
    end
  end

  # --- Turn lifecycle --------------------------------------------------------

  def sts_start_new_turn(state, turn_id, ws_session_id)
    # Stop the previous turn's gate timer before replacing it: the timer's
    # closure captures the OLD turn, so a still-armed timer would flush the
    # old turn's buffered fragments into the new turn's card when it fires
    # (mixed-turn text leak on a quick barge-in → re-commit).
    previous = state[:turn]
    if previous && previous[:gate_timer]
      previous[:gate_timer].stop
      previous[:gate_timer] = nil
    end

    turn = {
      id: turn_id,
      user_partial: +"",
      assistant_transcript: +"",
      gate_open: false,
      pending_fragments: [],
      user_msg_ref: nil,
      assistant_finalized: false,
      cancel_notified: false,
      gate_timer: nil
    }
    state[:turn] = turn

    # Order-gate safety valve: if input_audio_transcription.completed never
    # arrives (provider hiccup), release buffered fragments after the
    # timeout so the assistant text is not silently lost.
    turn[:gate_timer] = Async do |task|
      task.sleep(STS_GATE_TIMEOUT)
      turn[:gate_timer] = nil
      sts_open_gate(turn, ws_session_id, reason: "timeout")
    end
    turn
  end

  def sts_open_gate(turn, ws_session_id, reason:)
    return if turn[:gate_open]
    turn[:gate_open] = true
    turn[:gate_timer]&.stop
    turn[:gate_timer] = nil

    if reason == "timeout"
      Monadic::Utils::ExtraLogger.log do
        "[STS session=#{ws_session_id}] order gate released by timeout after #{STS_GATE_TIMEOUT}s (turn=#{turn[:id]})"
      end
    end

    pending = turn[:pending_fragments]
    return if pending.empty?
    pending.each do |delta|
      send_or_broadcast({ "type" => "fragment", "content" => delta }.to_json, ws_session_id)
    end
    pending.clear
  end

  def sts_handle_transcription_completed(state, payload, ws_session_id)
    final = payload["transcript"].to_s
    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] completed transcript=#{final.inspect}"
    end

    turn = state[:turn]
    turn[:user_partial].clear if turn

    send_or_broadcast({ "type" => "stt", "content" => final, "logprob" => nil }.to_json, ws_session_id)

    # Mirror the normal pipeline's user-message shape (streaming_handler.rb):
    # the batch STT path's transcript becomes a user message in exactly this
    # form when the client echoes it back as a typed message.
    unless final.strip.empty?
      params = get_session_params
      user_message_data = {
        "mid" => SecureRandom.hex(4),
        "role" => "user",
        "text" => final,
        "app_name" => params["app_name"],
        "active" => true
      }
      session[:messages] ||= []
      session[:messages] << user_message_data
      # Deliver the user card so the utterance shows up in the timeline: in
      # STS mode the client no longer echoes the transcript as a typed
      # message, so the server must send the card itself (rendered via the
      # client's user-role html path).
      send_or_broadcast({ "type" => "html", "content" => user_message_data }.to_json, ws_session_id)
      turn[:user_msg_ref] = user_message_data if turn
      sync_session_state!
    end

    # Release the order gate only AFTER the stt message has gone out.
    sts_open_gate(turn, ws_session_id, reason: "completed") if turn
  end

  def sts_handle_assistant_transcript_done(state, payload, ws_session_id)
    turn = state[:turn]
    return unless turn

    transcript = payload["transcript"].to_s
    transcript = turn[:assistant_transcript].dup if transcript.empty?

    # Make sure any still-gated fragments go out (in order) before the
    # final card supersedes them.
    sts_open_gate(turn, ws_session_id, reason: "done")
    sts_send_assistant_card(turn, transcript, ws_session_id, interrupted: false)
  end

  def sts_handle_response_done(state, payload, ws_session_id)
    turn = state[:turn]
    usage = payload.dig("response", "usage") || {}
    accounting = sts_usage_accounting(usage)

    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] response.done turn=#{turn && turn[:id]} " \
      "audio_in=#{accounting[:audio_input_tokens]} audio_out=#{accounting[:audio_output_tokens]} " \
      "cached=#{accounting[:cached_tokens]} est_cost=$#{format('%.6f', accounting[:estimated_cost_usd])}"
    end

    send_or_broadcast({
      "type" => "sts_audio_done",
      "turn_id" => turn && turn[:id],
      "usage" => usage,
      # Cost accounting computed SERVER-side so the rate constants stay
      # single-sourced here; the client only displays (marked "estimate").
      "accounting" => accounting
    }.to_json, ws_session_id)
  end

  # Usage accounting (task #10): extract audio/cached token counts from a
  # realtime `usage` object and compute a cost ESTIMATE. Text tokens in the
  # same usage object are billed at different rates, so this is an estimate.
  #
  # NOTE on estimate DIRECTION: cached audio input would be billed at a far
  # lower cached-input rate, but we price ALL input at the full rate. The
  # estimate is therefore an UPPER BOUND that overestimates on cache-heavy
  # (long) sessions. `cached_tokens` is included in the breakdown so the
  # display side can phrase accordingly ("estimate (upper bound)").
  def sts_usage_accounting(usage)
    usage = {} unless usage.is_a?(Hash)
    input_details = usage["input_token_details"] || {}
    output_details = usage["output_token_details"] || {}
    cached_details = input_details["cached_tokens_details"] || {}

    audio_in = input_details["audio_tokens"].to_i
    audio_out = output_details["audio_tokens"].to_i
    cached = cached_details["audio_tokens"] || input_details["cached_tokens"]
    cached = cached.to_i

    estimated = (audio_in / 1_000_000.0 * STS_AUDIO_INPUT_RATE_PER_MTOK) +
                (audio_out / 1_000_000.0 * STS_AUDIO_OUTPUT_RATE_PER_MTOK)

    {
      audio_input_tokens: audio_in,
      audio_output_tokens: audio_out,
      cached_tokens: cached,
      estimated_cost_usd: estimated
    }
  end

  # Finalize the partial assistant card after a cancel (barge-in): send the
  # transcript accumulated so far via the same html path as a completed
  # turn, flagged as interrupted. Idempotent per turn.
  def sts_finalize_interrupted_turn(state, turn, ws_session_id)
    return if turn[:assistant_finalized]
    transcript = turn[:assistant_transcript].to_s
    return if transcript.strip.empty?

    # The interrupted card carries the full accumulated transcript, so any
    # still-gated fragments are superseded by it: stop the gate timer and
    # drop the buffer instead of letting it fire into the NEXT turn's card.
    turn[:gate_timer]&.stop
    turn[:gate_timer] = nil
    turn[:pending_fragments].clear

    sts_send_assistant_card(turn, transcript, ws_session_id, interrupted: true)
  end

  def sts_notify_cancelled(turn, ws_session_id)
    return if turn[:cancel_notified]
    turn[:cancel_notified] = true
    send_or_broadcast({ "type" => "sts_audio_cancelled", "turn_id" => turn[:id] }.to_json, ws_session_id)
  end

  # Assistant card via the same path/shape as the normal pipeline
  # (html_handler.rb's handle_ws_html): an html message whose content hash
  # doubles as the session[:messages] entry.
  def sts_send_assistant_card(turn, text, ws_session_id, interrupted:)
    params = get_session_params
    new_data = {
      "mid" => SecureRandom.hex(4),
      "role" => "assistant",
      "text" => text,
      "lang" => detect_language(text),
      "app_name" => params["app_name"],
      "monadic" => params["monadic"],
      "active" => true
    }
    new_data["interrupted"] = true if interrupted

    send_or_broadcast({ "type" => "html", "content" => new_data }.to_json, ws_session_id)

    session[:messages] ||= []
    session[:messages] << new_data
    sync_session_state!
    turn[:assistant_finalized] = true
  end
end
