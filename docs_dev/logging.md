# Logging (Locations, Types, Extra Logging)

Monadic Chat writes logs on the host at `~/monadic/log`. From the Console Panel (Menu → Open → Open Log Folder), you can jump to this directory.

Common files:
- `server.log` — the Thin server log for the Ruby web app.
- `docker-build.log`, `docker-startup.log` — docker lifecycle logs.
- `command.log` — shell/code execution traces.
- `jupyter.log` — Jupyter cell additions/run logs.
- `extra.log` — verbose, structured stream used for deep inspection (see below).

## Extra Logging

- Toggleable in Settings → System → “Extra Logging”.
- Forced to enabled in `rake server:debug` (Rakefile sets `EXTRA_LOGGING=true`).
- File path is centralized: `MonadicApp::EXTRA_LOG_FILE` (via `Monadic::Utils::Environment.extra_log_file`).
- Many adapters/helpers append structured events here (e.g., provider requests/responses, tool invocations).

## Test Run Artifacts

- Independent of runtime logs, RSpec runs write to `./tmp/test_runs/<timestamp>/`:
  - `summary_compact.md`, `summary_full.md`, `rspec_report.json`, `env_meta.json`.
  - Latest symlink: `./tmp/test_runs/latest`.

## Tips

- For API-level diagnosis, combine `EXTRA_LOGGING=true` with `API_LOG=true` in test env.
- When investigating Electron path issues, add temporary `console.log` in `app/main.js` and inspect DevTools.

