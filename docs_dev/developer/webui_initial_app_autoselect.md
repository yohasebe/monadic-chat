Title: Web UI initial app auto‑select and prompt initialization

Overview
- The Web UI now reliably initializes the first available app on first load and inserts its initial prompt without requiring a manual re‑selection.

What changed
- Cache full apps payload to the global `apps` map as soon as APPS is received, so `proceedWithAppChange(firstValidApp)` can access `system_prompt` immediately.
- On first APPS render, if a valid selection exists but initialization hasn’t run yet, call `proceedWithAppChange` once to ensure params are populated and the initial prompt is injected.
- Added a lightweight timeline logger `window.logTL(event, payload)` to help trace APPS/PARAMETERS/initialization order during debugging.

Where to look
- Initialization: `docker/services/ruby/public/js/monadic/websocket.js`
- App change: `docker/services/ruby/public/js/monadic.js`
- Params loading: `docker/services/ruby/public/js/monadic/utilities.js`

Debugging hints
- Open DevTools console and look for `[TL]` entries:
  - `apps_received`, `proceedWithAppChange_called_from_apps`, `loadParams_called_from_proceed` etc.
  - These events help confirm the order: APPS → proceedWithAppChange → loadParams → prompt insertion.

Notes
- This logic does not alter user selection behavior; it only ensures first‑run initialization is complete without manual input.

