# Frontend Documentation

Internal documentation for the browser side of Monadic Chat: plain JavaScript in `docker/services/ruby/public/js/`, talking to the Ruby backend over WebSocket.

## Contents

### Testing
- [No-Mock UI Tests](no_mock/) - Tests with real DOM, fixtures and events

### UI
- [UI State Synchronization](ui_synchronization.md) - Badge updates, `loadParams()` and the reasoning UI
- [Client-Side Rendering Pipeline](client_side_rendering.md) - Markdown, Monadic, ABC, Mermaid and math rendering
- [Safe WebSocket Send](safe_ws_send.md) - `safeWsSend`, its queue and the replayable message types
- [Tab Isolation](tab_isolation.md) - Per-tab sessions
- [Workflow Viewer](workflow_viewer.md) - App workflow graph

## Main Files

All in `docker/services/ruby/public/js/monadic/` unless noted:

- `websocket.js`, `websocket-handlers.js`, `ws-*.js` - WebSocket connection and message handlers
- `monadic-ws.js`, `monadic-fetch.js` - Sending over WebSocket and HTTP
- `utilities.js`, `ui-utilities.js`, `dom-helpers.js` - Parameters, UI helpers, DOM helpers (`$id`, `$show`, …)
- `card-renderer.js`, `markdown-renderer.js` - Message cards and rendering
- `model_spec.js`, `model_utils.js` - Model capabilities (SSOT) and model list logic
- `../monadic.js` - Page setup and event wiring
- `../i18n/translations.js` - UI strings

## Related Documentation

- [JS Console](../js-console.md) - Console logging modes
- [External Libraries](../external-libs.md) - Vendor assets
- [SSOT Normalization](../ssot_normalization_and_accessors.md)
- `docs/advanced-topics/code_structure.md`
