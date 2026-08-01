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

  # xAI realtime (live-probed 2026-08-01): a DIALECT of the OpenAI GA
  # protocol, not a different one — response.* event names, seeding
  # vocabulary (input_text/output_text) and cancel semantics
  # (response.done status="cancelled") are identical. The differences the
  # profile + payload builder encapsulate:
  #   * session.update shape (voice / turn_detection at session level, no
  #     type:"realtime" / output_modalities; transcription.language_hint)
  #   * server_vad needs create_response / interrupt_response EXPLICITLY
  #     (defaults are off, unlike OpenAI)
  #   * user transcription arrives as .updated (CUMULATIVE) + .completed
  #   * invalid model silently falls back to think-fast-1.0 → model echo
  #     validation must be fatal
  #   * invalid voice is silently dropped → client-side whitelist
  #   * usage is {} — billing is per session minute, estimated by duration
  XAI_REALTIME_STS_URL = "wss://api.x.ai/v1/realtime"
  XAI_REALTIME_STS_DEFAULT_MODEL = "grok-voice-think-fast-2.0"
  XAI_REALTIME_STS_VOICES = %w[ara rex sal eve leo
                               carina zagan helix orion luna iris altair
                               zenith perseus helios lux kepler rigel cosmo
                               celeste ursa sirius lumen castor naksh atlas].freeze
  XAI_REALTIME_STS_DEFAULT_VOICE = "eve"
  # $4.80/hour (xAI pricing), billed per session minute — idle time included.
  XAI_STS_RATE_PER_MINUTE = 0.08

  # Per-provider connection/validation facts. The turn machinery (turns,
  # gates, response/item maps, merge, canon) is shared; what varies is how
  # to reach the provider and which failure modes need hard guards.
  STS_PROVIDER_PROFILES = {
    "openai" => {
      url: REALTIME_STS_URL,
      api_key_env: "OPENAI_API_KEY",
      default_model: REALTIME_STS_DEFAULT_MODEL,
      voices: REALTIME_STS_VOICES,
      default_voice: REALTIME_STS_DEFAULT_VOICE,
      # OpenAI honors the requested model; mismatch is log-only.
      model_mismatch_fatal: false
    },
    "xai" => {
      url: XAI_REALTIME_STS_URL,
      api_key_env: "XAI_API_KEY",
      default_model: XAI_REALTIME_STS_DEFAULT_MODEL,
      voices: XAI_REALTIME_STS_VOICES,
      default_voice: XAI_REALTIME_STS_DEFAULT_VOICE,
      # Live-probed: a bad model name silently becomes think-fast-1.0.
      # Continuing on the wrong model would misrepresent the app.
      model_mismatch_fatal: true
    },
    # Gemini Live (BidiGenerateContent) — a genuinely different protocol.
    # The reader translates its serverContent stream into the internal
    # (OpenAI-GA-shaped) event vocabulary via sts_translate_gemini; the
    # writer wraps audio/seed/greet in Gemini frames. Live-probed
    # 2026-08-01: input 16kHz / output 24kHz, delta transcriptions both
    # ways, auth via ?key= query param, 15-minute session cap.
    "gemini" => {
      url: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent",
      api_key_env: "GEMINI_API_KEY",
      auth: :query_key,
      default_model: "gemini-3.1-flash-live-preview",
      voices: %w[Zephyr Puck Charon Kore Fenrir Leda Orus
                 Aoede Callirrhoe Autonoe Enceladus Iapetus
                 Umbriel Algieba Despina Erinome Algenib
                 Rasalgethi Laomedeia Achernar Alnilam Schedar
                 Gacrux Pulcherrima Achird Zubenelgenubi
                 Vindemiatrix Sadachbia Sadaltager Sulafat].freeze,
      default_voice: "Kore",
      input_rate: 16_000,
      model_mismatch_fatal: false
    }
  }.freeze

  # Data-driven provider lookup (review round 5, P4): the model_spec entry
  # carries sts_provider; the prefix scan remains only as a fallback for
  # entries that predate the field.
  def sts_provider_for(model)
    from_spec = begin
      Monadic::Utils::ModelSpec.get_model_property(model.to_s, "sts_provider")
    rescue StandardError
      nil
    end
    return from_spec if STS_PROVIDER_PROFILES.key?(from_spec)

    case model.to_s.downcase
    when /\Agrok/ then "xai"
    when /\Agemini/ then "gemini"
    else "openai"
    end
  end

  def sts_profile(state)
    STS_PROVIDER_PROFILES[state[:provider] || "openai"] || STS_PROVIDER_PROFILES["openai"]
  end

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
    return unless state

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
    settings = sts_app_settings

    # semantic_vad waits for semantic completion instead of a fixed silence
    # window — the right tool when hesitation pauses cause false turn ends.
    # Opt-in per app via MDSL (sts_vad_type "semantic_vad"); default stays
    # server_vad.
    vad_type = settings && (settings[:sts_vad_type] || settings["sts_vad_type"]).to_s
    if vad_type == "semantic_vad"
      cfg = { type: "semantic_vad" }
      eagerness = (settings[:sts_vad_eagerness] || settings["sts_vad_eagerness"]).to_s
      cfg[:eagerness] = eagerness if %w[low medium high auto].include?(eagerness)
      return cfg
    end

    cfg = { type: "server_vad" }
    if settings
      { threshold: :sts_vad_threshold,
        prefix_padding_ms: :sts_vad_prefix_ms,
        silence_duration_ms: :sts_vad_silence_ms }.each do |api_key, mdsl_key|
        value = settings[mdsl_key] || settings[mdsl_key.to_s]
        next unless value.is_a?(Numeric) && value >= 0
        next if api_key == :threshold && value > 1
        next if api_key != :threshold && value > 10_000 # ms sanity cap

        cfg[api_key] = value
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
    return unless state

    queue = state[:cmd_queue]
    return unless queue

    greet_requested = obj["greet"] == true || obj["greet"] == "true"
    # The client's greet hint says "the greeting toggle is on"; whether this
    # is a FRESH conversation is decided here against the canonical
    # session[:messages]. Fresh means no CONVERSATION turns — the session
    # start always appends the system prompt first (handle_ws_system_prompt),
    # so an emptiness check never fired (review P1-A).
    fresh = session[:messages].to_a.none? { |m| %w[user assistant].include?((m["role"] || m[:role]).to_s) }
    greet = greet_requested && fresh
    # Merge scope for Stop-time consolidation: only messages produced during
    # THIS conversation span are candidates (a loaded history must never be
    # rewritten).
    state[:canon_start] ||= session[:messages].to_a.length
    Monadic::Utils::ExtraLogger.log do
      "[STS] START greet_requested=#{greet_requested} fresh=#{fresh} → greet=#{greet}"
    end
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
    merged = state ? sts_merge_conversation_fragments!(sess, state) : false
    teardown_sts_session(sess)
    send_or_broadcast({ "type" => "sts_session", "state" => "stopped",
                        "merged" => merged }.to_json, ws_session_id)
  end

  # VAD-split turns leave several consecutive same-role cards ("The" / "Oh
  # yeah, …" / "Ilias and the Odyssey…"). Once the conversation ends, fold
  # consecutive user/user and assistant/assistant messages of THIS span into
  # one message each, so the saved conversation reads as alternating turns.
  # Returns true when anything was folded (the client then reloads the
  # discourse to re-render).
  def sts_merge_conversation_fragments!(sess, state)
    messages = sess[:messages]
    # No recorded span means NO span — nil must not default to 0 ("the whole
    # canon is mine"), or a stray STS_STOP against a bridge that never saw
    # STS_START would fold the entire loaded history (review round 4, P2).
    start = state[:canon_start] || (messages.is_a?(Array) ? messages.length : 0)
    return false unless messages.is_a?(Array) && start < messages.length

    merged_any = false
    result = messages[0...start]
    messages[start..].each do |msg|
      role = (msg["role"] || msg[:role]).to_s
      # A fragment may only fold into a predecessor from the SAME span —
      # otherwise the first in-span message merges into the loaded history.
      prev = result.length > start ? result.last : nil
      prev_role = prev && (prev["role"] || prev[:role]).to_s
      if %w[user assistant].include?(role) && prev_role == role && prev.is_a?(Hash)
        prev["text"] = [prev["text"].to_s, msg["text"].to_s].map(&:strip).reject(&:empty?).join("

")
        # The interruption marker describes the END state of the merged
        # message: a later completed piece supersedes an interrupted stub.
        if msg["interrupted"]
          prev["interrupted"] = true
        else
          prev.delete("interrupted")
        end
        merged_any = true
      else
        result << msg
      end
    end
    return false unless merged_any

    messages.replace(result)
    sync_session_state!
    true
  end

  # Entry point for initiate_from_assistant in STS mode. Driving the normal
  # pipeline would 404 on a realtime-only model, so the client signals
  # initiation with STS_INITIATE instead; the bridge then asks the model to
  # greet (response.create with instructions). Same defensive surface as a
  # bare commit: with no bridge state there is nothing to do.
  def handle_sts_initiate(_connection, obj)
    state = ensure_sts_state!(obj)
    return unless state

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
    WebSocketHelper.teardown_sts_session_for(sess)
  end

  # Class-method form so non-WebSocket contexts (the HTTP import route) can
  # tear the bridge down too: importing a conversation replaces
  # session[:messages], and a live bridge surviving that keeps the upstream
  # socket billing AND holds a canon_start into the OLD canon — the Stop-time
  # merge would then fold the imported history (review round 4, P1).
  def self.teardown_sts_session_for(sess)
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

    # A model that just failed fatally (e.g. xAI silent fallback) must not
    # be respawned by mic chunks still in flight after the stop — each
    # respawn opens a billed upstream session that dies the same way. A
    # DIFFERENT model clears the memory (the user changed something).
    if session[:_sts_fatal]
      return nil if session[:_sts_fatal] == model

      session.delete(:_sts_fatal)
    end
    provider = sts_provider_for(model)
    profile = STS_PROVIDER_PROFILES[provider]
    # Voice resolution (SSOT order): model_spec sts_voices is the canonical
    # list, profile constants are the fallback; model_spec sts_voice is the
    # canonical default, profile default_voice the fallback. `sts_voice`
    # (LC selector) wins over the legacy `tts_voice` (TTS panel) value.
    candidates = Monadic::Utils::ModelSpec.get_model_property(model, "sts_voices")
    candidates = profile[:voices] unless candidates.is_a?(Array) && !candidates.empty?
    voice = (params["sts_voice"] || params[:sts_voice] ||
             params["tts_voice"] || params[:tts_voice]).to_s
    unless candidates.include?(voice)
      Monadic::Utils::ExtraLogger.log do
        "[STS] voice #{voice.inspect} is not a #{provider} realtime voice; using the default"
      end unless voice.strip.empty?
      default = Monadic::Utils::ModelSpec.get_model_property(model, "sts_voice")
      default = profile[:default_voice] unless default.is_a?(String) && candidates.include?(default)
      voice = default
    end
    instructions = params["initial_prompt"] || params[:initial_prompt]
    language = (params["conversation_language"] || params[:conversation_language]).to_s
    language = "auto" if language.strip.empty?

    # OpenAI-only: playback speed (0.25-1.5, spec-verified). Carried only
    # for providers whose model_spec marks sts_speed_capability; never sent
    # to xAI/Gemini (their setup would reject or ignore it silently).
    speed = nil
    if provider == "openai" &&
       Monadic::Utils::ModelSpec.get_model_property(model, "sts_speed_capability") == true
      raw_speed = (params["sts_speed"] || params[:sts_speed]).to_s
      unless raw_speed.strip.empty?
        val = raw_speed.to_f
        speed = val.clamp(0.25, 1.5) if val.positive?
      end
    end

    state = {
      cmd_queue: Async::Queue.new,
      session_ready: false,
      seeded: false,
      abort_seq: 0,
      ready: Async::Condition.new,
      model: model,
      provider: provider,
      voice: voice,
      speed: speed,
      instructions: instructions,
      language: language,
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
    profile = sts_profile(state)
    api_key = CONFIG[profile[:api_key_env]]
    if api_key.nil? || api_key.empty?
      forward_sts_error("#{profile[:api_key_env]} is not configured", ws_session_id)
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
      state[:billing_mark] ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
        # A fatal condition (e.g. xAI silent model fallback) is deterministic:
        # reconnecting would only repeat it.
        if state[:fatal]
          send_or_broadcast({ "type" => "sts_session", "state" => "stopped" }.to_json, ws_session_id)
          break
        end
        attempts = 0 if state[:session_ready] && lived >= STS_HEALTHY_SESSION_SECONDS
        attempts += 1
        if attempts > STS_MAX_RECONNECTS
          Monadic::Utils::ExtraLogger.log do
            "[STS session=#{ws_session_id}] reconnect attempts exhausted (#{STS_MAX_RECONNECTS})"
          end
          forward_sts_error("Speech-to-speech connection lost", ws_session_id)
          # Mirror handle_sts_stop's terminal signal: without it the client
          # stays in "listening" with the mic streaming into a dead bridge
          # (P2-3). The ensure below clears session[:_sts].
          send_or_broadcast({ "type" => "sts_session", "state" => "stopped" }.to_json, ws_session_id)
          break
        end

        # Reset the handshake gates; the new upstream session must be
        # re-configured (session.update) and re-seeded from session[:messages]
        # before any further audio is appended.
        state[:session_ready] = false
        state[:seeded] = false
        # Per-minute estimate: the dead-session gap up to this point must not
        # ride on the next accounting mark (review P3-3). Handshake time of
        # the new session still counts — small and genuinely billed.
        state[:billing_mark] = Process.clock_gettime(Process::CLOCK_MONOTONIC) if state[:provider] == "xai"
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
    send_or_broadcast({ "type" => "sts_session", "state" => "stopped" }.to_json, ws_session_id)
  ensure
    session[:_sts] = nil if session[:_sts].equal?(state)
  end

  def sts_connect_and_run(state, ws_session_id, api_key)
    profile = sts_profile(state)
    if profile[:auth] == :query_key
      # Gemini: API key travels as a query parameter; the model is named in
      # the setup frame, not the URL.
      url = "#{profile[:url]}?key=#{URI.encode_www_form_component(api_key)}"
      headers = {}
    else
      url = "#{profile[:url]}?model=#{URI.encode_www_form_component(state[:model])}"
      headers = { "Authorization" => "Bearer #{api_key}" }
    end
    # Force HTTP/1.1 ALPN — see file header (OpenAI 405s on HTTP/2 upgrade).
    endpoint = Async::HTTP::Endpoint.parse(url, alpn_protocols: ["http/1.1"])

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
    case state[:provider] || "openai"
    when "xai" then return build_xai_session_update_payload(state)
    when "gemini" then return build_gemini_setup_payload(state)
    end

    audio_input = {
      format: { type: "audio/pcm", rate: REALTIME_STS_SAMPLE_RATE },
      # Continuous conversation: the server VAD segments turns, auto-creates
      # responses and auto-cancels them on barge-in (create_response /
      # interrupt_response default to true — live-probed 2026-07-31).
      # Tunable per app via MDSL features (sts_vad_* keys); omitted keys use
      # the API defaults (threshold 0.5 / prefix 300ms / silence 500ms).
      turn_detection: sts_vad_config,
      # Near-field noise reduction: fewer false VAD triggers from ambient
      # noise, which otherwise become hallucinated transcripts.
      noise_reduction: { type: "near_field" },
      transcription: { model: REALTIME_STS_TRANSCRIPTION_MODEL }
    }
    # Pin the input-transcription language when the user chose one: without
    # it the transcriber auto-detects per utterance, and short/noisy audio
    # gets misread into unrelated languages (Japanese → Korean in dogfood).
    lang_code = Monadic::Utils::LanguageConfig.stt_language_code(state[:language])
    audio_input[:transcription][:language] = lang_code if lang_code

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
          # audio.output.speed is GA-accepted (live-probed 2026-08-01: echo
          # speed=1.3 on a 1.3 request). OpenAI-only by construction
          # (state[:speed] is nil for other providers).
        }.tap { |out| out[:speed] = state[:speed] if state[:speed] }
      }
    }
    # The conversation-language preference travels inside instructions —
    # same directive text the typed pipeline uses (LanguageConfig), so the
    # two pipelines cannot drift apart on wording.
    language_prompt = Monadic::Utils::LanguageConfig
                      .system_prompt_for_language(state[:language] || "auto").to_s
    instructions = [state[:instructions].to_s, language_prompt]
                   .map(&:strip).reject(&:empty?).join("\n\n")
    session_cfg[:instructions] = instructions unless instructions.empty?

    { type: "session.update", session: session_cfg }
  end

  # xAI session shape (live-probed 2026-08-01): voice and turn_detection sit
  # at session level, there is no type/output_modalities, transcription takes
  # a BCP-47 language_hint, and create_response/interrupt_response must be
  # explicit (the continuous conversation depends on both).
  def build_xai_session_update_payload(state)
    vad = { type: "server_vad", create_response: true, interrupt_response: true }
    settings = sts_app_settings
    if settings && (settings[:sts_vad_type] || settings["sts_vad_type"]).to_s == "semantic_vad"
      Monadic::Utils::ExtraLogger.log do
        "[STS] sts_vad_type=semantic_vad is not supported by xAI; using server_vad"
      end
    end
    if settings
      { threshold: :sts_vad_threshold,
        silence_duration_ms: :sts_vad_silence_ms }.each do |api_key, mdsl_key|
        value = settings[mdsl_key] || settings[mdsl_key.to_s]
        next unless value.is_a?(Numeric) && value >= 0
        next if api_key == :threshold && !(0.1..0.9).cover?(value)
        next if api_key == :silence_duration_ms && value > 10_000

        vad[api_key] = value
      end
    end

    audio_input = { format: { type: "audio/pcm", rate: REALTIME_STS_SAMPLE_RATE } }
    lang_code = Monadic::Utils::LanguageConfig.stt_language_code(state[:language])
    audio_input[:transcription] = { language_hint: lang_code } if lang_code

    language_prompt = Monadic::Utils::LanguageConfig
                      .system_prompt_for_language(state[:language] || "auto").to_s
    instructions = [state[:instructions].to_s, language_prompt]
                   .map(&:strip).reject(&:empty?).join("\n\n")

    session_cfg = {
      voice: state[:voice],
      turn_detection: vad,
      audio: {
        input: audio_input,
        output: { format: { type: "audio/pcm", rate: REALTIME_STS_SAMPLE_RATE } }
      }
    }
    session_cfg[:instructions] = instructions unless instructions.empty?

    { type: "session.update", session: session_cfg }
  end

  # Gemini Live setup frame (live-probed 2026-08-01). camelCase field names;
  # the model is named here (not in the URL); transcription is enabled for
  # both directions; VAD tuning maps the shared MDSL keys onto
  # automaticActivityDetection where an equivalent exists.
  def build_gemini_setup_payload(state)
    language_prompt = Monadic::Utils::LanguageConfig
                      .system_prompt_for_language(state[:language] || "auto").to_s
    instructions = [state[:instructions].to_s, language_prompt]
                   .map(&:strip).reject(&:empty?).join("\n\n")

    setup = {
      model: "models/#{state[:model]}",
      generationConfig: {
        responseModalities: ["AUDIO"],
        speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: state[:voice] } } }
      },
      inputAudioTranscription: {},
      outputAudioTranscription: {}
    }
    setup[:systemInstruction] = { parts: [{ text: instructions }] } unless instructions.empty?

    vad = {}
    settings = sts_app_settings
    if settings
      { silenceDurationMs: :sts_vad_silence_ms,
        prefixPaddingMs: :sts_vad_prefix_ms }.each do |api_key, mdsl_key|
        value = settings[mdsl_key] || settings[mdsl_key.to_s]
        next unless value.is_a?(Numeric) && value >= 0 && value <= 10_000

        vad[api_key] = value
      end
    end
    setup[:realtimeInputConfig] = { automaticActivityDetection: vad } unless vad.empty?

    { setup: setup }
  end

  def send_sts_session_update(conn, state)
    body = build_sts_session_update_payload(state).to_json
    Monadic::Utils::ExtraLogger.log { "[STS] session.update payload: #{body}" }
    conn.write(body)
    conn.flush
  end

  def sts_reader_loop(conn, state, ws_session_id)
    while (msg = conn.read)
      raw = sts_parse_payload(msg)
      next unless raw

      # Normalization boundary: Gemini's BidiGenerateContent stream is
      # translated into the internal event vocabulary (the OpenAI-GA shapes
      # — the dialect two of three providers speak natively) so the shared
      # turn machinery below stays provider-blind. One upstream message can
      # yield several internal events.
      sts_translate_events(state, raw).each do |payload|
      event_type = payload["type"]
      Monadic::Utils::ExtraLogger.log do
        "[STS session=#{ws_session_id}] event=#{event_type}"
      end

      case event_type
      when "session.created"
        unless sts_validate_session_model(payload, state, ws_session_id)
          if sts_profile(state)[:model_mismatch_fatal]
            # Live-probed: xAI silently substitutes think-fast-1.0 for any
            # unknown model. Running the conversation on a model the user
            # did not pick is a misrepresentation — stop instead.
            reported = payload.dig("session", "model")
            forward_sts_error(
              "Speech-to-speech: requested model #{state[:model]} but the " + "server selected #{reported} (silent fallback). Stopping.",
              ws_session_id
            )
            state[:fatal] = true
            # Remembered at session level so mic chunks still in flight do
            # not respawn the bridge into the same fatal (billing loop) —
            # cleared when the model changes (see ensure_sts_state!) or on
            # the UPDATE_PARAMS / RESET teardown paths.
            session[:_sts_fatal] = state[:model]
            # Wake a writer parked in sts_wait_for_ready NOW — without this
            # the Start path blocked up to 15s and surfaced a second,
            # misleading "session setup timeout" error (review P2).
            state[:ready].signal
            break
          end
        end
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
        #    the interrupted card NOW while the reference is still in hand;
        #    trailing response-scoped events (cancelled/done/transcript.done)
        #    resolve the OLD turn via the response_id map and no-op on its
        #    idempotence guards.
        # 2. Open a new turn so the incoming utterance's transcription deltas
        #    have a home (they can arrive before response.created).
        # Finalize whenever a RESPONSE existed for the old turn — gate state is
        # irrelevant (the gate exists precisely because transcription can lag
        # the response; P1-2). `response_id` also guards the double-speech
        # edge: a turn that never got a response has no audio to cancel, and
        # notifying it would make the client discard its future audio.
        if (turn = state[:turn]) && !turn[:assistant_finalized] && turn[:response_id]
          sts_finalize_interrupted_turn(state, turn, ws_session_id)
          sts_notify_cancelled(turn, ws_session_id)
        end
        sts_start_new_turn(state, SecureRandom.hex(8), ws_session_id)
        send_or_broadcast({ "type" => "sts_vad", "event" => "speech_started" }.to_json, ws_session_id)
      when "input_audio_buffer.speech_stopped"
        send_or_broadcast({ "type" => "sts_vad", "event" => "speech_stopped" }.to_json, ws_session_id)
      when "response.created"
        # A spontaneous response.create (greet / commit) is correlated with
        # the turn that requested it — the current turn may already belong
        # to the NEXT utterance by the time this event arrives (P2-1).
        turn = state.delete(:pending_response_turn)
        unless turn
          # With server VAD the turn normally exists already (opened at
          # speech_started); a response arriving with no turn (e.g. an
          # upstream-initiated one) still needs a home for its fragments.
          sts_start_new_turn(state, SecureRandom.hex(8), ws_session_id) unless state[:turn]
          turn = state[:turn]
        end
        sts_bind_response(state, payload.dig("response", "id"), turn)
      when "conversation.item.input_audio_transcription.delta"
        delta = payload["delta"].to_s
        next if delta.empty?
        turn = state[:turn]
        next unless turn
        # First delta claims the item for this turn, so the (possibly late)
        # completed event can resolve its own turn (P2-2 — same pattern as
        # the response map: user A's completed arriving after user B's
        # speech_started must not open B's order gate).
        sts_bind_item(state, payload["item_id"], turn)
        turn[:user_partial] << delta
        send_or_broadcast({ "type" => "stt_partial", "content" => turn[:user_partial].dup }.to_json, ws_session_id)
      when "conversation.item.input_audio_transcription.updated"
        # xAI dialect: cumulative user transcript (whole utterance so far),
        # not a delta — REPLACE the partial rather than appending. Resolve
        # the turn through the item map (symmetric with completed) and
        # ignore late updates for turns whose user card is already final —
        # a straggler must not repaint the NEXT turn's partial (review
        # P3-1, same family as the response-map misattributions).
        transcript = payload["transcript"].to_s
        next if transcript.empty?
        iid = payload["item_id"]
        turn = (state[:items] || {})[iid] || state[:turn]
        next unless turn
        # Drop only true stragglers: an update for a PREVIOUS turn whose
        # user card is final (P3-1). The CURRENT turn keeps updating even
        # after an intermediate completed — xAI finalizes repeatedly while
        # the user is still talking.
        next if turn[:user_msg_ref] && !turn.equal?(state[:turn])
        sts_bind_item(state, iid, turn) unless (state[:items] || {})[iid]
        turn[:user_partial].replace(transcript)
        send_or_broadcast({ "type" => "stt_partial", "content" => transcript }.to_json, ws_session_id)
      when "conversation.item.input_audio_transcription.completed"
        sts_handle_transcription_completed(state, payload, ws_session_id)
      when "response.output_audio_transcript.delta"
        delta = payload["delta"].to_s
        next if delta.empty?
        turn = sts_turn_for_response(state, payload)
        next unless turn
        turn[:assistant_transcript] << delta
        if turn[:gate_open]
          sts_send_fragment(turn, delta, ws_session_id)
        else
          # Order gate (task #6): hold assistant text until the user's
          # final stt message has been delivered.
          turn[:pending_fragments] << delta
        end
      when "response.output_audio_transcript.done"
        sts_handle_assistant_transcript_done(state, payload, ws_session_id)
      when "response.output_audio.delta"
        turn = sts_turn_for_response(state, payload)
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
        # Live-probed 2026-08-01: GA does NOT emit this event (cancellation
        # arrives as response.done status="cancelled", handled in
        # sts_handle_response_done). Kept as defense for other deployments.
        # Attribute by response id: after a barge-in this event arrives when
        # state[:turn] is already the NEXT utterance's turn (P1-1).
        turn = sts_turn_for_response(state, payload)
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
      break if state[:fatal]
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
          sts_flush_pending_appends(conn, state, pending)
          conn.write(sts_append_frame(state, payload))
          conn.flush
        else
          pending << payload
        end
      when :seed
        next if state[:seeded]
        sts_seed_history(conn, state, ws_session_id)
        state[:seeded] = true
        sts_flush_pending_appends(conn, state, pending)
      when :commit
        # Gemini has no GA commit/response.create frames; the LC flow never
        # issues :commit, this guard keeps a stray one from confusing the
        # upstream (review P3).
        next if (state[:provider] || "openai") == "gemini"
        next unless sts_wait_for_ready(state, ws_session_id)
        unless state[:seeded]
          sts_seed_history(conn, state, ws_session_id)
          state[:seeded] = true
        end
        sts_flush_pending_appends(conn, state, pending)
        conn.write({ type: "input_audio_buffer.commit" }.to_json)
        conn.flush
        conn.write({ type: "response.create" }.to_json)
        conn.flush
        state[:pending_response_turn] = sts_start_new_turn(state, payload, ws_session_id)
      when :start
        # Live Conversation session start. Ready + seed, tell the client the
        # session is live, and greet only when asked (fresh conversation).
        # With no greeting the VAD simply starts listening — the first
        # user utterance opens the first turn via upstream events.
        #
        # Chunks captured before this point are mic warm-up, not speech:
        # flushing them after the greet made the VAD "hear" noise, and its
        # phantom turn barge-in-cancelled the greeting (transcribed as
        # hallucinated text like a stray sentence). The conversation starts
        # NOW; whatever the mic caught before now is discarded. Once per
        # bridge — a duplicate STS_START mid-conversation must not discard
        # legitimate speech buffered across a reconnect (review P3-1).
        unless state[:started]
          state[:started] = true
          pending.clear
        end
        next unless sts_wait_for_ready(state, ws_session_id)
        unless state[:seeded]
          sts_seed_history(conn, state, ws_session_id)
          state[:seeded] = true
        end
        if payload && !state[:greeted] # greet flag; once per bridge (a
          # duplicate STS_START must not re-greet mid-conversation)
          state[:greeted] = true
          turn = sts_start_new_turn(state, SecureRandom.hex(8), ws_session_id)
          # Correlate the spontaneous response we are about to create with
          # THIS turn: if the user starts talking before response.created
          # arrives, state[:turn] is already the next utterance's turn and
          # binding to it would mis-address the greeting (review P2-1).
          state[:pending_response_turn] = turn
          # Greeting turns have no user utterance, so there is no stt card
          # to order fragments against: open the gate at once (this also
          # disarms the gate timer).
          sts_open_gate(turn, ws_session_id, reason: "greet")
          if (state[:provider] || "openai") == "gemini"
            # Gemini has no response.create; a turnComplete client turn
            # asking for a greeting triggers generation. The nudge text
            # stays upstream-only — the canon is untouched.
            conn.write({ clientContent: {
              turns: [{ role: "user", parts: [{ text: STS_INITIATE_INSTRUCTIONS }] }],
              turnComplete: true
            } }.to_json)
          else
            conn.write({
              type: "response.create",
              response: { instructions: STS_INITIATE_INSTRUCTIONS }
            }.to_json)
          end
          conn.flush
        end
      when :initiate
        # Legacy alias for [:start, true] (kept so the message type remains
        # honored; Live Conversation clients send STS_START).
        state[:cmd_queue].enqueue([:start, true])
      when :abort
        Monadic::Utils::ExtraLogger.log { "[STS session=#{ws_session_id}] barge-in (response.cancel)" }
        next if (state[:provider] || "openai") == "gemini"
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

  def sts_flush_pending_appends(conn, state, pending)
    return if pending.empty?
    pending.each do |chunk|
      conn.write(sts_append_frame(state, chunk))
    end
    conn.flush
    pending.clear
  end

  # Audio frame per provider dialect. OpenAI/xAI share the GA shape; Gemini
  # wraps chunks in realtimeInput with an explicit sample-rate mime (input
  # is 16kHz there — the CLIENT captures at the profile rate, this only
  # labels it).
  def sts_append_frame(state, chunk)
    if (state[:provider] || "openai") == "gemini"
      rate = sts_profile(state)[:input_rate] || REALTIME_STS_SAMPLE_RATE
      { realtimeInput: { audio: { data: chunk, mimeType: "audio/pcm;rate=#{rate}" } } }.to_json
    else
      { type: "input_audio_buffer.append", audio: chunk }.to_json
    end
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

  # Provider event normalization. Non-Gemini payloads pass through
  # unchanged; Gemini serverContent messages are decomposed into internal
  # events. Synthesized ids: one item per user utterance (gitem-N), one
  # response per generation (gresp-N) — Gemini itself has neither concept,
  # the counters exist so the shared attribution maps keep working.
  def sts_translate_events(state, payload)
    return [payload] unless (state[:provider] || "openai") == "gemini"

    sts_translate_gemini(state, payload)
  end

  def sts_translate_gemini(state, payload)
    g = (state[:gem] ||= { resp_open: false, resp_seq: 0, item_seq: 0, item_id: nil, usage: nil })
    events = []

    events << { "type" => "session.updated" } if payload["setupComplete"]
    g[:usage] = payload["usageMetadata"] if payload["usageMetadata"]

    sc = payload["serverContent"]
    if payload["error"]
      err = payload["error"]
      events << { "type" => "error", "error" => { "message" => err["message"] || err.inspect } }
    end
    return events unless sc

    # Barge-in: Gemini flags the aborted generation instead of emitting a
    # cancel event. Translate to the internal cancel shape (response.done
    # status=cancelled — the same wire GA OpenAI/xAI use).
    if sc["interrupted"] && g[:resp_open]
      events << { "type" => "response.done",
                  "response" => { "id" => g[:rid], "status" => "cancelled",
                                  "usage" => g[:usage] || {} } }
      g[:resp_open] = false
      g[:usage] = nil
    end

    in_text = sc.dig("inputTranscription", "text").to_s
    unless in_text.empty?
      # A fresh utterance begins only when the previous turn is genuinely
      # over: assistant finalized, interrupted (Gemini's own flag — an
      # empty-transcript interruption never sets finalized, review P1-2),
      # or the turn closed without any response (safety filter, review P2).
      # `resp_open` is deliberately NOT a trigger: Gemini keeps delivering
      # the previous utterance's transcription after the answer starts, and
      # treating that as barge-in cancelled healthy responses mid-air
      # (review P1-1). Real barge-in announces itself via `interrupted`.
      turn = state[:turn]
      if turn.nil? || turn[:assistant_finalized] || turn[:interrupted] ||
         g[:closed_without_response]
        events << { "type" => "input_audio_buffer.speech_started" }
        g[:item_id] = "gitem-#{g[:item_seq] += 1}"
        g[:closed_without_response] = false
      end
      events << { "type" => "conversation.item.input_audio_transcription.delta",
                  "item_id" => g[:item_id], "delta" => in_text }
    end

    audio_parts = (sc.dig("modelTurn", "parts") || []).filter_map { |p| p.dig("inlineData", "data") }
    out_text = sc.dig("outputTranscription", "text").to_s

    if (!audio_parts.empty? || !out_text.empty?) && !g[:resp_open]
      g[:resp_open] = true
      g[:rid] = "gresp-#{g[:resp_seq] += 1}"
      # The user's turn is over when the model starts answering: finalize
      # the user side first so the order gate opens before fragments flow.
      # transcript is left empty — the completed handler falls back to the
      # accumulated partial. speech_stopped keeps the client status line
      # honest (Gemini never emits it).
      events << { "type" => "input_audio_buffer.speech_stopped" }
      events << { "type" => "conversation.item.input_audio_transcription.completed",
                  "item_id" => g[:item_id], "transcript" => "" }
      events << { "type" => "response.created", "response" => { "id" => g[:rid] } }
    end

    audio_parts.each do |b64|
      events << { "type" => "response.output_audio.delta",
                  "response_id" => g[:rid], "delta" => b64 }
    end
    unless out_text.empty?
      events << { "type" => "response.output_audio_transcript.delta",
                  "response_id" => g[:rid], "delta" => out_text }
    end

    if sc["turnComplete"]
      if g[:resp_open]
        events << { "type" => "response.output_audio_transcript.done",
                    "response_id" => g[:rid], "transcript" => "" }
        events << { "type" => "response.done",
                    "response" => { "id" => g[:rid], "status" => "completed",
                                    "usage" => g[:usage] || {} } }
        g[:resp_open] = false
        g[:usage] = nil
      else
        # A turn can complete with NO model content (safety filter, empty
        # generation — review P2). Close the user side so the turn does not
        # stay open and swallow the next utterance.
        events << { "type" => "input_audio_buffer.speech_stopped" }
        events << { "type" => "conversation.item.input_audio_transcription.completed",
                    "item_id" => g[:item_id], "transcript" => "" }
        g[:closed_without_response] = true
      end
    end

    events
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

    return sts_seed_history_gemini(conn, context, state, ws_session_id) if (state[:provider] || "openai") == "gemini"

    seeded = 0
    context.each do |m|
      next unless m.is_a?(Hash)
      next if m["type"] == "search" # search cards are UI artifacts (cf. html_handler.rb)
      role = m["role"]
      next unless %w[user assistant].include?(role)
      next if skip_ref && m.equal?(skip_ref)
      text = m["text"].to_s
      next if text.strip.empty?

      # GA vocabulary (dogfood 2026-07-31): assistant items take
      # "output_text" — the legacy "text" is rejected with "Invalid value:
      # 'text'. Value must be 'output_text'." The failure only surfaced on a
      # MID-CONVERSATION reconnect re-seed, because that is the first live
      # path that seeds assistant history into a GA session.
      content_type = role == "user" ? "input_text" : "output_text"
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

  # Gemini seeds history as ONE clientContent frame (turns array, roles
  # user/model — NOT assistant). turnComplete:false = context only, no
  # generation. Live-probed 2026-08-01.
  def sts_seed_history_gemini(conn, context, state, ws_session_id)
    active_turn = state[:turn]
    skip_ref = active_turn && !active_turn[:assistant_finalized] ? active_turn[:user_msg_ref] : nil

    turns = context.filter_map do |m|
      next unless m.is_a?(Hash)
      next if m["type"] == "search"

      role = m["role"]
      next unless %w[user assistant].include?(role)
      next if skip_ref && m.equal?(skip_ref)

      text = m["text"].to_s
      next if text.strip.empty?

      { role: role == "assistant" ? "model" : "user", parts: [{ text: text }] }
    end
    return if turns.empty?

    conn.write({ clientContent: { turns: turns, turnComplete: false } }.to_json)
    conn.flush
    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] gemini history seeded: #{turns.length} turns"
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

  # response-scoped events (deltas / transcript.done / done / cancelled) can
  # arrive AFTER state[:turn] has been replaced by the next utterance's turn
  # (VAD barge-in). Attributing them to state[:turn] mis-addressed them — the
  # live failure was a delayed response.cancelled carrying the NEW turn's id,
  # which made the client discard that turn's audio forever. Responses are
  # therefore mapped to their turn explicitly.
  STS_RESPONSE_MAP_MAX = 8

  def sts_bind_response(state, response_id, turn)
    return if response_id.to_s.empty?

    turn[:response_id] = response_id
    map = (state[:responses] ||= {})
    map[response_id] = turn
    map.shift while map.size > STS_RESPONSE_MAP_MAX
  end

  # Turn for a response-scoped event. Falls back to the current turn only
  # when the event carries no response id at all.
  def sts_turn_for_response(state, payload)
    rid = payload["response_id"] || payload.dig("response", "id")
    return state[:turn] if rid.to_s.empty?

    (state[:responses] || {})[rid]
  end

  # Same idea for conversation items (user-side transcription events):
  # the item is claimed by the turn whose utterance produced it.
  def sts_bind_item(state, item_id, turn)
    return if item_id.to_s.empty?

    turn[:item_id] ||= item_id
    map = (state[:items] ||= {})
    map[item_id] = turn
    map.shift while map.size > STS_RESPONSE_MAP_MAX
  end

  def sts_turn_for_item(state, payload)
    iid = payload["item_id"]
    return state[:turn] if iid.to_s.empty?

    (state[:items] || {})[iid] || state[:turn]
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
      sts_send_fragment(turn, delta, ws_session_id)
    end
    pending.clear
  end

  # All assistant fragments leave through here so the FIRST one of each turn
  # carries is_first — the client's fragment handler moves the streaming
  # temp-card to the bottom of the discourse only on that flag, and STS
  # fragments without it left the in-progress card stranded ABOVE the newer
  # user card (dogfood round 6 ordering complaint).
  def sts_send_fragment(turn, delta, ws_session_id)
    msg = { "type" => "fragment", "content" => delta }
    unless turn[:fragment_sent]
      turn[:fragment_sent] = true
      msg["is_first"] = true
    end
    send_or_broadcast(msg.to_json, ws_session_id)
  end

  # Grow-only in-place update of a turn's already-final user message (xAI
  # repeated cumulative completed). Mirrors the interrupted-card refresh:
  # canon text and the client card update together, position preserved.
  def sts_grow_user_message(turn, final, ws_session_id)
    msg = turn[:user_msg_ref]
    text = final.to_s.strip
    return if text.empty? || text.length <= msg["text"].to_s.length

    msg["text"] = text
    sync_session_state!
    send_or_broadcast({ "type" => "sts_card_text",
                        "mid" => msg["mid"],
                        "content" => text }.to_json, ws_session_id)
    # Keep the plain stt consumers in sync too (status line, temp-card
    # removal on the client).
    send_or_broadcast({ "type" => "stt", "content" => text, "logprob" => nil }.to_json, ws_session_id)
  end

  def sts_handle_transcription_completed(state, payload, ws_session_id)
    final = payload["transcript"].to_s
    Monadic::Utils::ExtraLogger.log do
      "[STS session=#{ws_session_id}] completed transcript=#{final.inspect}"
    end

    # Resolve by item id: utterance A's completed can arrive after
    # utterance B's speech_started replaced state[:turn] (P2-2). Opening
    # B's gate with A's completed would let B's assistant fragments out
    # before B's own user card — the exact inversion the gate exists for.
    turn = sts_turn_for_item(state, payload)
    # Synthesized completions (Gemini translation) carry no transcript —
    # the accumulated partial IS the final text. dup, not to_s: String#to_s
    # returns self, and the clear below would empty `final` through the
    # alias.
    final = turn[:user_partial].dup if final.strip.empty? && turn

    # xAI emits completed REPEATEDLY per utterance with growing cumulative
    # snapshots ("Nothing special." → "Nothing special so far. So good.").
    # One turn owns ONE user message: later snapshots grow it in place.
    # The grow path is strictly SAME-ITEM — a completed for a DIFFERENT
    # item landing on a turn whose user card is final is a fresh utterance
    # whose turn tracking fell behind (missed speech_started). Growing —
    # or worse, grow-only DROPPING when shorter — silently ate the spoken
    # text in dogfood (OpenAI: "The theme for many films…" vanished).
    if turn && turn[:user_msg_ref]
      iid = payload["item_id"]
      if iid && turn[:item_id] && iid == turn[:item_id]
        return sts_grow_user_message(turn, final, ws_session_id)
      end

      # Fresh utterance on a spent turn: open its own turn and fall through
      # to the normal card path.
      turn = sts_start_new_turn(state, SecureRandom.hex(8), ws_session_id)
    end
    sts_bind_item(state, payload["item_id"], turn) if turn

    turn[:user_partial].clear if turn

    # Trailing-silence hallucinations transcribe as bare punctuation ("."),
    # which made empty-looking user cards. No word content — no card.
    final = "" if final.gsub(/[[:punct:][:space:]]/, "").empty?

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
    turn = sts_turn_for_response(state, payload)
    return unless turn
    # A barge-in already finalized this turn as interrupted; the late
    # transcript.done for the cancelled response must not re-emit a card
    # (P2-4). But its transcript is MORE complete than what the card froze
    # at (audio deltas run ahead of transcript deltas), so update the
    # existing card's text in place — dogfood showed cards cut mid-word
    # while the heard audio ran further.
    return sts_update_interrupted_card(turn, payload, ws_session_id) if turn[:assistant_finalized]

    transcript = payload["transcript"].to_s
    transcript = turn[:assistant_transcript].dup if transcript.empty?

    # Make sure any still-gated fragments go out (in order) before the
    # final card supersedes them.
    sts_open_gate(turn, ws_session_id, reason: "done")
    sts_send_assistant_card(turn, transcript, ws_session_id,
                            interrupted: turn[:interrupted] == true)
  end

  def sts_handle_response_done(state, payload, ws_session_id)
    turn = sts_turn_for_response(state, payload)
    # THE GA cancel path (live-probed 2026-08-01): response.cancel answers
    # with response.done status="cancelled" and NO response.cancelled event
    # (the Azure GA reference is right; OpenAI's guide text is stale).
    # Interruption handling therefore lives here; the response.cancelled
    # reader branch remains only as defense for other deployments.
    if turn && payload.dig("response", "status").to_s == "cancelled"
      sts_finalize_interrupted_turn(state, turn, ws_session_id)
      sts_notify_cancelled(turn, ws_session_id)
    end
    # One accounting message per response: a cancelled response can emit both
    # response.cancelled and a response.done (status "cancelled"), and the
    # client sums every sts_audio_done it sees. With no resolvable turn
    # (response pruned from the map — near-unreachable) the guard cannot
    # apply and the message goes out with turn_id null: the tokens were
    # billed either way, and the client normalizes null turn ids.
    return if turn && turn[:done_sent]

    turn[:done_sent] = true if turn
    usage = payload.dig("response", "usage") || {}
    accounting = sts_usage_accounting(usage, state)

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
  # xAI bills per session MINUTE (idle included, ~$4.80/hr) and reports an
  # empty usage object (live-probed 2026-08-01) — so the estimate is wall
  # clock between accounting marks, not tokens. The first mark is set when
  # the bridge opens.
  # Gemini usageMetadata reports token counts but the Live-audio pricing is
  # not pinned here — report the counts and mark the entry unpriced rather
  # than invent a rate (a fabricated figure is worse than none).
  def sts_gemini_usage_accounting(usage)
    usage = {} unless usage.is_a?(Hash)
    {
      audio_input_tokens: usage["promptTokenCount"].to_i,
      audio_output_tokens: usage["responseTokenCount"].to_i,
      cached_tokens: 0,
      estimated_cost_usd: 0.0,
      billing_basis: "unpriced"
    }
  end

  def sts_xai_usage_accounting(state)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    last = state[:billing_mark] || now
    state[:billing_mark] = now
    minutes = [(now - last) / 60.0, 0.0].max

    {
      audio_input_tokens: 0,
      audio_output_tokens: 0,
      cached_tokens: 0,
      estimated_cost_usd: minutes * XAI_STS_RATE_PER_MINUTE,
      billing_basis: "per_minute"
    }
  end

  def sts_usage_accounting(usage, state = nil)
    return sts_xai_usage_accounting(state) if state && state[:provider] == "xai"
    return sts_gemini_usage_accounting(usage) if state && state[:provider] == "gemini"

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

    # Even when there is no transcript yet (nothing to put on a card), the
    # turn IS interrupted — a late transcript.done must not dress it up as a
    # completed turn (review P2-3).
    turn[:interrupted] = true
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

  # A late transcript.done for an already-finalized (interrupted) turn
  # carries the fullest text of what the model actually generated. Update
  # the persisted message and tell the client to refresh the card body in
  # place (re-sending html would move the card to the bottom — createCard
  # removes-then-appends on a duplicate mid).
  def sts_update_interrupted_card(turn, payload, ws_session_id)
    msg = turn[:assistant_msg]
    return unless msg

    full = payload["transcript"].to_s.strip
    return if full.empty? || full.length <= msg["text"].to_s.length

    msg["text"] = full
    sync_session_state!
    send_or_broadcast({
      "type" => "sts_card_text",
      "mid" => msg["mid"],
      "content" => full
    }.to_json, ws_session_id)
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

    # Finalize BEFORE broadcasting: a concurrent event arriving mid-send
    # must already see the turn as finalized (review P3-2).
    turn[:assistant_finalized] = true
    turn[:assistant_msg] = new_data

    send_or_broadcast({ "type" => "html", "content" => new_data }.to_json, ws_session_id)

    session[:messages] ||= []
    session[:messages] << new_data
    sync_session_state!
  end
end
