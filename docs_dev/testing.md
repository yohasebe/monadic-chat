# Testing Guide (Developers)

Test categories, commands and environment variables. Ruby specs live in `docker/services/ruby/spec/`; run `bundle exec rspec` from `docker/services/ruby/`. The unified runner (`rake test:run`, `rake test:profile`) is described in [Test Runner](test_runner.md).

## Categories

| Category | Location | Content |
|---|---|---|
| Unit | `spec/unit` | Components without external services; HTTP and provider calls are stubbed |
| Integration | `spec/integration` | App helpers, containers and provider integrations; API-gated specs skip unless `RUN_API=true` |
| API media | `spec/integration/api_media` | Image, video and voice generation (`RUN_API=true RUN_MEDIA=true`) |
| Provider matrix | `spec/integration/provider_matrix` | Every provider against the apps it has (`:api, :matrix`) |
| System | `spec/system` | Server endpoints and behavior without live provider APIs |
| E2E | `spec/e2e` | UI and server wiring; provider calls need `RUN_API_E2E=true` (examples tagged `:no_api` always run) |
| Frontend | `test/frontend` | Jest with jsdom; see [No-Mock UI Tests](frontend/no_mock/README.md) |
| Python | `docker/services/python/scripts/services/test_*.py` | `rake pytest:all` |

## Commands

| Command | Runs |
|---|---|
| `bundle exec rspec spec/unit` | Ruby unit specs |
| `rake spec` | Ruby unit, integration and system specs; starts Qdrant and Embeddings if they are not running and stops them afterwards (unless `KEEP_VECTOR_SERVICES=true`) |
| `rake test` | Ruby, JavaScript and Python tests, no API |
| `rake test:all[standard]` / `rake test:all[full]` | Unified runner with API tests; `full` adds media |
| `rake matrix[openai,anthropic]` | Provider matrix (`RUN_API=true`; all configured providers without an argument) |
| `rake spec_api:media` | API media specs (sets `RUN_API`, `RUN_MEDIA`) |
| `RUN_API=true bundle exec rspec spec/integration` | API-gated integration specs |
| `rake spec_e2e:jupyter_notebook`, `rake spec_e2e:monadic_context` | E2E specs |
| `npm test` | Jest |

`rake -T | grep -E "test|spec|matrix"` lists the rest.

## Provider Matrix Settings

`spec/support/provider_matrix_helper.rb` paces and retries requests per provider:

| Provider | Timeout (s) | Max retries | Requests per second |
|---|---|---|---|
| openai | 45 | 3 | 0.5 |
| anthropic | 60 | 3 | 0.5 |
| gemini | 60 | 3 | 0.4 |
| mistral | 60 | 3 | 0.4 |
| cohere | 90 | 4 | 0.3 |
| deepseek | 75 | 4 | 0.35 |
| xai | 75 | 3 | 0.35 |
| ollama | 90 | 2 | 1.0 |

Each value is read from `<KEY>_<PROVIDER>` (e.g. `API_TIMEOUT_COHERE`), then the global `<KEY>`, then the table. Keys: `API_TIMEOUT`, `API_MAX_RETRIES`, `API_RATE_QPS`, `API_RETRY_BASE`. `rake matrix` sets `API_TIMEOUT=90` and `API_MAX_RETRIES=0` unless they are set; `rake spec_api:media` sets 120 and 0. Specs skip when a provider's key is missing.

## Writing API-Facing Specs

- Assert presence and shape (non-empty text, valid JSON, a tool was called), not exact wording or order.
- Treat transient provider errors (429, timeouts, 5xx) as non-fatal: retry or skip, do not fail.
- Keep prompts short.

## Result Artifacts

The summary formatter writes each run to `tmp/test_results/<run id>/`:

- `summary_compact.md`, `summary_full.md` (failures and pending with filtered traces)
- `rspec_report.json`
- `env_meta.json` (environment and git metadata)

`tmp/test_results/latest` points to the last run. The latest 20 runs are kept (`TEST_RESULTS_KEEP`; 0 keeps all). `rake test_summary:latest` prints the last summary.

## Environment Variables

| Variable | Effect |
|---|---|
| `RUN_API` | `true` runs API-gated specs |
| `RUN_MEDIA` | `true` (with `RUN_API`) runs media specs |
| `RUN_API_E2E` | `true` lets E2E specs call providers |
| `PROVIDERS` | Comma-separated providers to run |
| `INCLUDE_OLLAMA` | `true` adds Ollama to the default provider list |
| `API_LOG` | `true` prints per-request summaries in matrix specs |
| `API_TIMEOUT`, `API_MAX_RETRIES`, `API_RATE_QPS`, `API_RETRY_BASE` | See above |
| `API_TEMPERATURE` | Temperature for matrix requests (set only when the model accepts it) |
| `GEMINI_REASONING` / `REASONING_EFFORT` | Reasoning level for Gemini matrix requests |
| `GEMINI_MAX_TOKENS` / `API_MAX_TOKENS` | Output token limit |
| `SUMMARY_ONLY` | `1` uses progress output with the summary at the end |
| `SUMMARY_RUN_ID` | Fixed run ID, to collect several runs in one directory |
| `TEST_RESULTS_KEEP` | Number of run directories to keep |
| `EXTRA_LOGGING` | Detailed application logging |

## Related Documentation

- [Test Runner](test_runner.md)
- [Test Quick Reference](test_quickref.md)
- `spec/support/provider_matrix_helper.rb`
