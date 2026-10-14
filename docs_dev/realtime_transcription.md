# Realtime Streaming Transcription

Speech input can stream audio to OpenAI's Realtime transcription endpoint and show the transcript while the user speaks. The public description is in `docs/basic-usage/message-input.md`. Other STT models use the batch path (`stt_api_request`).

## When the Streaming Path Is Used

`SttGate.isRealtimeSttEnabled()` (`public/js/monadic/stt-gate.js`) decides when Speech Input starts:

1. The selected STT model must be an OpenAI model: its `stt_provider` in `model_spec.js` is `openai` (or absent). A model without an entry is non-OpenAI when its name starts with one of `NON_OPENAI_STT_PREFIXES`, which match the Ruby fallback `ModelSpec.stt_provider_from_name`.
2. The model has `supports_realtime_streaming: true`, or `localStorage.stt_realtime` is `'1'` (development override).
3. If anything is missing (no `#stt-model`, no `window.modelSpec`, `localStorage` throws), the batch path is used.

The STT selector marks the streaming model with ⚡ (`views/index.erb`). When the selected chat model has `supports_speech_to_speech`, the same audio stream is used for the speech-to-speech session regardless of the STT model (`SttGate.isStsModelSelected()`).

If `startAudioStream()` fails, the client shows "Realtime STT unavailable; falling back to standard mode" and records with the batch path.

## Client

- `audio-pcm-encoder-worklet.js`: an `AudioWorkletProcessor` that resamples the microphone to 24 kHz mono, converts to Int16 little-endian and posts 100 ms chunks. It is loaded from its own URL (`/js/monadic/audio-pcm-encoder-worklet.js`), not from the bundle.
- `recording.js`, `startAudioStream()`: connects microphone → worklet → a muted gain node, and sends each chunk as

  ```json
  {"message": "AUDIO_CHUNK", "content": "<base64 PCM16>", "stt_model": "<model>", "lang_code": "<code or auto>", "chat_model": "<model>"}
  ```

  The STT model is the selected one, otherwise `providerDefaults.openai.audio_transcription[0]`. The silence detector only drives the waveform; silence does not stop the stream.
- **Stop** (or Enter while streaming, through a capture-phase `keydown` listener) sends `AUDIO_COMMIT` and tears down the audio graph.
- `ws-session-handler.js`:
  - `handleSTTPartial` writes into `#message-partial-overlay`: an invisible `.stt-mirror` span with the textarea's current text, then a `.stt-partial` span with the partial transcript. The textarea itself is not changed, so the user can type while speaking.
  - `handleSTT`: when the overlay is active, the final transcript is appended to the textarea (except in a speech-to-speech session) and the overlay is cleared; the rest (buttons, spinner, easy submit) is done by `handleSTTMessage` with `_alreadyAppended`. Without an active overlay, the transcript is appended as in the batch path.
  - `clearSTTPartialOverlay` is exported on `window.WsSessionHandler`.

## Server

`websocket.rb` routes `AUDIO_CHUNK`, `AUDIO_COMMIT` and `AUDIO_ABORT` through `route_audio_event`: to the speech-to-speech bridge when the chat model (from `chat_model`, checked against `model_spec.js`) supports speech-to-speech, otherwise to `lib/monadic/utils/websocket/audio_stream_handler.rb`.

### Bridge

The first `AUDIO_CHUNK` of a session creates `session[:_realtime_stt]` (command queue, partial transcript, ready/done conditions, model, language) and starts an `Async` bridge task:

1. Without `OPENAI_API_KEY`, the client gets an error.
2. The task takes a slot from a per-process semaphore whose size is `REALTIME_STT_MAX_CONCURRENT` from the config (default 8), read when the semaphore is first created.
3. It opens `wss://api.openai.com/v1/realtime?intent=transcription` over HTTP/1.1 (`alpn_protocols: ["http/1.1"]`) and sends `session.update`:
   - `type: "transcription"`, input format `audio/pcm` at 24000 Hz, `noise_reduction: near_field`, the transcription model, and `language` unless the language is empty or `auto`;
   - `turn_detection: null`, except for models whose name starts with `REALTIME_STT_DEFAULT_MODEL`, which reject the key.

A retired model in `stt_model` is replaced by its successor (`ModelSpec.resolve_deprecated_model`); an empty value uses `REALTIME_STT_DEFAULT_MODEL`.

### Reader and Writer

| Upstream event | Action |
|---|---|
| `session.updated` | mark the session ready |
| `conversation.item.input_audio_transcription.delta` | append to the partial transcript; send `{"type": "stt_partial", "content": <partial so far>}` |
| `conversation.item.input_audio_transcription.completed` | send `{"type": "stt", "content": <transcript>, "logprob": null}` |
| `error` | send an error `Realtime STT: <message>` |

| Command | Action |
|---|---|
| `:append` | held locally until `session.updated`, then flushed; afterwards sent directly as `input_audio_buffer.append` |
| `:commit` | wait up to `REALTIME_STT_COMMIT_TIMEOUT` (15 s) for `session.updated`, flush, send `input_audio_buffer.commit`, wait up to 15 s for `.completed`, close |
| `:abort` | close |

Errors sent to the client: `No audio captured` (commit without chunks), `Realtime STT session setup timeout`, `Realtime STT timed out waiting for transcript`, `Realtime STT failed: …`. `AUDIO_ABORT` signals both conditions first, so an abort does not wait for a timeout and produces no timeout error. Messages go to the tab's session (`send_or_broadcast`, `send_error`). When the bridge ends, `session[:_realtime_stt]` is cleared.

Only models that stream emit `.delta` events; others return a single `.completed` after the commit, so no partial transcript is shown.

## Capability Flag

`supports_realtime_streaming: true` in `model_spec.js` makes an STT model eligible. It is read by the JS gate and by `Monadic::Utils::ModelSpec.supports_realtime_streaming?`. `listModels` (`utilities.js`) keeps such models out of chat model lists.

## Tests

- `test/frontend/ws-session-handler.test.js`: overlay handling in `handleSTTPartial`, `handleSTT`, `clearSTTPartialOverlay`
- `test/frontend/recording-stt-gate.test.js`: the gate, including that non-OpenAI models never stream
- `test/frontend/stt-gate-prefix-parity.test.js`: `NON_OPENAI_STT_PREFIXES` matches the Ruby prefixes
- `spec/unit/utils/websocket/audio_stream_handler_spec.rb`: `session.update` payload and `parse_realtime_payload`
- `spec/unit/dsl/websocket_alpn_consistency_spec.rb`: every `Async::HTTP::Endpoint.parse` on a `wss://` URL sets HTTP/1.1 ALPN
