# Developer Updates (2025-09)

This note summarizes several behavior clarifications and small infrastructure changes made while fixing tests and polishing the Web UI. These are intended to guide future changes and reduce regressions.

## Web UI: App Switching vs. Import Flows

- Function: `window.proceedWithAppChange(appValue)` in `public/js/monadic.js`.
- Behavior rules:
  - On user‑driven app selection (normal UI change), merge the selected app’s defaults into `params` and do NOT preserve the previous app’s `model`/`group`/`app_name`.
  - When importing or programmatic parameter loading is in progress (`window.isImportedSession` or `window.isLoadingParams`), preserve `model`/`group`/`app_name` that came with the imported session.
  - `initiate_from_assistant`:
    - On user‑driven app changes, set to the app’s explicit value; default to `false` if not defined by the app.
    - During imports/param loading, preserve the imported value as is.
- Rationale: prevents stale parameters from a previous app from “sticking” when the user explicitly picks a new app (e.g., OpenAI › Chat), while still honoring imported sessions.

## MDSL Validation: Verbosity and Testability

- New flags: set `MDSL_VALIDATION_VERBOSE=true` (or `EXTRA_LOGGING=true`) to emit MDSL warnings; otherwise remain silent by default.
- Loader changes:
  - Only validates MDSL when `app_state.respond_to?(:llm_settings)`; `AppState#llm_settings` now returns symbolized keys from `settings` for compatibility.
  - Emitted via `Kernel.warn` (not bare `warn`) to make RSpec spies reliable.
- Test note: When testing for warnings, spy on `Kernel.warn` and flip `MDSL_VALIDATION_VERBOSE` to `true`.

## MCP Server: Test‑safe EventMachine Notifications

- `lib/monadic/mcp/server.rb` uses `EM.next_tick` to broadcast status.
- In test/mocked environments where `EventMachine` may be doubled without `next_tick`, we guard calls:
  - If `EM.next_tick` is unavailable, broadcast immediately; swallow `NoMethodError` safely.
- “Server started” logs are now gated behind `EXTRA_LOGGING` to keep test output quiet.

## Python Jupyter Controller: Quiet Mode

- Default quiet by environment variable `MONADIC_PY_QUIET=1`.
- All routine prints routed through `_echo()`; CLI outputs (user‑facing) are preserved.
- To debug interactively: `MONADIC_PY_QUIET=0 python3 test_jupyter_controller.py -v`.

## RSpec Example Persistence in Read‑only Environments

- `spec_helper.rb` only enables `config.example_status_persistence_file_path` if the directory is writable, removing noisy warnings in read‑only sandboxes.

## Ruby Constants: Safer Re‑init in Tests

- Avoid redefinition warnings:
  - `IN_CONTAINER` defined unless already present.
  - `CONFIG` seeded once; merge defaults instead of reassigning.
  - `APPS` is reinitialized via `remove_const` during reload.
- In MDSL class generation, remove existing constant for the same app name before `eval` to avoid `superclass mismatch` during repeated DSL evaluations in tests.

## xAI (Grok) Live Search: Parameters

- `search_parameters.mode` default is now `"auto"` with optional override via `parameters["websearch_mode"]`.
- This is more robust with date ranges while still allowing callers to force `"on"`.

## Cohere Model Spec: Deprecations Removed

- Removed `c4ai-aya-expanse-8b`, `c4ai-aya-expanse-32b` from `model_spec.js` to match current provider reality.

## Misc Fixes and Guards

- `init_apps` safely handles subclasses without `@settings` to prevent `NoMethodError` while debugging or partial loads.
- Logs across Ruby/JS tightened behind `EXTRA_LOGGING` to reduce default noise while keeping a convenient verbose knob for debugging.

## Takeaways for Future Changes

- Treat user‑initiated app changes differently from imported/session‑driven changes. Preserve imported parameters only during import/param loading gates.
- Keep warning/logging behind explicit flags. Prefer `Kernel.warn` for messages that unit tests need to spy on.
- When integrating event loops (EventMachine), guard optional APIs in tests and provide a synchronous fallback.
- Prefer quiet defaults with explicit verbose/debug flags in both Ruby and Python components.
