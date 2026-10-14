# Tab Isolation

Each browser tab has its own conversation, parameters and chat state. The tab identifier is the server-side session key.

## Tab ID

`ws-tab-id.js`:

- `ensureMonadicTabId()` reads `monadicTabId` from sessionStorage, or creates one (`crypto.randomUUID()`, otherwise `tab-<time>-<random>`) and stores it. The ID survives reloads of the tab and differs between tabs; it is gone when the tab closes.
- It runs once when the bundle loads and sets `window.monadicTabId`. `window.getMonadicTabId` re-reads it; `window.monadicTabQuery()` returns `?tab_id=<id>` for HTTP requests that read the tab's chat (export, the app's graph, `/attachments`).
- `connect_websocket()` (`websocket.js`) appends `tab_id=<id>` to the WebSocket URL.

## Server Side

On a WebSocket connection (`lib/monadic/utils/websocket.rb`):

1. `ws_session_id` is the `tab_id`. Without one, the Rack session's `websocket_session_id` is used, or a new UUID.
2. `claim_session_state` gives the connection a generation number (`session[:_ws_generation]`).
3. The chat state copied from the Rack session is cleared, and `session[:messages]` and `session[:parameters]` are set empty. The Rack session (cookie) is shared by all tabs, so nothing of a chat is taken from it.
4. `fetch_session_state(ws_session_id)` restores the tab's messages and parameters. When the saved `chat_id` is valid, the rest of the chat's data (`chat_state`: tool results, Session Context, privacy registry) is restored too; `Chats.resume!` continues that chat or starts a new one.
5. `sync_session_state!` saves the state, and `register_live_session` records the connection's session object for HTTP requests (`live_session(tab_id)`).

The store is `WebSocketHelper`'s `@@session_state` (`lib/monadic/utils/websocket/connection_manager.rb`), guarded by a mutex:

| Method | Does |
|---|---|
| `update_session_state(id, messages:, parameters:, chat_id:, chat_state:, generation:)` | Saves deep copies; ignores a write whose generation is older than the latest, so a replaced connection closing cannot undo the new one's changes. `chat_id` and `chat_state` are kept when not given |
| `fetch_session_state(id)` | Returns deep copies, or nil |
| `register_live_session` / `unregister_live_session` | Tracks the live session per tab; only the registering generation removes it |
| `live_chat_ids` | Chats open in some tab |

The WebSocket handlers call `sync_session_state!` when they change messages or parameters. Entries in `@@session_state` stay for the life of the server process.

On every connection the server sends `parameters` (even when empty) and then `past_messages`, so the browser drops state it does not have on the server. See [Session Restoration](../session_restoration_improvements.md).

## Browser Storage

Tab-specific data (the tab ID and `SessionState`) is in sessionStorage, which is per tab. localStorage is shared by all tabs and is not used for it.

## Checking by Hand

1. Tab A: select Chat and send "Hello from A".
2. Tab B: opens with no messages; select another app.
3. Tab A still shows Chat with its message; reloading it restores the conversation (Continue Session).
4. Reloading Tab B restores its app with an empty conversation.
5. Closing Tab A does not affect Tab B.
6. In the console, `window.ws.url` includes `?tab_id=` and `sessionStorage.getItem('monadicTabId')` returns the ID.

With `EXTRA_LOGGING=true`, the log shows `[WebSocket] Session initialized: <id> (tab_id: <id>)` and `[WebSocket] Session state: restored|new (<id>)`.

## Tests

`spec/integration/websocket_tab_isolation_spec.rb` tests the store directly: isolation between tab IDs, restoration for the same tab ID, deep copies, concurrent access and app switching.
