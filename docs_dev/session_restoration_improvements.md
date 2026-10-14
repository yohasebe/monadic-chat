# Session Restoration on Page Load

How a tab shows its conversation after a reload, and how it follows the server when the server's session is empty (for example after `rake server:debug` was restarted).

## Steps

1. **From sessionStorage** (`monadic.js`, page load): `SessionState.restore()` reads the tab's state from sessionStorage (one state per tab). Unless a reset was requested (`SessionState.shouldForceNewSession()`), the stored messages are rendered as cards right away, and the Start button reads **Continue Session**. `window.isRestoringSession` is true during this step and is cleared after 3 seconds.
2. **From the server** (`push_apps_data` in `lib/monadic/utils/websocket/app_data.rb`): after the `apps` and `parameters` messages, the server sends `past_messages` with the session's messages for the current app.
3. **Replace** (`handlePastMessages` in `ws-message-renderer.js`): the browser clears `SessionState` messages and `#discourse`, then renders and stores the server's messages. It updates the stats and sets the Start button to **Continue Session** when there is a non-system message, otherwise **Start Session**.

The server's messages always win. When the server's session is empty, step 3 removes the messages shown in step 1; they are visible for a moment before that.

`window.messages` is a proxy to `SessionState.conversation.messages` (`session_state.js`), so `SessionState.clearMessages()` also clears the global `messages`.

## Imports

An import sends `past_messages` with `from_import: true` (`misc_handlers.rb`). The handler suppresses Auto Speech, sets `isProcessingImport` and `skipAssistantInitiation`, and clears `isProcessingImport` after rendering.

## Cases to Check After Changes

| Case | Expected |
|---|---|
| Reload during a conversation | Messages come back |
| Restart the server, then reload | Messages are cleared; Start Session |
| Reset | New session without the old messages |
| Switch app | Only the new app's messages |
| Import a `.json` file | The imported messages appear; no Auto Speech |

## Related Files

- `docker/services/ruby/public/js/monadic.js` (restore on load)
- `docker/services/ruby/public/js/monadic/ws-message-renderer.js` (`handlePastMessages`)
- `docker/services/ruby/public/js/monadic/session_state.js`
- `docker/services/ruby/lib/monadic/utils/websocket/app_data.rb` (`push_apps_data`)
- [Tab Isolation](frontend/tab_isolation.md)
