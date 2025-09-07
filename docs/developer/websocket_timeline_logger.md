Title: WebSocket timeline logger for initialization tracing

Overview
- A small timeline logger is available in the browser to trace initialization and message handling order.

Usage
- The logger is exposed as `window.logTL(event, payload)`.
- It writes concise entries to the console as `[TL] <event>`, and also records them in `window._timeline` for later inspection.

Common events
- `apps_received`: APPS message arrived, includes counters and the current selection.
- `parameters_received`: PARAMETERS message arrived, includes `app_name`/`model` flags.
- `proceedWithAppChange_called_from_apps`: Auto‑select path invoked on first load.
- `loadParams_called_from_proceed`: Params load executed after app change.

Where to look
- Defined in `docker/services/ruby/public/js/monadic/websocket.js`.

Notes
- The logger is intentionally lightweight and has no side effects. It should remain safe to keep enabled in debug builds.

