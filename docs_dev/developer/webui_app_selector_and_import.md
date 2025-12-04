# Web UI App Selector and Import Notes, SSOT Policy (Developer Reference)

Last updated: 2025-09-05

## App Selector (Web UI) Specification

- Custom menu (overlay): A custom dropdown (`#custom-apps-dropdown`) and overlay (`#app-select-overlay`) are displayed on top of the `#apps` select element.
  - The `#apps` value is treated as the source of truth, and the custom menu follows it (highlighting, group expansion, etc.).
  - Icon display is handled by `updateAppSelectIcon(appValue)`. It tries `apps[appValue].icon` → failsafe retrieval from custom menu → fallback to generic icon.
- Initial state: Candidates are built after receiving APPS_LIST via WebSocket.
  - Default auto-selection logic (OpenAI/Chat priority) exists, but is guarded to skip if "importing" or if a valid selection already exists.

## Import Processing Notes (UI Interaction)

- Import applies app_name → model in sequence to the UI.
  - `updateAppAndModelSelection(parameters)` sets `#apps` and `#model` in order, firing `change` for each.
  - To prevent overwriting when `proceedWithAppChange` runs in parallel, guard flags (`window.isImporting`) and timestamp (`window.lastImportTime`) are used.
  - APPS_LIST's "default app auto-selection" is skipped if `isImporting` is true or if a valid selection value already exists.
- Key points for conflict avoidance:
  - During import, set `isImporting = true` at the start, and reset to false after app/model application completes with sufficient delay (~500ms).
  - Recent imports within 1 second (`lastImportTime`) also suppress auto-selection (delayed race condition countermeasure).
- Common pitfalls:
  - If provider/group is carried over in params, incorrect labels/menus may be displayed on next app switch. In normal flow, `apps[appValue].group` is the source of truth and params.group is synced to it; the apps definition itself is never overwritten (only handled limitedly during import if necessary).

## SSOT Policy in Helper Files

- SSOT (model_spec.js) is the primary source of truth. Feature detection should reference the spec whenever possible, falling back to legacy logic only when undefined.
  - Representative examples: `tool_capability`, `supports_streaming`, `vision_capability`, `supports_pdf`, `supports_web_search`, `reasoning_effort`, `supports_thinking`, `supports_verbosity`, `latency_tier`, `beta_flags`, etc.
- Recommended fallback strategy:
  1) If defined in spec, use it
  2) Provider defaults (safe default values)
  3) If still unknown, fail safe (disable)
- Introduction order (small and safe):
  - Phase 0: Observation/inventory (vocabulary of branches)
  - Phase 1: Spec-first (e.g., tool_capability / supports_streaming) + undefined fallback
  - Phase 2: Introduce normalization layer (message shape/parameter commonization)
  - Phase 3: Remove legacy hardcoding (once spec coverage is complete)
  - Phase 4: Spec-driven contract tests
- Logging/monitoring:
  - When EXTRA_LOGGING is enabled, it's helpful to briefly record "applied capabilities", "disabled parameters", "selected endpoint", and "source (spec/default/fallback)" to make migration safe.

---
This document briefly summarizes the interaction between UI and import, and the SSOT policy for helpers in a practical manner. If conflicts or reversions are needed during implementation flow, use this as a starting point to identify causes and countermeasures.
