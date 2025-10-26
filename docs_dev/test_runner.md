Title: Unified Test Runner and Reports (Internal)

Scope
- This document is for Monadic Chat maintainers. Public app‑developer docs live under `docs/`; internal implementation details belong to `docs_dev/`.

Overview
- A unified runner orchestrates Ruby (unit/integration/API), JavaScript (Jest), and Python tests.
- Ruby suites save JSON, HTML, and compact text reports by default.

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
All test results are saved to `./tmp/test_results/` for centralized access:

- **Ruby (RSpec)**:
  - `tmp/test_results/<run_id>/` (directory with full results)
  - `tmp/test_results/<run_id>/summary_compact.md` (concise summary)
  - `tmp/test_results/<run_id>/summary_full.md` (detailed results)
  - `tmp/test_results/<run_id>/rspec_report.json` (machine-readable)
  - `tmp/test_results/latest/` (symlink to most recent run)

- **JavaScript (Jest)**:
  - `tmp/test_results/<run_id>_jest.json` (test results in JSON format)

- **Python (pytest)**:
  - `tmp/test_results/<run_id>_pytest.txt` (test output)

- **Unified test suite**:
  - `tmp/test_results/all_<timestamp>.json` (combined summary)
  - `tmp/test_results/index_all_<timestamp>.html` (HTML report index)

API Levels
- `full`: All tests including media generation (image/video/audio)
- `standard`: API tests without media generation (default)
- `none`: Local tests only, no API calls

Rake Tasks
- `rake test` – Run all tests (Ruby + JavaScript + Python, no API)
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
- `rake test:cleanup[keep_count]` – clean up old test results (default: keep latest 3).

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
- Auto-cleanup: Set `TEST_AUTO_CLEANUP=true` to automatically clean up old results after tests.
- Retention policy: Set `TEST_KEEP_COUNT=10` to keep more test results (default: 3).

Cleanup Management
- Manual cleanup: `rake test:cleanup` (keeps latest 3 by default)
- Custom retention: `rake test:cleanup[10]` (keeps latest 10)
- Auto-cleanup: `TEST_AUTO_CLEANUP=true rake test` (cleans up after test run)
- Check disk usage: `du -sh tmp/test_results`
