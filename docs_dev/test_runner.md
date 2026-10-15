Title: Unified Test Runner and Reports (Internal)

Scope
- This document is for Monadic Chat maintainers. Public app‑developer docs live under `docs/`; internal implementation details belong to `docs_dev/`.

Overview
- A unified runner orchestrates Ruby (unit/integration/API), JavaScript (Jest), and Python tests.
- `rake test:all` writes per-suite JSON and an `index.html`; `rake test:run` writes reports only with `save=true`.
- Ruby specs run from `docker/services/ruby` (its Gemfile).

Quick Start
- Basic test run (Ruby + JavaScript + Python, no API calls):
  - `rake test`
- Comprehensive test suite with API tests (auto-open index on macOS):
  - `rake test:all[standard,true]`
- Full test suite including media tests (image/video/audio generation):
  - `rake test:all[full]`
- Fast local run without API calls:
  - `rake test:all[none]`

Artifacts
All test results are saved to a unified directory per test run:

- **Unified output structure** (`rake test:all`):
  ```
  tmp/test_results/<timestamp>/
  ├── unit.json           # Ruby unit test results
  ├── integration.json    # Ruby integration test results
  ├── system.json         # Ruby system test results
  ├── api.json            # API test results (if api_level != none)
  ├── media.json          # Media test results (if api_level == full)
  ├── websearch.json      # Websearch API test results (if api_level == full)
  ├── jest.json           # JavaScript test results
  ├── pytest.txt          # Python test output
  ├── summary.json        # Combined summary
  └── index.html          # HTML report with all results
  ```

- **Symlink to latest run**:
  - `tmp/test_results/latest/` → points to most recent test run directory

- **Retention**: every rspec invocation creates one run directory, so
  `spec/support/test_run_dir.rb` prunes on each run and keeps only the newest
  **20**. Override with `TEST_RESULTS_KEEP=<n>`; `TEST_RESULTS_KEEP=0` disables
  pruning entirely. Only entries named exactly `YYYYMMDD_HHMMSS` are ever
  removed — the `latest` symlink and any other file or folder you park in
  `tmp/test_results/` are left alone.

- **Simple test run** (`rake test`):
  ```
  tmp/test_results/test_<timestamp>/
  ├── jest.json           # JavaScript test results
  ├── pytest.txt          # Python test output
  └── summary.json        # Combined summary
  ```

API Levels
- `full`: All tests including media generation (image/video/audio)
- `standard`: API tests without media generation (default)
- `none`: Local tests only, no API calls

Rake Tasks
- `rake test` – Run all tests (Ruby + JavaScript + Python, no API)
- `rake test:help` – list suites and options.
- `rake test:run[suite,opts]` – run a single suite (`unit`, `integration`, `system`, `api`, `e2e`); accepts:
  - `api_level=full|standard|none` (default: `standard`)
  - `format=documentation|progress|json`
  - `save=true|false` (default: false)
  - `run_id=...`, `output_dir=...`, `suite_name=...
- `rake test:all[api_level,open]` – orchestrate all suites; `open=true` opens index on macOS.
- `rake test:js`, `rake test:python` – run Jest or the Python tests alone.
- `rake test:report[run_id]` – generate HTML for latest or specific run.
- `rake test:history[count]`, `rake test:compare[run1,run2]` – browse/diff saved runs.
- `rake test:cleanup[keep_count]` – clean up old test results (default: keep latest 3).

Implementation Notes
- Runner loads env defaults from `~/monadic/config/env` when available.
- JSON analysis extracts failures/pending and writes compact text reports for CLI tools.
- Index HTML aggregates per‑suite reports when available; JS/Python currently show pass/fail only.

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
  - Start Docker Desktop and ensure the `qdrant` and `embeddings` containers are available.
- Long execution time
  - Limit API usage: `api_level=none` for quick turnaround.
- Memory pressure in large suites
  - Run suites separately; avoid concurrent heavy workloads.

Profiles (examples)
- Define reusable profiles in `config/test/test-config.yml` (fallback: `.test-config.yml`) and run with `rake test:profile[ci]`.

A profile lists `suites` and may set `api_level`, `format`, `save`, `timeout` (exported as `API_TIMEOUT`) and `providers` (exported as `PROVIDERS` for the provider-matrix specs). Every suite runs; `rake test:profile` and `rake test:run` exit with status 1 when a suite fails. Results saved without an output directory go to `tmp/test_results/` in the repository.

Example:
```
profiles:
  quick:
    suites: [unit]

  ci:
    suites: [unit, integration]
    format: json
    save: true
```

Sample outputs
- Index HTML (`rake test:all`): `tmp/test_results/<run_id>/index.html` lists per‑suite cards with status and links to detailed reports.
- Per‑suite HTML (`rake test:run … save=true`): `report_<run_id>.html` shows summary counts and enumerates failures/pending with locations.

Tips
- macOS auto‑open: `rake test:all[standard,true]` will open the index page when finished.
- Custom run ids: pass `run_id=my_run_001` to group artifacts predictably.
- Retention: every run prunes to the newest 20 run directories (`TEST_RESULTS_KEEP`, 0 keeps all). `rake test:cleanup` uses `TEST_KEEP_COUNT` (default 3).

Cleanup Management
- Manual cleanup: `rake test:cleanup` (keeps latest 3 by default)
- Custom retention: `rake test:cleanup[10]` (keeps latest 10)
- Check disk usage: `du -sh tmp/test_results`
