# frozen_string_literal: true

# Streaming STT (Phase 1 tracer bullet). Receives the per-frame PCM16
# chunks the client emits from AudioWorklet capture and the two control
# events (commit / abort). For now this only logs sizes — the real bridge
# to OpenAI's Realtime WebSocket lands in Phase 2.
#
# Wire format (client → server):
#   { "message": "AUDIO_CHUNK", "content": "<base64 PCM16 mono 24kHz>" }
#   { "message": "AUDIO_COMMIT" }
#   { "message": "AUDIO_ABORT" }

module WebSocketHelper
  def handle_audio_chunk(_connection, obj)
    ws_session_id = Thread.current[:websocket_session_id]
    content_len = obj["content"].to_s.length
    pcm_bytes_est = (content_len * 3.0 / 4).floor
    Monadic::Utils::ExtraLogger.log do
      "[AudioStream session=#{ws_session_id}] AUDIO_CHUNK: #{content_len} b64 chars (~#{pcm_bytes_est} PCM bytes)"
    end
  end

  def handle_audio_commit(_connection, _obj)
    ws_session_id = Thread.current[:websocket_session_id]
    Monadic::Utils::ExtraLogger.log { "[AudioStream session=#{ws_session_id}] AUDIO_COMMIT" }
  end

  def handle_audio_abort(_connection, _obj)
    ws_session_id = Thread.current[:websocket_session_id]
    Monadic::Utils::ExtraLogger.log { "[AudioStream session=#{ws_session_id}] AUDIO_ABORT" }
  end
end
