# Logging (Locations, Types, Extra Logging)

Monadic Chat writes logs on the host at `~/monadic/log`. From the Console Panel (Menu → Open → Open Log Folder), you can jump to this directory.

Common files:
- `server.log` — the Falcon server log for the Ruby web app.
- `docker_build.log`, `docker_startup.log` — docker lifecycle logs.
- `command.log` — shell/code execution traces.
- `jupyter.log` — Jupyter cell additions/run logs.
- `extra.log` — verbose, structured stream used for deep inspection (see below).

Notes:
- At Start, the app probes Ruby control‑plane health. Only when the container is explicitly unhealthy and auto‑refresh is enabled does it rebuild Ruby once and retry. When this happens, `docker_startup.log` includes:
  - `Auto-rebuilt Ruby due to failed health probe`

## Secrets in Logs and Other Outputs

`Monadic::Utils::SecretRedactor` (`lib/monadic/utils/secret_redactor.rb`) replaces secrets, whole, with `[redacted]`, at two levels:

- `redact_values` and `redact_deep` replace the known secret values and 1Password references (`op://...`) only. Known secret values are the values of settings and environment variables whose names match `SecretReferences::CREDENTIAL_NAME` (ending in `_KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `PASSWD` or `CREDENTIAL(S)`, in either case), 8 characters or longer (`CONFIG` holds the values resolved from 1Password references), also in the forms they take inside JSON (as Ruby writes it, and ASCII-only with `\uXXXX` as Python's `json.dumps` does), in Ruby inspect output and percent-encoded (spaces as `+` or `%20`, hex digits in either case). Text that is not valid in its encoding is matched as bytes and kept. `redact_deep` also covers hash keys. An MCP tool result goes through `redact_deep` once, before its JSON text form is made from it, so code, URLs and file contents are otherwise unchanged. What `send_command` returns or yields (stdout) goes through `redact_values`.
- `redact` does the same and also replaces key formats a provider may echo in an error (`sk-`, `sk_`, `xai-`, `AIza`, `gsk_`, `tvly-`, `ya29.`), credential values after `authorization`, `x-api-key` and similar headers (with or without a scheme such as Bearer or Basic) `key=`, `token=`, `password=` and similar values in URLs, and the password in `user:password@` URLs. It runs on every line written by `ExtraLogger` (`extra.log`), on `command.log` and `jupyter.log` entries, on `DebugHelper` output (`mask_secrets`) and on the stderr that `send_command` returns or yields.

`ErrorFormatter.scrub_identifiers` calls `redact` and also replaces account identifiers (organization, project, request ids). It is used for errors sent to the browser, every message built by `ErrorFormatter.format` (including `tool_error` and `api_error`), the error text `send_command` returns to the model, Second Opinion errors, MCP errors, Live Conversation tool errors, Knowledge Base import errors (`ImportTracker.update`), degradation notices (`degradation.log`, stderr and the System card) and failed segments saved in `transcript.json`.

Tests: `spec/unit/utils/secret_redactor_spec.rb`.

## Private Chats

Nothing is logged for the work of a Private chat (`Monadic::History::Policy.current_work_private?`: the chat the work started in, as `EgressGuard.for_chat` keeps it for the threads and fibers it starts, or the tab's session; the ids of Private chats are kept in memory, so work of a Private chat stays Private after the tab moves to a new chat). A line cannot be told to hold none of the chat, so the whole line is left out:

- `ExtraLogger` (`log`, `log_json`, `log_raw`) writes nothing.
- `command.log` gets no entry (`Shell.log_invocation`, `MonadicApp#send_command`).
- HTTP requests that name the tab of a Private chat (`tab_id`) run as that chat's work (`Monadic::History::PrivateRequestGuard`), since the cookie's session is shared by every tab. An imported conversation (`/load`) is parsed in memory (`Monadic::Workspace::UploadInMemory`), so no temporary file is made of it.
- What the process prints (`STDOUT`/`STDERR`, the server log) is dropped: `Monadic::History::PrivateOutput` is prepended to both streams at startup, so `puts`, `print`, loggers made earlier on them and other threads are covered. `$stderr` is set to a guarded copy of `STDERR`: while it is `STDERR` itself, Ruby writes warnings (`warn`) and the report of a thread that died of an exception straight to the file descriptor, past `write`.

Tests: `spec/unit/history/private_work_spec.rb`, and `spec/unit/history/private_chat_files_spec.rb` (a whole chat through the app booted from `config.ru` in a child process with its own home: every file under it is scanned for a marker and every write is recorded, with a normal chat as the positive control, also after the process is killed in an answer).

## Build Logs

- Python build (overwritten each run):
  - `~/monadic/log/docker_build_python.log`: Docker build stdout/stderr, including the output of `~/monadic/config/pysetup.sh` when present
  - `~/monadic/log/python_health.json`: Health check results right after build (LaTeX/convert/Python libraries)
  - `~/monadic/log/python_meta.json`: Execution metadata (Monadic version, host OS, build args, etc.)
- Ruby, user container and full builds (overwritten each run):
  - `~/monadic/log/docker_build.log`

Build progress and logs are shown in the main console. The Install Options window does not auto-trigger rebuilds and does not stream build output.

Renderer message routing:
- Only server-sent messages explicitly tagged as `[HTML]:` (or structured error tags) render into the `#messages` pane.
- Plain command output always remains in the `#output` log area.

## Orchestration Health Probe (Start)

- The Start command verifies that the Ruby control‑plane is ready to coordinate services. You can tune the probe via `~/monadic/config/env`:

```
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

- Auto‑refresh toggle (optional):

```
# If set to false, the app will not rebuild Ruby automatically even on health failure
AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=true
```

- Behavior summary:
  - Healthy: continue.
  - Starting/Unknown: keep waiting up to `START_HEALTH_*` (no rebuild).
  - Unhealthy: rebuild Ruby once if `AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=true`, then retry.

## Build Concurrency Guard

- All build commands are serialized with a lightweight lock at `~/monadic/log/build.lock.d`.
- If a build is already running, the UI shows an informational message and returns immediately.

## Extra Logging

- Toggleable in Settings → System → “Extra Logging”.
- Forced to enabled in `rake server:debug` (`rakelib/server.rake` sets `EXTRA_LOGGING=true`).
- File path is centralized: `MonadicApp::EXTRA_LOG_FILE` (via `Monadic::Utils::Environment.extra_log_file`).
- Many adapters/helpers append structured events here (e.g., provider requests/responses, tool invocations).

### Log Rotation

- To avoid unlimited growth, some logs rotate by size when `LOG_ROTATE_MAX_BYTES` (default 5MB) is exceeded.
- Rotation keeps up to `LOG_ROTATE_MAX_FILES` (default 5) generations: `log`, `log.1`, `log.2`, ...
- Currently applied to:
  - `~/monadic/log/command.log`
  - `~/monadic/log/jupyter.log`
- Configure via `~/monadic/config/env`:

```
LOG_ROTATE_MAX_BYTES=10485760   # 10MB
LOG_ROTATE_MAX_FILES=7          # keep 7 generations
```

## Test Run Artifacts

- Independent of runtime logs, RSpec runs write to `./tmp/test_results/<YYYYMMDD_HHMMSS>/`:
  - `summary_compact.md`, `summary_full.md`, `rspec_report.json`, `env_meta.json`.
- The 20 newest run directories are kept. Set `TEST_RESULTS_KEEP` to another number (0 keeps all).

## Tips

- For API-level diagnosis, combine `EXTRA_LOGGING=true` with `API_LOG=true` in test env.
- When investigating Electron path issues, add temporary `console.log` in `app/main.js` and inspect DevTools.
- If the Python container build fails, check `~/monadic/log/docker_build_python.log` and `python_health.json`.

## Renderer Message Routing Guidelines (Developers)

The Electron renderer has two panes: `#messages` (HTML, user‑facing status) and `#output` (plain console log). To keep UI predictable and noise‑free, follow these rules when emitting messages from the main process or server:

- What goes to `#messages`:
  - Only content explicitly tagged with `[HTML]:` or error markers (e.g., `[ERROR]:`) will render into `#messages`.
  - Use the existing helpers (Electron `formatMessage(type, key, params)` or server‑side HTML snippets) to generate properly structured, localized HTML lines.
  - Allowed semantic types and icon/colors (keep consistent):
    - info: circle‑info, `#61b0ff`
    - success: circle‑check, `#22ad50`
    - warning: circle‑exclamation, `#FF7F07`
    - error: circle‑exclamation, `#DC4C64`

- What goes to `#output`:
  - All plain text logs and command outputs (Docker, build steps, script stdout/stderr) must remain untagged (no `[HTML]:`).
  - Long, streaming output should never be wrapped as HTML.

- Do not rely on fallbacks:
  - The renderer does not elevate plain lines into `#messages`. If you intend a user‑facing status line, you must send `[HTML]:`.
  - Do not emit both HTML and the same text as plain output; prefer a short HTML summary in `#messages` + detailed logs in `#output`.

- Internationalization (i18n):
  - Prefer using `formatMessage()` in the Electron main process for translated messages (includes data attributes for re‑translation on language change).
  - For server‑side HTML snippets, use neutral English if translation isn’t available; keep them short and informational.

- Examples (Electron main):
  - Info: `[HTML]: <p><i class='fa-solid fa-circle-info' style='color:#61b0ff;'></i> Checking orchestration health . . .</p>`
  - Success: use `formatMessage('success', 'messages.buildPythonFinished')`
  - Error: `[ERROR]: Something bad happened` (renderer renders to `#messages` with error styling)

- Anti‑patterns (avoid):
  - Emitting large command output as `[HTML]:` (pollutes `#messages`) — keep it in `#output`.
  - Emitting untagged plain information and expecting it to appear in `#messages` — it will not.
  - Inline styling inconsistent with established icon colors above.

Following these rules ensures users see concise, localized status in `#messages`, while full technical output remains accessible in `#output`.
