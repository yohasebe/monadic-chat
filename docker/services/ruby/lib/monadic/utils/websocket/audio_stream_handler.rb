# frozen_string_literal: true

# Streaming STT bridge to OpenAI's Realtime transcription endpoint.
#
# Client → server wire format:
#   { "message": "AUDIO_CHUNK", "content": "<b64 PCM16 mono 24kHz>",
#     "stt_model": "<model>", "lang_code": "<bcp47 or 'auto'>" }
#   { "message": "AUDIO_COMMIT" }
#   { "message": "AUDIO_ABORT" }
#
# Server → client (added by this handler):
#   { "type": "stt_partial", "content": "<accumulated transcript so far>" }
# Followed by the existing batch-path message on final transcript:
#   { "type": "stt", "content": "<final transcript>", "logprob": null }
# Or, on failure:
#   { "type": "error", "content": "<message>" }
#
# Phase 0 spike findings carried into this bridge:
#  * Force HTTP/1.1 ALPN — async-http picks HTTP/2 by default and OpenAI 405s.
#  * Server processes events in receive order: hold AUDIO_CHUNK locally until
#    session.updated arrives, then flush. Otherwise the buffer is associated
#    with the not-yet-configured session and commit fails empty.

require 'async'
require 'async/queue'
require 'async/notification'
require 'async/http/endpoint'
require 'async/websocket/client'
require 'json'

module WebSocketHelper
  REALTIME_STT_URL = "wss://api.openai.com/v1/realtime?intent=transcription"
  # Default to the natively-streaming whisper variant so deltas flow during
  # the open buffer. `gpt-4o-transcribe` is non-streaming and only emits a
  # final `.completed` after explicit commit — incompatible with the
  # realtime-partials UX the streaming path is meant to deliver.
  REALTIME_STT_DEFAULT_MODEL = "gpt-realtime-whisper"
  REALTIME_STT_COMMIT_TIMEOUT = 15 # seconds — bound the wait for `.completed`

  def handle_audio_chunk(_connection, obj)
    state = ensure_realtime_stt_state!(obj)
    queue = state[:cmd_queue]
    return unless queue

    queue.enqueue([:append, obj["content"].to_s])
  end

  def handle_audio_commit(_connection, _obj)
    state = session[:_realtime_stt]
    unless state && state[:cmd_queue]
      # Commit arrived without any prior AUDIO_CHUNK — the bridge was
      # never opened, so no `stt` or `error` event will reach the client
      # via the normal path. Surface a no-audio error so the client UI
      # can reset (spinner / disabled buttons would otherwise persist).
      forward_stt_error("No audio captured", Thread.current[:websocket_session_id])
      return
    end

    state[:cmd_queue].enqueue([:commit])
  end

  def handle_audio_abort(_connection, _obj)
    state = session[:_realtime_stt]
    return unless state && state[:cmd_queue]

    state[:cmd_queue].enqueue([:abort])
  end

  private

  def ensure_realtime_stt_state!(obj)
    state = session[:_realtime_stt]
    return state if state && state[:cmd_queue] && state[:bridge_task] && !state[:bridge_task].finished?

    model = (obj["stt_model"].to_s.strip.empty? ? nil : obj["stt_model"]) || REALTIME_STT_DEFAULT_MODEL
    lang  = obj["lang_code"].to_s
    lang  = nil if lang.empty? || lang == "auto"

    state = {
      cmd_queue: Async::Queue.new,
      partial: +"",
      session_ready: false,
      ready: Async::Notification.new,
      done: Async::Notification.new,
      model: model,
      lang: lang
    }
    session[:_realtime_stt] = state

    ws_session_id = Thread.current[:websocket_session_id]
    state[:bridge_task] = Async do
      run_realtime_stt_bridge!(state, ws_session_id)
    end
    state
  end

  def run_realtime_stt_bridge!(state, ws_session_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    if api_key.nil? || api_key.empty?
      forward_stt_error("OPENAI_API_KEY is not configured", ws_session_id)
      return
    end

    Monadic::Utils::ExtraLogger.log do
      "[AudioStream session=#{ws_session_id}] bridge open model=#{state[:model]} lang=#{state[:lang] || 'auto'}"
    end

    endpoint = Async::HTTP::Endpoint.parse(REALTIME_STT_URL, alpn_protocols: ["http/1.1"])
    headers = { "Authorization" => "Bearer #{api_key}" }

    Async::WebSocket::Client.connect(endpoint, headers: headers) do |conn|
      send_realtime_session_update(conn, state)

      reader = Async do
        realtime_reader_loop(conn, state, ws_session_id)
      end

      realtime_writer_loop(conn, state, ws_session_id)
      reader.stop
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log do
      "[AudioStream session=#{ws_session_id}] bridge error: #{e.class}: #{e.message}"
    end
    forward_stt_error("Realtime STT failed: #{e.message}", ws_session_id)
  ensure
    session[:_realtime_stt] = nil if session[:_realtime_stt].equal?(state)
  end

  def send_realtime_session_update(conn, state)
    audio_input = {
      format: { type: "audio/pcm", rate: 24_000 },
      transcription: { model: state[:model] },
      noise_reduction: { type: "near_field" }
    }
    audio_input[:transcription][:language] = state[:lang] if state[:lang]

    # Turn detection handling differs by model:
    #   * gpt-realtime-whisper: REJECTS any turn_detection value (Phase 0
    #     spike: "Turn detection is not supported for this transcription
    #     model"). Omit the key.
    #   * gpt-4o-transcribe / gpt-4o-mini-transcribe: server defaults to
    #     `{type: server_vad, silence_duration_ms: 200}` which auto-commits
    #     on every ~200 ms pause. Send explicit `null` to disable — omitting
    #     the key is a no-op under session.update's sparse-merge semantics.
    unless state[:model].to_s.start_with?("gpt-realtime-whisper")
      audio_input[:turn_detection] = nil
    end

    payload = {
      type: "session.update",
      session: {
        type: "transcription",
        audio: { input: audio_input }
      }
    }
    body = payload.to_json
    Monadic::Utils::ExtraLogger.log { "[AudioStream] session.update payload: #{body}" }
    conn.write(body)
    conn.flush
  end

  def realtime_reader_loop(conn, state, ws_session_id)
    while (msg = conn.read)
      payload = parse_realtime_payload(msg)
      next unless payload

      event_type = payload["type"]
      # Log every server event type so we can see whether `.delta` is
      # actually being emitted for the model we asked for. With real
      # speech, whisper-class models should emit a steady stream of
      # `.delta` events; 4o-transcribe only emits `.completed`.
      Monadic::Utils::ExtraLogger.log do
        "[AudioStream session=#{ws_session_id}] event=#{event_type}"
      end

      case event_type
      when "session.updated"
        state[:session_ready] = true
        state[:ready].signal
      when "conversation.item.input_audio_transcription.delta"
        delta = payload["delta"].to_s
        next if delta.empty?
        state[:partial] << delta
        Monadic::Utils::ExtraLogger.log do
          "[AudioStream session=#{ws_session_id}] delta=#{delta.inspect} partial_len=#{state[:partial].length}"
        end
        send_or_broadcast({ "type" => "stt_partial", "content" => state[:partial].dup }.to_json, ws_session_id)
      when "conversation.item.input_audio_transcription.completed"
        final = payload["transcript"].to_s
        Monadic::Utils::ExtraLogger.log do
          "[AudioStream session=#{ws_session_id}] completed transcript=#{final.inspect}"
        end
        state[:partial].clear
        send_or_broadcast({ "type" => "stt", "content" => final, "logprob" => nil }.to_json, ws_session_id)
        state[:done].signal
      when "error"
        err = payload["error"] || {}
        Monadic::Utils::ExtraLogger.log do
          "[AudioStream session=#{ws_session_id}] OpenAI error: #{err.inspect}"
        end
        forward_stt_error("Realtime STT: #{err['message'] || 'unknown error'}", ws_session_id)
        state[:done].signal
      end
    end
  rescue Async::Stop
    # writer requested stop; not an error
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log do
      "[AudioStream session=#{ws_session_id}] reader exited: #{e.class}: #{e.message}"
    end
  end

  def realtime_writer_loop(conn, state, ws_session_id)
    pending = []
    queue = state[:cmd_queue]

    loop do
      cmd = queue.dequeue
      break if cmd.nil?
      type, payload = cmd

      case type
      when :append
        if state[:session_ready]
          flush_pending_appends(conn, pending)
          conn.write({ type: "input_audio_buffer.append", audio: payload }.to_json)
          conn.flush
        else
          pending << payload
        end
      when :commit
        unless wait_for_ready(state, ws_session_id)
          break
        end
        flush_pending_appends(conn, pending)
        conn.write({ type: "input_audio_buffer.commit" }.to_json)
        conn.flush
        wait_for_completion(state, ws_session_id)
        break
      when :abort
        Monadic::Utils::ExtraLogger.log { "[AudioStream session=#{ws_session_id}] abort" }
        break
      end
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log do
      "[AudioStream session=#{ws_session_id}] writer error: #{e.class}: #{e.message}"
    end
  end

  def flush_pending_appends(conn, pending)
    return if pending.empty?
    pending.each do |chunk|
      conn.write({ type: "input_audio_buffer.append", audio: chunk }.to_json)
    end
    conn.flush
    pending.clear
  end

  def wait_for_ready(state, ws_session_id)
    return true if state[:session_ready]
    Async::Task.current.with_timeout(REALTIME_STT_COMMIT_TIMEOUT) do
      state[:ready].wait
    end
    true
  rescue Async::TimeoutError
    Monadic::Utils::ExtraLogger.log do
      "[AudioStream session=#{ws_session_id}] session.updated never arrived; aborting commit"
    end
    forward_stt_error("Realtime STT session setup timeout", ws_session_id)
    false
  end

  def wait_for_completion(state, ws_session_id)
    Async::Task.current.with_timeout(REALTIME_STT_COMMIT_TIMEOUT) do
      state[:done].wait
    end
  rescue Async::TimeoutError
    Monadic::Utils::ExtraLogger.log do
      "[AudioStream session=#{ws_session_id}] commit completion timed out after #{REALTIME_STT_COMMIT_TIMEOUT}s"
    end
    forward_stt_error("Realtime STT timed out waiting for transcript", ws_session_id)
  end

  def parse_realtime_payload(msg)
    raw = msg.respond_to?(:buffer) ? msg.buffer : msg.to_s
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def forward_stt_error(message, ws_session_id)
    payload = { "type" => "error", "content" => message }.to_json
    send_or_broadcast(payload, ws_session_id)
  end
end
