# Safe WebSocket Send (`safeWsSend`)

Every WebSocket message from the web UI goes through `window.safeWsSend`, defined in `public/js/monadic/monadic-ws.js`. Direct `ws.send(...)` calls outside that file fail `lint:bare_ws_send` (see [Anti-Pattern Lints](../developer/anti_pattern_lints.md)).

## API

```js
const r = window.safeWsSend({ message: 'RESET' });
if (r.sent || r.queued) {
  // In flight; the UI can move on.
} else {
  // safeWsSend has already told the user. Do not close dialogs or
  // otherwise move the UI forward.
}
```

Return value: `{ sent, queued, state, deduped?, error? }`, where `state` is the socket state (`OPEN`, `CONNECTING`, `CLOSING`, `CLOSED` or `NULL`).

Options (`safeWsSend(payload, opts)`):

| Option | Default | Meaning |
|---|---|---|
| `idempotent` | From the message type (see below) | Whether the message may be queued and replayed after a reconnect |
| `allowReconnect` | Same as `idempotent` | Whether a non-OPEN socket queues the message and reconnects, or fails at once |
| `alertOnFail` | `true` | Tell the user when the message cannot be sent |
| `silentDrop` | `false` | Fail without telling the user and without the reconnecting notice (for background sends) |

## Behavior

- **OPEN**: the message is sent.
- **Not OPEN, message not replayable**: it fails at once with `queued: false`, and the user sees "Connection lost. Please retry." (`ui.messages.connectionLost`) unless `alertOnFail` is false or `silentDrop` is set.
- **Not OPEN, message replayable**: it is queued, and the user sees "Reconnecting…" (`ui.messages.reconnecting`) unless `silentDrop` is set.
  - With `CONNECTING` or `CLOSING`, the current transition is awaited.
  - With `CLOSED` or no socket, a reconnect is started through `window.connect_websocket()`, unless one is already running (`window._wsIsConnecting`).
- When the socket opens, `websocket.js` calls `window.MonadicWs.drainQueue()`, which sends the queued messages in order. If the socket closes during the drain, the rest stay queued.

Queue limits:

- At most 20 entries. When full, the oldest `PING` is dropped; if there is none, the new message is refused (`error: queue full`).
- Entries older than 30 seconds are dropped.
- An identical payload queued within 500 ms is not queued again (`deduped: true`).
- A payload that cannot be serialized to JSON is refused.

## Replayable Message Types

These message types are replayed after a reconnect (`IDEMPOTENT_MESSAGE_TYPES` in `monadic-ws.js`):

`PING`, `RESET`, `LOAD`, `HTML`, `CHECK_TOKEN`, `CANCEL`, `DELETE`, `EDIT`, `STOP_TTS`, `UPDATE_PARAMS`, `UPDATE_LANGUAGE`, `PDF_TITLES`, `DELETE_PDF`, `DELETE_ALL_PDFS`, `PRIVACY_REGISTRY`, `LIBRARY_SAVE`, `LIBRARY_LIST`, `LIBRARY_DELETE`, `LIBRARY_STATS`, `LIBRARY_GET_CONVERSATION`, `LIBRARY_RAG_QUERY`, `LIBRARY_RAG_TOGGLE`, `LIBRARY_RENAME`, `LIBRARY_SET_SCOPE`

Replaying does not make a handler idempotent: a `LIBRARY_SAVE` without a `conversation_id` creates a new entry each time it runs. Every other type is not replayed. Examples: a chat message (no `message` field), `SYSTEM_PROMPT` and `SAMPLE` (each adds a message), `AI_USER_QUERY` and `LIBRARY_SUGGEST_TITLE` (each calls a model), `PLAY_TTS`, `TTS` and `AUDIO` (each calls a speech service), `PRIVACY_EXPORT` (each makes a new download).

When you add a message type, add it to `IDEMPOTENT_MESSAGE_TYPES` only if running its handler twice leaves the same state as running it once.

## Tests

The Jest tests in `test/frontend/` cover the send paths, the queue limits and the drain. `window.MonadicWs` exposes `_peekQueue`, `_resetQueueForTests` and `_config` for them.
