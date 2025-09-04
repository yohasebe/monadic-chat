## Session Import and Startup Stabilization Guide

This document captures the practical lessons learned while stabilizing the web UI during normal startup and session import flows. It describes how to avoid UI flicker, ensure consistent initial state, and prevent transient, incorrect UI updates (e.g., the "math" badge flashing briefly).

### Message Order and Import Detection

- Initial messages can arrive in this order: `apps → parameters(empty) → parameters(with app_name)`.
- If `parameters.app_name` is present, treat it as a session import (restoring a saved session).

### First App Application (pendingFirstApp + Grace Period)

- On `apps`, compute the best initial app (prefer a Chat app; otherwise the first non-disabled app) and store it in `pendingFirstApp`. Do not apply it immediately.
- For normal startup (i.e., not an import), start a short grace period (e.g., ~800ms). If no `parameters.app_name` arrives during this window, apply `pendingFirstApp` exactly once and complete init.
- If an import is detected (i.e., a `parameters` with `app_name` arrives), cancel the grace timer and avoid any interim UI updates.

### Handling parameters(empty)

- `parameters(empty)` may denote either normal startup (no persisted session) or “import about to arrive".
- While the grace timer is active, do not perform UI updates based on `parameters(empty)`. This prevents intermediate, incorrect UI states.

### Guarding resetParams (common flicker source)

- Even if `resetParams` is queued (e.g., via a delayed call in the `apps` handler), avoid running it when:
  - Import is underway (`isImportedSession && isLoadingParams`), or
  - Initialization is not yet confirmed (`!paramsInitialized`), or
  - The grace timer (post-`apps`) is still active.
- This prevents a temporary blank/partial UI from rendering between `apps` and final `parameters`.

### UI Updates During Import

- During import, do not update visual elements that would visibly change (title/icon/description/badges).
- In `handleImportedParameters`, update internal controls (e.g., checkboxes like `#mathjax`) as needed, but do not call `show()/hide()` on badges. Apply all final visual updates once the import has fully completed.

### Core Flags (semantics and usage)

- `isImportedSession`: Import is in progress or confirmed. Default: defer UI rebuilds.
- `isLoadingParams`: Parameters are being loaded/applied. Used to block `resetParams`.
- `paramsInitialized`: Startup parameters are finalized. Normal startup sets this to `true` after the grace period.
- `pendingParameters`: Temporary store for early/delayed `parameters`; if it contains `app_name`, import is confirmed.
- `pendingFirstApp`: Candidate app captured on `apps`; applied only once according to the rules above.
- `possibleImportSession`: Heuristic that an import may be happening (evaluated in the `apps` handler).

### shouldDeferUIUpdates()

Return `true` and skip UI rebuilds if any of the following holds:

```
isImportedSession || isLoadingParams || (!paramsInitialized && (possibleImportSession || (pendingParameters && pendingParameters.app_name)))
```

### Do / Don’t

- Do: Store `pendingFirstApp` on `apps`, then update UI exactly once after deciding between normal startup vs. import.
- Do: Guard `resetParams` during grace/import windows.
- Do: Avoid badge/title/icon/description changes during import; apply once at the final stage.
- Don’t: Perform stepwise visual updates during import. That causes “one-frame” flickers and transient wrong UI.

### Quick Regression Checklist

- Normal startup: After the grace period, the initial app is applied exactly once; icon and initial prompt are present.
- Import: Only the final app name/icon/description/badges are shown; there is no intermediate “Chat” or “math” flash.
- `parameters(empty)` received during grace: No UI changes occur until import is confirmed or grace expires.

### Implementation Pointers (current codebase)

- `websocket.js`
  - `apps` handler: compute and store `pendingFirstApp`, start grace timer for normal startup, cancel on import.
  - `parameters` handler: skip UI work while grace is active; only apply once.
  - Avoid running `resetParams` while grace/import conditions hold.
- `websocket.js: handleImportedParameters`
  - Update controls/checkboxes only (e.g., set `#mathjax` state) but defer badge `show()/hide()` until the final import-complete phase.
- `utilities.js`
  - Keep badge toggles tied to the final, stable state; avoid calling these during import.

### Spinner Text (optional)

Changing spinner text during import can be overwritten by other flows. If you need an import-specific label, set it in a single place that is not invoked by other startup paths, or keep the default text to reduce complexity.
