Title: Unified Test Runner and Reports (Internal)

Scope
- This document is for Monadic Chat maintainers. Public app‑developer docs live under `docs/`; internal implementation details belong to `docs_dev/`.

Overview
- A unified runner orchestrates Ruby (unit/integration/API), JavaScript (Jest), and Python tests.
- Ruby suites save JSON, HTML, and compact text reports by default.

Quick Start
- Run everything (non‑media API) and auto‑open index (macOS):
  - `rake test:all[standard,true]`
- Fast local run without real API calls:
  - `rake test:all[none]`

Artifacts
- Per Ruby suite:
  - `tmp/test_results/<run_id>.json` (RSpec JSON)
  - `tmp/test_results/<run_id>_report.txt` (compact CLI report)
  - `tmp/test_results/<run_id>_{failures|pending}.{txt|json}`
  - `tmp/test_results/report_<run_id>.html` (human‑readable)
- All‑suites index:
  - `tmp/test_results/index_all_<timestamp>.html`

API Levels
- `full`: `RUN_API=true RUN_API_E2E=true RUN_MEDIA=true`
- `standard`: `RUN_API=true RUN_API_E2E=true RUN_MEDIA=false`
- `none`: `RUN_API=false RUN_API_E2E=false RUN_MEDIA=false`

Rake Tasks
- `rake test:help` – list suites and options.
- `rake test:run[suite,opts]` – run a single suite; accepts:
  - `api_level=full|standard|none` (default: `standard`)
  - `format=doc|progress|json`
  - `save=true|false` (default: true), `html=true|false` (default: true), `text=true|false` (default: true)
  - `docker=auto|on|off` (integration/system only)
  - `run_id=...` (override auto id)
- `rake test:all[api_level,open]` – orchestrate all suites; `open=true` opens index on macOS.
- `rake test:report[run_id]` – generate HTML for latest or specific run.
- `rake test:history[count]`, `rake test:compare[run1,run2]` – browse/diff saved runs.

Implementation Notes
- Runner loads env defaults from `~/monadic/config/env` when available.
- JSON analysis extracts failures/pending and writes compact text reports for CLI tools.
- Index HTML aggregates per‑suite reports when available; JS/Python currently show pass/fail only.

Rationale
- Default‑on reporting improves developer feedback loops without requiring CI integration; artifacts are suitable for local review and sharing.

Troubleshooting
- RSpec rake task load error when listing tasks: `cannot load such file -- rspec/core/rake_task`
  - Cause: global `rspec` gem missing. The unified runner does not need it, but `rake -T` may try to load it.
  - Fix: ignore for non‑RSpec tasks, or run `bundle install` in `docker/services/ruby` if you need standalone RSpec tasks.
- Results not saved / directory missing
  - Ensure: `tmp/test_results/` exists; the runner creates it automatically but permissions can block it.
  - Check: `ls -la tmp/ && chmod 755 tmp && mkdir -p tmp/test_results`.
- API keys not configured
  - For offline runs, prefer `api_level=none`.
  - For API runs, set keys in `~/monadic/config/env` (e.g., `OPENAI_API_KEY=...`).
- Docker not running (integration/system)
  - Start Docker Desktop and ensure the `pgvector` container is available.
  - Or bypass with `docker=off` for targeted runs that don't require it.
- Long execution time / timeouts
  - Increase timeout: `rake test:run[integration,"timeout=120"]`.
  - Limit API usage: `api_level=none` for quick turnaround.
- Memory pressure in large suites
  - Run suites separately; avoid concurrent heavy workloads.

Profiles (examples)
- Define reusable profiles in `config/test/test-config.yml` (fallback: `.test-config.yml`) and run with `rake test:profile[ci]`.

Example:
```
profiles:
  quick:
    suites: [unit]
    timeout: 30

  ci:
    suites: [unit, integration]
    format: json
    save: true
    docker: auto

  full:
    suites: [unit, integration, api]
    providers: [openai, anthropic]
    timeout: 120
    save: true
    format: documentation
    docker: auto
```

Sample outputs
- Index HTML: `tmp/test_results/index_all_<timestamp>.html` lists per‑suite cards with status and links to detailed reports.
- Per‑suite HTML: `tmp/test_results/report_<run_id>.html` shows summary counts and enumerates failures/pending with locations.
- Compact text summary: `tmp/test_results/<run_id>_report.txt` includes totals, timings, and a numbered list of failures/pending.

Tips
- macOS auto‑open: `rake test:all[standard,true]` will open the index page when finished.
- Custom run ids: pass `run_id=my_run_001` to group artifacts predictably.
