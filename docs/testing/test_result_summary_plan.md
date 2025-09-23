# Test Result Summarization & Visibility – Plan

## Objectives
- Reduce terminal noise and make pass/fail status obvious at-a-glance.
- Generate concise, LLM-friendly digests (Codex/Claude) containing only essentials.
- Persist full details for failures and pendings under `./tmp` with timestamped folders.

## Scope (Phase 1)
- Ruby RSpec suites only: `spec/unit`, `spec/integration` (incl. `spec_api`), `spec/system`, and minimal `spec/e2e`.
- Non-goals for Phase 1: Jest/Pytest integration (planned in Phase 2).

## Outputs (per run)
- Root: `./tmp/test_runs/<YYYYmmdd_HHMMSSZ>/` (older run directories are removed automatically unless `SUMMARY_PRESERVE_HISTORY` is set).
  - `summary_compact.md`: Short, scan-friendly digest for humans/LLMs.
  - `summary_full.md`: Detailed summary (full failure + pending details).
  - `rspec_report.json`: Machine-readable result summary (examples, status, timings, metadata).
  - `rspec_output.log`: Concatenated RSpec console output (for deep dive).
  - `env_meta.json`: Key environment metadata (provider list, RUN_API/RUN_MEDIA, commit SHA, branch, Ruby version).
- Convenience links:
  - `./tmp/test_runs/latest` → symlink to last run.
  - `./tmp/test_runs/latest_compact.md` → copies/links to most recent compact summary.

## Terminal UX Improvements
- Add a custom RSpec formatter that:
  - Prints an end-of-run, colorized one-page summary (totals, duration, seed).
  - Lists only failed and pending/flaky examples with `file:line`, example description, and 1–2 line reason.
  - Shows the artifact directory path and how to open the compact summary.
- Optional noise controls via env:
  - `SUMMARY_ONLY=1`: Use `--format progress` during run, suppress documentation output, and rely on end summary.
  - `SUMMARY_MAX_FAILS=<N>`: Limit number of failures shown inline; full remains in `summary_full.md`.

## Implementation Plan
1) Summary Directory Helper
- Add `Monadic::TestRunDir` helper to:
  - Create timestamped run dir under `./tmp/test_runs`.
  - Expose paths for `summary_compact.md`, `summary_full.md`, `rspec_report.json`, `rspec_output.log`, `env_meta.json`.
  - Maintain/update the `latest` symlink and `latest_compact.md` copy.

2) Custom RSpec Formatter
- File: `docker/services/ruby/spec/support/summary_formatter.rb` (autoloaded by spec_helper).
- Responsibilities:
  - Collect example results (passed/failed/pending), durations, seed, and grouping by spec path prefix (unit/integration/system/e2e).
  - Emit:
    - Console summary (colorized, concise; respects `SUMMARY_MAX_FAILS`).
    - `rspec_report.json` with all examples (id, file, line, status, description, exception summary, pending_reason, run_time).
    - `summary_compact.md` (see Template below).
    - `summary_full.md` (complete failures/pending with filtered backtraces).

3) Rake Task Wiring
- Wrap existing tasks to include the formatter and ensure artifacts are written:
  - For `:spec`, `spec_api:*`, and `spec_e2e` tasks:
    - If `SUMMARY_ONLY=1`, run with `--format progress` + `--require spec/support/summary_formatter.rb` + `--format Monadic::SummaryFormatter`.
    - Else, keep existing human format (`documentation`) and add the summary formatter as an additional formatter.
  - Pipe stdout/stderr to `rspec_output.log` via RSpec IO capture (the formatter writes logs and summaries to files; no shell redirection needed).

4) Content Templates
- Compact (LLM-friendly) `summary_compact.md`:
  - Header with totals and timings.
  - Environment meta (PROVIDERS, RUN_API, RUN_MEDIA, BRANCH, SHA).
  - “Failed” list: `n.` `description` — `file:line` — `short reason`.
  - “Pending/Skipped” list with reasons (max 25 items, truncate beyond with note).
- Full `summary_full.md`:
  - Same header.
  - Full sections for Failures and Pending including filtered backtraces (project files first, gem noise collapsed).

5) Metadata Capture
- Generate and write `env_meta.json` with selected keys:
  - `PROVIDERS`, `INCLUDE_OLLAMA`, `RUN_API`, `RUN_MEDIA`, `GEMINI_REASONING`, `API_MAX_TOKENS`, `GEMINI_MAX_TOKENS`.
  - Git info if available: `git rev-parse --abbrev-ref HEAD`, `git rev-parse --short HEAD`.
  - Ruby, OS, container flags (best-effort).

6) Defaults & Env Controls
- `SUMMARY_DIR_ROOT=./tmp/test_runs` (overrideable). Older runs are pruned unless `SUMMARY_PRESERVE_HISTORY=true` (or `SUMMARY_KEEP_HISTORY=true`).
- `SUMMARY_ONLY=0` by default.
- `SUMMARY_MAX_FAILS=50` (inline console cap).
- `SUMMARY_MAX_PENDINGS=50` (compact cap).

## Phase 2 (Optional)
- Jest integration:
  - Run with `--json --outputFile` and post-process to the same `summary_compact.md` format (append section “JavaScript”).
- Pytest integration:
  - Prefer `pytest-json-report` plugin; fallback to parsing `-r a` summary lines.
- CI Integration:
  - Upload `./tmp/test_runs/<ts>` as artifact.
  - Post compact summary as a PR comment.

## Risks & Mitigations
- Formatter incompatibilities: Implement as an additional formatter to avoid breaking current output.
- Overhead: JSON writing and summaries are O(examples); acceptable for current suite size. Use caps for inline lists.
- Path portability: Keep all paths relative and avoid shell-only redirection; formatter writes files directly.

## Acceptance Criteria
- After any `rake spec` or `rake spec_api:*` run:
  - A new `./tmp/test_runs/<ts>/` is created with all artifacts.
  - Terminal shows a concise colorized summary with counts and pointers to artifacts.
  - `latest` symlink and `latest_compact.md` are updated.
- Failures/Pendings listed clearly in both console and compact summary with `file:line` and short reason.

## Compact Summary – Example (Template)
```md
# Test Summary – 2025-01-12T08:42:11Z

- Total: 812 • Passed: 789 • Failed: 3 • Pending: 20 • Duration: 6m42s
- Suite: unit(540) integration(240) system(30) e2e(2)
- Env: PROVIDERS=openai,anthropic • RUN_API=true • RUN_MEDIA=false
- Git: main @ a1b2c3d

## Failed (3)
1. Research Assistant – returns sources for query — spec/integration/api_smoke/research_assistant_smoke_spec.rb:27 — expected to include "Source"
2. Gemini Mermaid – structured output format — spec/integration/provider_matrix/extended_matrix_spec.rb:58 — invalid JSON
3. Claude code interpreter – runs Python snippet — spec/integration/code_interpreter_integration_spec.rb:102 — timeout (60s)

## Pending/Skipped (top 20)
- Visual Web Explorer – live capture disabled in CI — spec/integration/api_smoke/visual_web_explorer_smoke_spec.rb:14
- Ollama provider – disabled by default — spec/integration/provider_matrix/all_apps_matrix_spec.rb:9
...

Artifacts: ./tmp/test_runs/2025-01-12_084211Z/
```

---

## Implementation Checklist
- [ ] Add `Monadic::TestRunDir` helper.
- [ ] Add `Monadic::SummaryFormatter` and wire into spec_helper load path.
- [ ] Update Rake tasks to include the formatter and env toggles.
- [ ] Verify artifacts on `rake spec_unit`, `rake spec_api:smoke`.
- [ ] Add CI step to upload `./tmp/test_runs/<ts>`.
