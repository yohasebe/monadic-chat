# Monadic Chat Coding Guidelines

This document defines coding conventions and best practices for contributors working on Monadic Chat itself (core app, services, and documentation). These rules complement the existing Developer Guide and aim for clarity, safety, and consistency across Ruby/Electron/Docs/MDSL.

## General Principles
- Clarity first: prioritize readable, maintainable code over cleverness.
- Minimize side effects; prefer pure functions and clear data flow.
- Small PRs with focused scope; write accurate, actionable commit messages.
- Keep changes consistent with existing style and project conventions.

## Configuration & Booleans
- Always normalize boolean-like values; never rely on raw strings such as "false".
- Use `ConfigUtils.parse_bool(value)` in Ruby for all ENV/config/MDSL-sourced booleans.
- Normalize distributed mode with `ConfigUtils.normalize_distributed_mode(value)`; accepted values are `off` or `server` (legacy `true`→`server`, `false`→`off`).
- Do not compare booleans via `== "true"` or `to_s == "true"`.
- Example (Ruby): `if ConfigUtils.parse_bool(CONFIG["EXTRA_LOGGING"])` (Avoid: `CONFIG["EXTRA_LOGGING"] == "true"`).

## Ruby (Backend)
- Ruby version: follow `.ruby-version`/container image baseline.
- File layout follows `docker/services/ruby/lib/monadic/...` for libraries and `apps/**` for built-in apps.
- Prefer early returns; avoid deep nesting.
- Error handling:
  - Catch the narrowest exception you can, and add context.
  - Use clear messages; prefer returning structured hashes from tools (e.g., `{ success: false, error: ... }`).
  - Log stack traces only when `EXTRA_LOGGING` (or debug category) is enabled.
- Logging:
  - Use `DebugHelper.debug(message, category:, level:)` for structured logs.
  - Avoid noisy `puts` unless gated by `EXTRA_LOGGING` or a debug category.
- Performance:
  - Avoid N+1 I/O and redundant parsing; cache when reasonable (e.g., MCP tool cache).
  - Prefer streaming where available; preserve backpressure and limits.

## Electron/JavaScript
- Use preload-exposed APIs; avoid direct `require` in the renderer.
- When reading booleans from env/settings, normalize in JS as well (e.g., a `toBool()` helper: true/1/yes/on/y → true).
- Keep DOM manipulation minimal and scoped; guard permission requests; handle failures.
- Internationalization:
  - Use `i18n.t(...)` for UI strings; ensure English fallback exists.
  - Keep translation keys consistent; avoid inline hard-coded text when possible.

## MDSL & Apps
- Maintain naming conventions:
  - File: `my_app_provider.mdsl`
  - App: `app "MyAppProvider"`
  - Class: `class MyAppProvider < MonadicApp`
- Features block booleans are normalized at load time. Supported keys include: `monadic`, `toggle`, `file`, `websearch`, `mermaid`, `abc`, `sourcecode`, `mathjax`, `easy_submit`, `auto_speech`, `initiate_from_assistant`, `pdf_vector_storage`, `jupyter`, `jupyter_access`.
- Special case: `image_generation` accepts `true`/`false` or `"upload_only"`.
- Prompt suffixes:
  - Avoid overwriting previously built suffixes; append instead (e.g., mermaid guidance + language instruction).
- Tools facade in Ruby should validate inputs and return structured results.

## Server Mode & Jupyter
- `DISTRIBUTED_MODE` uses `off` (default) or `server`.
- In server mode, Jupyter apps are filtered unless `ALLOW_JUPYTER_IN_SERVER_MODE=true`.
- Any server-mode-only constraints must be documented and enforced in code.

## MCP Server
- Enablement via `MCP_SERVER_ENABLED`; port via `MCP_SERVER_PORT` (default 3100).
- Use `ConfigUtils.parse_bool` for enablement; ensure port availability before start.
- Keep traffic limited to `127.0.0.1` unless requirements change and are reviewed for security.

## Error Handling & Resilience
- Detect repeated error patterns and stop infinite loops.
- Ensure UTF-8 safety and robust JSON handling (use `JsonRepair` where applicable).
- Gracefully degrade when API keys or optional services are missing; do not crash.

## Security
- Treat any `eval`-like behavior with caution. Only evaluate trusted expressions originating from our MDSL compilation step.
- Sanitize file paths (use `Environment.safe_data_file_path`).
- Avoid leaking secrets in logs; redact tokens in debug output.

## Tests
- Favor fast unit tests; add integration/E2E only where necessary.
- Use existing patterns under `docker/services/ruby/spec` and `test/frontend`.
- When touching critical paths (config parsing, MCP, app loading), add or update tests.

## Documentation
- Keep English docs under `docs/` and Japanese under `docs/ja/`.
- Update the relevant reference/advanced topic pages when behavior changes (e.g., configuration semantics).
- Write concise, task-focused documentation with examples.

## Git & CI
- Do not commit user-specific setup scripts; keep placeholders intact (`rbsetup.sh`, `pysetup.sh`).
- Keep PRs scoped; prefer feature branches and draft PRs for discussion.
- Ensure lint/tests pass locally before opening PRs.
