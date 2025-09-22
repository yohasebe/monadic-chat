# Testing Guide (Developers)

This project ships multiple test categories. Goals, locations, and commands:

## Categories

- Unit (`spec/unit`):
  - Scope: small utilities, adapters behavior without external side effects.
  - Command: `rake spec_unit` or `rake spec` (runs all ruby test suites).

- Integration (`spec/integration`):
  - Scope: app helpers, provider integrations, and real API workflows.
  - Real-API subsets live under `spec/integration/api_smoke`, `spec/integration/api_media`, and `spec/integration/provider_matrix`.
  - Commands (Rake):
    - `RUN_API=true rake spec_api:smoke` — non‑media real API smoke across providers.
    - `RUN_API=true RUN_MEDIA=true rake spec_api:media` — media (image/voice) tests.
    - `RUN_API=true rake spec_api:matrix` — minimal matrix across providers.
    - `RUN_API=true rake spec_api:all` — all non‑media API tests (+ optional matrix).

- System (`spec/system`):
  - Scope: server endpoints and high‑level behavior without live external APIs.

- E2E (`spec/e2e`):
  - Scope: UI/server wiring and local workflows only (no real provider API by default).
  - `RUN_API_E2E=true` can enable API calls, but real API coverage is intentionally moved to `spec_api` to reduce flakiness.

## Principles

- Default: skip real APIs unless `RUN_API=true`.
- Provider coverage: Ollama is included by opt‑in when needed; others depend on keys in `~/monadic/config/env`.
- Logging during API tests: set `API_LOG=true` for per‑request logging, or use `EXTRA_LOGGING=true` (see Logging Guide).

## Real API smoke defaults

The `ProviderMatrixHelper` applies conservative heuristics so that a single developer run can exercise every major provider without tripping rate limits:

| Provider      | Timeout (s) | Max retries | Default QPS (≈ requests/second) |
|---------------|-------------|-------------|----------------------------------|
| openai        | 45          | 3           | 0.5                              |
| anthropic     | 60          | 3           | 0.5                              |
| gemini        | 60          | 3           | 0.4                              |
| mistral       | 60          | 3           | 0.4                              |
| cohere        | 90          | 4           | 0.3                              |
| perplexity    | 90          | 4           | 0.3                              |
| deepseek      | 75          | 4           | 0.35                             |
| xai (Grok)    | 75          | 3           | 0.35                             |
| ollama        | 90          | 2           | 1.0                              |

All values can be overridden per provider (for example `API_TIMEOUT_COHERE=120` or `API_RATE_QPS_OPENAI=0.25`). When the provider‑specific variable is absent, the helper falls back to the global knob (`API_TIMEOUT`, `API_MAX_RETRIES`, `API_RATE_QPS`, `API_RETRY_BASE`) and finally to the defaults above.

### Running the smoke suite manually

1. Export the API keys you intend to exercise in `~/monadic/config/env` (missing keys cause the helper to `skip`).
2. Optionally narrow the providers via `PROVIDERS=openai,anthropic` or adjust per‑provider pacing (`API_TIMEOUT_<PROVIDER>`, etc.).
3. Execute the suite:
   ```bash
   RUN_API=true rake spec_api:all
   ```
   For a faster pass, scope to a subset (e.g., `rake spec_api:smoke`).
4. Review `./tmp/test_runs/latest_compact.md` for a concise summary. Re-run failed providers individually if a transient error is suspected.

## Result Summaries

- A custom formatter emits artifacts under `./tmp/test_runs/<timestamp>/`:
  - `summary_compact.md` — short digest (LLM‑friendly)
  - `summary_full.md` — failures/pending details with filtered traces
  - `rspec_report.json` — machine‑readable
  - `env_meta.json` — env + git metadata
- Latest shortcuts:
  - `./tmp/test_runs/latest` (symlink), `./tmp/test_runs/latest_compact.md`
- Print last summary in terminal:
  - `rake test_summary:latest`

## Tips

- Quiet output during iteration: `SUMMARY_ONLY=1 ...`
- Enable per‑provider subsets: `PROVIDERS=openai,anthropic` (see helper).
- Avoid strict string matching for general text apps; rely on presence/non‑error (the tests already lean this way).

## Environment Variables (Quick Reference)

- `RUN_API`: Enable real API tests (`true` to run API-bound specs).
- `RUN_MEDIA`: Enable media tests (image/voice). Use with `RUN_API=true`.
- `PROVIDERS`: Comma‑separated providers to run (e.g., `openai,anthropic,gemini`).
- `API_LOG`: `true` to print per‑test request/response summaries.
- `API_TIMEOUT`: Per‑request timeout in seconds (defaults via Rake: non‑media 90, media 120).
- `API_MAX_RETRIES`: Retries for transient errors (defaults to `0` to avoid extra cost).
- `API_RATE_QPS`: Throttle across tests (e.g., `0.5` for ~2s spacing).
- Provider-specific overrides inherit the same pattern: `API_TIMEOUT_<PROVIDER>`, `API_MAX_RETRIES_<PROVIDER>`, `API_RATE_QPS_<PROVIDER>`, `API_RETRY_BASE_<PROVIDER>` (provider names are uppercased, e.g., `API_TIMEOUT_GEMINI`).
- `SUMMARY_ONLY`: `1` to use progress output + end summary; artifacts still generated.
- `SUMMARY_RUN_ID`: Fixed ID to collate multiple runs in one artifact directory.
- Provider‑specific (optional):
  - `GEMINI_REASONING` / `REASONING_EFFORT`: Reasoning level for Gemini (omit unless required).
  - `GEMINI_MAX_TOKENS` / `API_MAX_TOKENS`: Upper bound for output tokens.
  - `API_TEMPERATURE`: Only set when model_spec allows; otherwise leave unset.
  - `INCLUDE_OLLAMA`: `true` to include Ollama in provider lists by default.
