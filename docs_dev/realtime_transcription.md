# Realtime Streaming Transcription (Internal Architecture)

Internal design notes for the streaming STT path introduced in beta.16
(`gpt-realtime-whisper ⚡`). The public-facing description lives in
`docs/basic-usage/message-input.md` § "Realtime Streaming Transcription".
This document captures the implementation choices and traps a future
maintainer needs to understand before touching the code.

## Scope

OpenAI Realtime Transcription only. Other providers (Gemini, xAI,
ElevenLabs, Cohere, Mistral, Whisper-1) remain on the batch path and
will until they ship a transcription-only realtime endpoint. The
chat-oriented bidirectional Live APIs (Gemini Live, etc.) are
deliberately out of scope — they bundle STT with LLM cycles, charge
for LLM tokens, and require prompt-engineering "only transcribe"
which makes them strictly inferior to the batch path for our use case.

## Data flow

```
recording.js                Monadic WS                bridge task
   │  AUDIO_CHUNK   ─────►   cmd_queue ◄──── writer fiber ──► OpenAI WS
   │  AUDIO_COMMIT  ─────►   cmd_queue                       (input_audio_buffer.*)
   │  AUDIO_ABORT   ─────►   cmd_queue                              │
   │                                       reader fiber ◄───────────┘
   │  stt_partial   ◄──────  send_or_broadcast ◄── reader (delta events)
   │  stt           ◄──────  send_or_broadcast ◄── reader (completed event)
```

### Client side (`docker/services/ruby/public/js/monadic/`)

- `audio-pcm-encoder-worklet.js` — `AudioWorkletProcessor` that pulls
  Float32 mic samples from the AudioContext, decimates to 24 kHz mono,
  converts to Int16 LE, and posts ~100 ms `ArrayBuffer` chunks via
  `port.postMessage`. **Not** part of `monadic.bundle.min.js`; loaded
  as a separate static asset because AudioWorklet scripts must come
  from their own URL.
- `recording.js`
  - `startAudioStream()` constructs the AudioContext + AudioWorkletNode,
    sends each PCM chunk over the existing Monadic WebSocket as a
    `{ message: "AUDIO_CHUNK", content: <base64>, stt_model, lang_code }`
    frame. Lifecycle parallels the legacy `startAudioCapture()` so the
    rest of the recording UX (waveform, Stop button, silence detection
    no-op for the streaming path) stays unchanged.
  - `isRealtimeSttEnabled()` gates the worklet path on
    `window.modelSpec[selected_stt_model].supports_realtime_streaming`.
    `localStorage.stt_realtime === '1'` survives as a debug back door
    for development.
  - On Stop → `AUDIO_COMMIT`; on silence-abort → `AUDIO_ABORT`.
  - Enter-key capture-phase listener delegates to the voice button
    click handler while a streaming session is active, so Enter
    commits the audio instead of inserting a newline or
    firing easy-submit on a partial.
- `ws-session-handler.js`
  - `handleSTTPartial(data)` renders the cumulative partial transcript
    into `#message-partial-overlay` as a two-span structure: an
    invisible `.stt-mirror` carrying the textarea's current value
    (re-read on every delta) followed by a grey-italic `.stt-partial`
    holding the partial text itself. The textarea's `value` is never
    mutated during streaming, so user typing during recording is
    preserved.
  - `handleSTT(data)` checks
    `overlay.classList.contains('is-active')` to know streaming was in
    progress, appends the final transcript to `messageEl.value`
    (preserving any user-typed text), and tears down the overlay. If
    the overlay is not active, falls through to the legacy
    `messageEl.value + " " + content` batch path.
  - `clearSTTPartialOverlay()` is exported via `window.WsSessionHandler`
    for `recording.js` to call from the abort/start paths.

### Server side (`docker/services/ruby/lib/monadic/utils/websocket/`)

- `audio_stream_handler.rb` is mixed into `WebSocketHelper`. Three
  message handlers (`handle_audio_chunk`, `handle_audio_commit`,
  `handle_audio_abort`) enqueue commands onto a per-session
  `Async::Queue`; an `Async` bridge task spawned on the first
  `AUDIO_CHUNK` owns the upstream WS to OpenAI.
- The bridge task has two fibers sharing the OpenAI WS connection:
  - **Reader fiber** (`realtime_reader_loop`) — pulls frames from
    OpenAI, dispatches on `payload["type"]`:
    - `session.updated` → signals the `ready` notification
    - `conversation.item.input_audio_transcription.delta` → appends
      to `state[:partial]`, forwards as `stt_partial` to the client
    - `conversation.item.input_audio_transcription.completed` →
      forwards as `stt` (final), signals the `done` notification
    - `error` → forwards as `error`, signals `done`
  - **Writer fiber** (`realtime_writer_loop`) — pulls commands from
    `cmd_queue`:
    - `:append` chunks before `session.updated` are buffered locally
      (Phase 0 trap, see below); after the ack they are flushed and
      subsequent chunks pass through directly.
    - `:commit` waits up to `REALTIME_STT_COMMIT_TIMEOUT` (15 s) for
      `session.updated`, flushes any pending chunks, sends
      `input_audio_buffer.commit`, then waits for `.completed`
      (same timeout).
    - `:abort` breaks the loop and lets the bridge tear down.

## Traps captured in this implementation

### 1. HTTP/1.1 ALPN is mandatory

`async-http` negotiates HTTP/2 by default via TLS ALPN. The WebSocket
upgrade handshake (RFC 6455) exists only in HTTP/1.1 — there is no
equivalent in HTTP/2 — so without explicit downgrade OpenAI's edge
replies with `405 Method Not Allowed` and the connection never
becomes a WS. The endpoint must be constructed with
`alpn_protocols: ["http/1.1"]`:

```ruby
endpoint = Async::HTTP::Endpoint.parse(
  REALTIME_STT_URL, alpn_protocols: ["http/1.1"]
)
```

Pinned by the invariant spec
`spec/unit/dsl/websocket_alpn_consistency_spec.rb`, which walks
`lib/**/*.rb` and fails any `Async::HTTP::Endpoint.parse` call on a
`wss://` URL that omits the kwarg.

### 2. Audio buffer must follow `session.updated`

OpenAI processes events in receive order. Sending
`input_audio_buffer.append` before the `session.updated` ack
associates the buffer with the not-yet-configured session, and the
subsequent commit returns `input_audio_buffer_commit_empty`. The
writer fiber therefore buffers `:append` commands locally until
`state[:session_ready]` flips true (signalled by the reader fiber on
the `ready` notification), then flushes and switches to
pass-through.

### 3. Model-specific `turn_detection` handling

- `gpt-realtime-whisper` **rejects** any `turn_detection` value
  ("Turn detection is not supported for this transcription model").
  Omit the key from `session.update`.
- `gpt-4o-transcribe` and `gpt-4o-mini-transcribe` default to
  `server_vad` with a 200 ms silence threshold, which auto-commits
  on every short pause and clashes with our user-controlled Stop
  semantics. Send `turn_detection: null` to disable.
- `session.update` is sparse-merge: omitting a key means "unchanged
  from server default", not "disable". So explicit `null` is the
  correct way to turn server VAD off, not omission.

### 4. Undocumented API params can corrupt sibling fields

Unrelated but pinned in the same release: the OpenAI
`/v1/audio/speech` endpoint silently accepted an undocumented
`language` field and used it to alter the semantics of the
`instructions` field — causing `gpt-4o-mini-tts` to speak the
instructions aloud (e.g. "Speak in a calm voice…" was read by the
voice). Lesson: undocumented params are not silent-ignored, they can
have side effects on sibling fields. Captured separately in
`feedback_undocumented_api_params.md`.

### 5. Bundled JS handler registration

`ws-session-handler.js` is part of `monadic.bundle.min.js`. Adding a
new function in the file is necessary but not sufficient — the
dispatch surface (`window.WsSessionHandler = { ... }` at the bottom
of the file) must list it explicitly, or the WS message dispatcher
in `websocket.js` cannot find it. Documented in
`feedback_websocket_handler_paths.md`.

## Capability flag SSOT

A streaming-capable STT model declares `supports_realtime_streaming: true`
in `model_spec.js`:

```js
"gpt-realtime-whisper": {
  "stt_capability": true,
  "supports_realtime_streaming": true
}
```

Both the JS gate (`recording.js#isRealtimeSttEnabled`) and the Ruby
accessor (`Monadic::Utils::ModelSpec.supports_realtime_streaming?`)
read this single flag. Adding a future streaming-capable STT model
is a one-line capability change; no UI or routing surgery required.

## Test surface

- `test/frontend/ws-session-handler.test.js` — overlay state-machine
  cases for `handleSTTPartial` / `handleSTT` /
  `clearSTTPartialOverlay`. Covers empty start, separator insertion,
  user-typing-during-stream, multi-delta overwrite, commit-from-active,
  user-typed-then-commit, explicit clear.
- `test/frontend/recording-stt-gate.test.js` — capability gate
  semantics. The function is mirrored from `recording.js` (which
  cannot be required cleanly in jsdom due to top-level DOM
  attachments); the docstring at the top of the spec file points
  back to the source.
- `spec/unit/utils/websocket/audio_stream_handler_spec.rb` — wire
  contract for `session.update` payload shape and
  `parse_realtime_payload` edge cases. Mocks the WS connection at
  the `write` / `flush` level; does not start the async bridge.
- `spec/unit/dsl/websocket_alpn_consistency_spec.rb` — grep-based
  invariant locking out the HTTP/2 ALPN trap.

The full async bridge (queue → fibers → real WS) is exercised end-to-end
by manual dogfood per the verification block in
`tmp/memo/realtime-transcription-plan.md` § Phase 2. An integration
suite with a mocked OpenAI WS is out of scope until/unless a
regression-blocking concern motivates one.

## Future extension points

- Adding `gpt-4o-transcribe` (or future OpenAI variants) to the
  streaming path: set `supports_realtime_streaming: true` in
  `model_spec.js`; the bridge already handles the
  `turn_detection: null` requirement for non-whisper models.
- A user-controlled "always batch" toggle: not currently needed
  because the ⚡ glyph + capability flag combination is already
  user-visible and explicit. Revisit if dogfood reveals confusion.
- Server VAD-driven multi-segment dictation: feasible with
  `gpt-4o-transcribe` and `turn_detection: { type: "server_vad" }`
  — would produce multiple `.completed` events per session. Would
  require recasting `handleSTT` to append rather than commit-then-
  clear. Out of scope for v1.
- Other providers when they ship transcription-only realtime
  endpoints: add a provider-specific adapter to
  `audio_stream_handler.rb`. Reuse the same client wire format
  (`AUDIO_CHUNK` / `AUDIO_COMMIT` / `AUDIO_ABORT`); add a small
  adapter module per provider for the upstream WS protocol.
