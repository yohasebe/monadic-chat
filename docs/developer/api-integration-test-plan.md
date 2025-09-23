# API Integration Test Plan

## Goals

- Verify core apps against real provider APIs (no mocks by default).
- Keep media (image/video/audio) tests optional to control cost.
- Minimize duplication via shared helpers, matrices, and fixtures.

## Scope & Matrix

- Providers: OpenAI, Anthropic, Gemini, Mistral, Cohere, Perplexity, DeepSeek, xAI (Grok), Ollama.
- Apps (non‑media): Chat, Second Opinion, Tools (function call), Web Search, Code Interpreter, PDF Navigator, Vector Search.
- Media (optional): Image generate/edit, Video generate/describe, TTS/STT.

## Directory Layout

- `docker/services/ruby/spec/support/provider_matrix_helper.rb` — provider discovery, auth, defaults, wrappers, retry.
- `docker/services/ruby/spec/integration/api_smoke/` — fast, real API smoke per app (non‑media).
- `docker/services/ruby/spec/integration/api_media/` — media tests (tagged `:media`, `:expensive`).
- `docker/services/ruby/spec/integration/provider_matrix/` — table‑driven Provider×App minimal checks.

## Execution Modes (ENV)

- `RUN_API=true` — enable real API tests (default: off).
- `RUN_MEDIA=true` — enable media tests (default: off).
- `PROVIDERS=openai,anthropic,...` — limit target providers.
- `MODELS__OPENAI=gpt-4.1-mini` (per-provider overrides). Otherwise resolve from `system_defaults.json`.
- `API_TIMEOUT=30`, `API_RATE_QPS=1`, `API_MAX_REQUESTS=200`, `FAIL_FAST=false`.
- `INCLUDE_OLLAMA=true` — include local Ollama in default provider set (otherwise excluded by default).

## Rake Tasks

- `rake spec_api:smoke` — non‑media smoke（RUN_API はタスク内で自動有効化）。
- `rake spec_api:media` — media only（RUN_API/RUN_MEDIA はタスク内で自動有効化）。
- `rake spec_api:matrix` — matrix suite（`PROVIDERS=...` で限定可能）。

Example:

```
rake spec_api:smoke PROVIDERS=openai,anthropic
rake spec_api:media API_MAX_REQUESTS=50
```

### Additional Rake Tasks

- `rake spec_api:quick` — CRITICAL apps × 主要プロバイダの最小スモーク（LEVEL_1）。
- `rake spec_api:all` — 全プロバイダ（Ollama除外）× 全アプリ（非メディア）の一括実行。
- `rake spec_api:full` — 全面（LEVEL_1+2+3、メディアも含む）。

ENV hints: `PROVIDERS=openai,anthropic PARALLEL_PROVIDERS=3 API_RATE_QPS=1`

## Coverage & Priorities

- CRITICAL (every run): chat, code_interpreter, jupyter_notebook, web_search
- IMPORTANT (daily): pdf_navigator, voice_chat, voice_interpreter, research_assistant, chat_plus (Monadic Mode)
- STANDARD (weekly): mail_composer, translate, mermaid_grapher, drawio_grapher, wikipedia
- EXPENSIVE (manual/scheduled): image_generator/edit, video_generator/describe, image_mask_editor

Not all 29 apps need equal depth. CRITICAL/IMPORTANT receive LEVEL_2 regularly; EXPENSIVE runs only with `RUN_MEDIA=true`.

## Test Levels

- LEVEL_1 (Smoke): minimal prompt/response, structural checks (<10s per case).
- LEVEL_2 (Functional): key features per app (e.g., web_search results > 0, code_interpreter creates file).
- LEVEL_3 (Edge): rate‑limits/timeouts/large input/cancellation and recovery.

## Cost Tracking

- CostTracker (support): record `{provider, model, kind, tokens_in/out, bytes, duration}` and estimate cost when unit prices are known.
- Emit summary to `tmp/test_costs.json` and RSpec summary; warn on `API_MAX_REQUESTS`/budget exceedance.

## Parallelism & Rate Limits

- Provider‑level parallelism: `PARALLEL_PROVIDERS=N`（プロバイダ間は並列）。
- Per‑provider serialization: `PARALLEL_PER_PROVIDER=1`（同一プロバイダは直列）。
- Implement token‑bucket/backoff in helper; honor 429/`Retry‑After`.

## Failure Diagnostics

- On failure, record: HTTP status/headers (rate limits), request shape (redacted), provider/model, retries, duration.
- Save logs to `tmp/api_failures/{provider}/{example}.log`; redact secrets.

## E2E vs API Responsibilities

- spec_api: real API coverage owner (matrix). No UI/server dependency.
- spec_e2e: wiring/UX/persistence across boundaries. Real API off by default.
- ENV: `RUN_API_E2E=false` (default). Use `RUN_API_E2E=true PROVIDERS=openai` to enable a single representative path.

## Additional Notes

- Monadic Mode (chat_plus): verify context continuity across turns (LEVEL_2 scenario).
- Jupyter Notebook: add‑cell → run → artifact exists (>0 bytes) as minimal assertion.

## Helper Responsibilities (ProviderMatrixHelper)

- Auth discovery: read ENV and `~/monadic/config/env`; skip with clear message if missing.
- Defaults: resolve minimal models from `system_defaults.json`; allow ENV override.
- Thin wrappers:
  - `chat(text, provider:, model:, **opts)`
  - `image_generate(prompt, size: '128x128', ...)`
  - `image_edit(image, mask, prompt, ...)`
  - `speech_to_text(audio, ...)`, `text_to_speech(text, voice: ...)`
  - `web_search(query, ...)`, `code_interpreter(prompt, ...)`
- Cost guards: low temperature, short prompts, smallest assets, no streaming unless required.
- Stability: retry/backoff for 429/5xx, per‑suite rate limiting; normalized response shape (keys: `:text`, `:json`, `:image_url`/`:image_bytes`).

## Test Design Guidelines

- Assertions focus on structure/consistency (HTTP 200, non‑empty, expected keys) over exact text.
- Skip fast if provider/model disabled or key missing (explicit reason).
- Share fixtures (e.g., tiny PNG, short audio) across media cases.
- Keep each test under ~10s in smoke; move heavy flows to `:media, :expensive`.

## Example Skeletons

RSpec (smoke):

```
RSpec.describe 'Chat', :api, provider: :openai do
  include ProviderMatrixHelper
  it 'responds minimally' do
    require_run_api!
    with_provider(:openai) do |p|
      res = p.chat('ping', max_tokens: 16)
      expect(res[:text]).to be_a(String).and not_to be_empty
    end
  end
end
```

RSpec (media, optional):

```
RSpec.describe 'Image generation', :api, :media, provider: :openai do
  include ProviderMatrixHelper
  it 'creates a tiny image (cost-guarded)' do
    require_run_media!
    with_provider(:openai) do |p|
      img = p.image_generate('a yellow square', size: '128x128')
      expect(img[:bytes].length).to be > 0
    end
  end
end
```

## CI & Local Policy

- Default: `RUN_API` off in PR; enable for nightly or labeled workflows; `RUN_MEDIA` only in scheduled runs.
- Secrets: load from CI secret store; never log API keys; redact provider errors.
- Budgets: enforce `API_MAX_REQUESTS` hard cap with early termination and summary.

## Migration Plan

1) Add helper + 2–3 smoke specs (Chat, Tools, Web Search) for 2 providers.
2) Wire Rake tasks; validate on local + nightly.
3) Expand matrix; then add minimal media tests behind `RUN_MEDIA`.
4) Document in README/testing and iterate thresholds/timeouts.
