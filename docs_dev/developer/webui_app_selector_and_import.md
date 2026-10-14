# Web UI App Selector and Import Notes, SSOT Policy (Developer Reference)

## App Selector (Web UI) Specification

- Custom menu (overlay): A custom dropdown (`#custom-apps-dropdown`) and overlay (`#app-select-overlay`) are displayed on top of the `#apps` select element.
  - The `#apps` value is treated as the source of truth, and the custom menu follows it (highlighting, group expansion, etc.).
  - Icon display is handled by `updateAppSelectIcon(appValue)`. It tries `apps[appValue].icon` → failsafe retrieval from custom menu → fallback to generic icon.
- Initial state: Candidates are built after receiving APPS_LIST via WebSocket.
  - Default auto-selection: (1) `window.lastApp` if it is enabled, (2) `ChatOpenAI`, (3) any enabled `*Chat*` app, (4) the first enabled app. Steps 2-4 are skipped while an import is in progress or when a valid selection exists.

## Import Processing Notes (UI Interaction)

- Import applies app_name → model in sequence to the UI.
  - `updateAppAndModelSelection(parameters)` sets `#apps` and `#model` in order, firing `change` for each.
  - To prevent overwriting when `proceedWithAppChange` runs in parallel, guard flags (`window.isImporting`) and timestamp (`window.lastImportTime`) are used.
  - APPS_LIST's "default app auto-selection" is skipped if `isImporting` is true or if a valid selection value already exists.
- Key points for conflict avoidance:
  - During import, `isImporting = true` is set at the start. The model is set 200 ms after the app, and `isImporting` is reset 500 ms after that.
  - Auto-selection is also suppressed within 1 second of an import (`lastImportTime`). The `isImporting` guard does not apply while a session is being restored (`isRestoringSession`).
- Common pitfalls:
  - If provider/group is carried over in params, incorrect labels/menus may be displayed on next app switch. In normal flow, `apps[appValue].group` is the source of truth and params.group is synced to it; the apps definition itself is never overwritten (only handled limitedly during import if necessary).

## SSOT Policy in Helper Files

- SSOT (model_spec.js) is the primary source of truth. Feature detection should reference the spec whenever possible, falling back to legacy logic only when undefined.
  - Representative examples: `tool_capability`, `supports_streaming`, `vision_capability`, `supports_pdf`, `supports_web_search`, `reasoning_effort`, `supports_thinking`, `beta_flags`, etc.
- Recommended fallback strategy:
  1) If defined in spec, use it
  2) Provider defaults (safe default values)
  3) If still unknown, fail safe (disable)
- Logging: when EXTRA_LOGGING is enabled, log the applied capabilities, disabled parameters, selected endpoint, and source (spec/default/fallback).
