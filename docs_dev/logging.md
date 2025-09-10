# Logging (Locations, Types, Extra Logging)

Monadic Chat writes logs on the host at `~/monadic/log`. From the Console Panel (Menu → Open → Open Log Folder), you can jump to this directory.

Common files:
- `server.log` — the Thin server log for the Ruby web app.
- `docker-build.log`, `docker-startup.log` — docker lifecycle logs.
- `command.log` — shell/code execution traces.
- `jupyter.log` — Jupyter cell additions/run logs.
- `extra.log` — verbose, structured stream used for deep inspection (see below).

Notes:
- At Start, if the Ruby control‑plane health probe fails, the app performs a single cache‑friendly rebuild and retries. When this happens, `docker_startup.log` includes:
  - `Auto-rebuilt Ruby due to failed health probe`

## Build Logs (per-run)

- Each Python rebuild writes logs to a dedicated per-run directory:
- Location: `~/monadic/log/build/python/<timestamp>/`
  - `docker_build.log`: Docker build stdout/stderr (includes verified promotion flow)
  - `post_install.log`: Output from running `~/monadic/config/pysetup.sh` if present (optional)
  - `health.json`: Health check results right after build (LaTeX/convert/Python libraries)
  - `meta.json`: Execution metadata (Monadic version, host OS, build args, etc.)

The Install Options window streams build output live and shows a summary (paths/health.json) on completion.

## Orchestration Health Probe (Start)

- The Start command verifies that the Ruby control‑plane is ready to coordinate services. You can tune the probe via `~/monadic/config/env`:

```
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

## Build Concurrency Guard

- All build commands are serialized with a lightweight lock at `~/monadic/log/build.lock.d`.
- If a build is already running, the UI shows an informational message and returns immediately.

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
- If the Python container build fails, check the latest per-run directory for `docker_build.log` and `post_install.log`.
