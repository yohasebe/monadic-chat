# WebSocket Sessions and Progress Messages

This page describes how the server addresses WebSocket messages to a browser tab, and how long-running operations report progress. The code is in `lib/monadic/utils/websocket.rb` and `lib/monadic/utils/websocket/connection_manager.rb`.

## Session ID

Each browser tab is its own session.

- `public/js/monadic/ws-tab-id.js` creates a tab ID (`crypto.randomUUID()`, or `tab-<time>-<random>` without it) and keeps it in `sessionStorage` under `monadicTabId`, so it survives a reload of the same tab and differs between tabs. `window.getMonadicTabId()` returns it.
- The WebSocket URL carries `?tab_id=<id>`. HTTP requests that act on a tab's chat (conversation import, attachments, the shared-folder panel, the Monadic state export, an app's graph) send the same `tab_id`.
- `handle_websocket_connection` uses `tab_id` as the session ID. A connection without `tab_id` uses `session[:websocket_session_id]` from the Rack session, creating a UUID the first time.
- The session ID is stored in `Thread.current[:websocket_session_id]` for the connection's thread. Threads started from it do not inherit it, so code that spawns threads reads it first and passes it on.

## Connection Tracking

| Structure | Contents |
|---|---|
| `@@ws_connections` | every open connection |
| `@@connections_by_session` | session ID → set of connections (a tab can briefly have two while it reconnects) |
| `@@session_state` | per session: messages, parameters, `chat_id`, the rest of the chat state, and a generation counter |
| `@@live_sessions` | session ID → the session object the tab's open connection runs its chat in |

Each new connection claims a generation (`claim_session_state`). `update_session_state` ignores writes from an older generation, so a closing connection cannot overwrite what its replacement did. On close the connection is removed from both lists, its live session is unregistered (only by the connection that registered it), and staged imports for the tab are dropped when no connection of the tab is left.

## Sending

| Method | Delivers to |
|---|---|
| `send_or_broadcast(message, session_id)` | the session's connections; all connections when there is no session ID |
| `WebSocketHelper.send_to_session(json, session_id)` | every connection of the session; dead connections are removed |
| `WebSocketHelper.send_audio_to_session(json, session_id)` | one connection of the session, so audio does not play twice |
| `send_error(content, session_id)` | the session, after removing account identifiers from provider error text |
| `send_to_client(connection, …)` | one connection (`pong` replies to `PING`) |
| `WebSocketHelper.broadcast_to_all(json)` | every connection |

Messages that belong to a chat go to its session. `broadcast_to_all` is used for:

- voice lists (`elevenlabs_voices`, `gemini_voices`, `mistral_voices`)
- component degradation notices (`system_info` from `DegradationNotifier`)
- MCP server status (`broadcast_mcp_status`)
- the fallback of the senders above when no session ID is known

## Progress Messages

A progress message is a `wait` fragment:

```json
{"type": "wait", "content": "…", "source": "…", "timestamp": 1234567890.1}
```

Optional fields: `minutes`, `elapsed`, `remaining`, `step_progress` (`{mode: "sequential"|"parallel", current, total, steps}`), `parallel_progress` (`{completed, total, task_names}`).

`WebSocketHelper.send_progress_fragment(fragment, session_id)` sends a Hash fragment whose `type` is `wait` or `fragment` through `broadcast_progress`, which adds `timestamp` and sends to the session (or to all connections without a session ID). Nothing is sent when `WEBSOCKET_PROGRESS_ENABLED` is `false`.

Senders:

| Sender | Interval | `source` |
|---|---|---|
| `Monadic::Utils::ProgressBroadcaster.with_progress` (media generation, Grok compaction, Conduit jobs) | 30 s by default | caller's name |
| OpenAI code agent (`start_progress_thread`) | `OPENAI_CODE_PROGRESS_INTERVAL` (60 s); only when the call timeout exceeds 120 s, a progress block is given and `OPENAI_CODE_PROGRESS_ENABLED` is not `false` | `OpenAICodeAgent` |
| Claude code agent | next step every 40 s | `ClaudeCodeAgent` |
| Grok code agent | next step every 30 s | `GrokCodeAgent` |
| `Monadic::Utils::StepProgress.send_step_progress` | per step | caller's name |
| Parallel dispatch, parallel Python execution, Second Opinion across providers | per completed task | `ParallelDispatch`, `ParallelCodeExecution`, `MultiProviderVerification` |

`ProgressBroadcaster` also copies each message into the Conduit job record (`Monadic::MCP::JobStore.report`) when the work runs in a Conduit job. Progress is best-effort: errors in progress threads are swallowed.

AutoForge passes a callback to the code agents that calls `send_progress_fragment` with the tab's session ID.

## Display

`websocket.js` hands `wait` messages to `WsToolHandler.handleWait` (`ws-tool-handler.js`). For a `source` that names a known agent or contains `Agent`, `Generator` or `Analyzer`, the message is shown in the assistant's temporary card (`#temp-card`), created if needed:

1. with `step_progress`: the current step (and the elapsed minutes when `minutes` is above 0) and a list of steps with check marks or spinners;
2. otherwise with `minutes`: a localized phase label chosen by elapsed minutes, the elapsed time, and the remaining time when 1–5 minutes remain;
3. otherwise with `parallel_progress` (`ParallelDispatch`, `MultiProviderVerification`): "completed / total" and the task list;
4. otherwise the content with an icon.

## Configuration

`~/monadic/config/env`:

| Key | Default | Effect |
|---|---|---|
| `WEBSOCKET_PROGRESS_ENABLED` | `true` | `false` stops all progress messages |
| `OPENAI_CODE_PROGRESS_ENABLED` | `true` | `false` stops the OpenAI code agent's progress thread |
| `OPENAI_CODE_PROGRESS_INTERVAL` | `60` | seconds between the OpenAI code agent's messages |
| `EXTRA_LOGGING` | `false` | logs sends, session registration and dead-connection cleanup |

## Troubleshooting

- **No progress shown**: check that the sender passes the tab's session ID (read from `Thread.current[:websocket_session_id]` before starting a thread); with `EXTRA_LOGGING`, `No connections found for session …` means the ID does not match an open connection.
- **Message shown in another tab**: the sender used `broadcast_to_all`, or passed a nil session ID, which falls back to it.

## Tests

- `spec/unit/utils/progress_broadcaster_spec.rb`, `spec/unit/utils/step_progress_spec.rb`
- `spec/unit/shared_tools/parallel_dispatch_spec.rb`, `spec/unit/shared_tools/parallel_python_execution_spec.rb`
- `spec/unit/workspace/new_chat_state_spec.rb` (session state and generations)
- `test/frontend/ws-tool-handler.test.js`
