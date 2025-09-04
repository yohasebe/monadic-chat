# Monadic Chat Implementation Notes (Internal)

This document is for internal development only. Do not commit or publish externally. It summarizes notable implementation details, gotchas, and areas to watch when working on Monadic Chat core.

## System Overview
- Electron app orchestrates Docker services via scripts; supports internal browser (webview) and external browser.
- Core services:
  - Ruby (Sinatra) web server: UI/API, app loading, provider adapters, monadic pipeline
  - Python (Flask) tools: auxiliary operations (e.g., LaTeX rendering, document processing)
  - PostgreSQL/pgvector: PDF RAG storage and search
  - Selenium (Chrome/Chromium): web automation; optional Ollama for local LLMs; optional Jupyter
- Data/paths: `/monadic/data` (in-container) ↔ `~/monadic/data` (host). Use environment helpers for safe path resolution.

## Configuration & Normalization
- Use `ConfigUtils.parse_bool` for all boolean-like values (ENV/config/MDSL). The string "false" is never truthy.
- Use `ConfigUtils.normalize_distributed_mode` for `DISTRIBUTED_MODE` (accepted: `off`/`server`; legacy `true`→`server`, `false`/empty→`off`).
- Feature booleans are normalized at app-init for these keys when present:
  - `monadic`, `toggle`, `file`, `websearch`, `mermaid`, `abc`, `sourcecode`, `mathjax`, `easy_submit`, `auto_speech`, `initiate_from_assistant`, `pdf_vector_storage`, `jupyter`, `jupyter_access`
- Special: `image_generation` may be `true`/`false` or `"upload_only"` (string).
- Key env booleans normalized: `EXTRA_LOGGING`, `MCP_SERVER_ENABLED`, `ALLOW_JUPYTER_IN_SERVER_MODE`, etc.

## Prompt Suffix Composition
- Do not overwrite previously added suffixes. We append provider/app-specific guidance, then append the common language instruction.
- Current order examples:
  - If `mermaid` enabled: add Mermaid syntax note → append language instruction
  - If tools defined: append strict tool-usage instruction
  - If `image_generation` enabled: add click-to-open JS snippet to response suffix

## Server Mode & Jupyter Filter
- `DISTRIBUTED_MODE=server` filters out Jupyter-related apps by default, unless `ALLOW_JUPYTER_IN_SERVER_MODE=true`.
- Filtering checks normalized `jupyter`/`jupyter_access` feature flags and name/display hints.
- Rationale: security and multi-user environment safety.

## MCP Server
- Controlled by `MCP_SERVER_ENABLED` (boolean) and `MCP_SERVER_PORT` (default 3100).
- Enablement/verbosity uses normalized booleans; Thin/EventMachine started on `127.0.0.1`.
- WebSocket broadcast for status; tool list cached with TTL.

## ModelSpec
- Default `modelSpec` comes from a JS file in the web UI; Ruby loads it via brace-matching extraction and JSON parsing.
- User overrides: `~/monadic/config/models.json` (deep-merged; user keys override defaults; invalid JSON falls back to defaults with warning).
- ENV-based provider defaults handled in `SystemDefaults` (e.g., `OPENAI_DEFAULT_MODEL`, `GEMINI_DEFAULT_MODEL`).

## Debug & Logging
- Unified debug: `MONADIC_DEBUG` (categories), `MONADIC_DEBUG_LEVEL` (levels). `EXTRA_LOGGING` remains as a toggle (also affects Electron UI).
- Prefer `DebugHelper.debug` over ad-hoc puts; stack traces gated by debug flags.

## Security & Robustness
- Evaluate only trusted expressions originating from our MDSL compile step; avoid arbitrary eval.
- Use `Environment.safe_data_file_path` for file writes; sanitize basenames.
- Error pattern detection to avoid infinite loops; UTF-8 safety; JSON repair fallback where appropriate.
- Graceful handling of missing API keys and optional services.

## Frontend Notes
- Internal browser (default): permission handler auto-approves media where appropriate; zoom overlay; language cookie set from `UI_LANGUAGE`.
- Settings UI normalizes booleans with a `toBool` helper for safe display (no "false" truthiness).

## Testing Priorities
- Add/maintain tests for: config normalization, MCP enablement/port handling, prompt suffix composition, Jupyter filtering in server mode, ModelSpec user-override loading.
- Follow existing patterns in `docker/services/ruby/spec` and `test/frontend`.

## Common Pitfalls
- Forgetting boolean normalization → "false" string becoming truthy (now mitigated via `parse_bool`).
- Overwriting `prompt_suffix` (fixed to append).
- Relying on provider capabilities without updating ModelSpec defaults/user overrides.

