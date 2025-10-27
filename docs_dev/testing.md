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
    - `rake test` — Run all tests (Ruby + JavaScript + Python, no API)
    - `rake test:all[standard]` — Comprehensive test suite (Ruby + API + JS + Python)
    - `rake test:all[full]` — Full test suite including media tests (image/video/audio)
    - Legacy commands:
      - `RUN_API=true rake spec_api:smoke` — non‑media real API smoke across providers
      - `RUN_API=true RUN_MEDIA=true rake spec_api:media` — media (image/voice) tests
      - `RUN_API=true rake spec_api:matrix` — minimal matrix across providers
      - `RUN_API=true rake spec_api:all` — all non‑media API tests (+ optional matrix)

- System (`spec/system`):
  - Scope: server endpoints and high‑level behavior without live external APIs.

- E2E (`spec/e2e`):
  - Scope: UI/server wiring and local workflows only (no real provider API by default).
  - `RUN_API_E2E=true` can enable API calls, but real API coverage is intentionally moved to `spec_api` to reduce flakiness.

## Principles

- Default: skip real APIs unless `RUN_API=true`.
- Provider coverage: Ollama is included by opt‑in when needed; others depend on keys in `~/monadic/config/env`.
- Logging during API tests: set `API_LOG=true` for per‑request logging, or use `EXTRA_LOGGING=true` (see Logging Guide).

## Testing Strategy: Mock vs Real API

Monadic Chat uses different testing approaches for different test categories. This is intentional and appropriate:

### Unit Tests (spec/unit/)

**Approach**: Mock-based testing

**Rationale**:
- Fast execution (no network calls)
- Isolated testing of individual components
- No external dependencies required
- Predictable, deterministic results

**What We Mock**:
- HTTP client responses
- External API calls
- Database interactions
- File system operations

**Example**:
```ruby
# Unit test with mocked HTTP response
it 'handles API timeout gracefully' do
  stub_request(:post, /api.openai.com/).to_timeout

  expect { helper.chat(messages: [...]) }
    .to raise_error(Faraday::TimeoutError)
end
```

### Integration Tests - API Category (spec/integration/api_*)

**Approach**: Real API calls (when `RUN_API=true`)

**Rationale**:
- Catch provider API changes (parameters, endpoints, formats)
- Test real rate limiting and retry behavior
- Verify actual error messages and handling
- Validate streaming response processing
- Ensure authentication flows work correctly

**What We DON'T Mock**:
- Provider API endpoints
- HTTP responses
- Rate limiting
- Error responses

**Trade-offs**:
- Costs money (real API usage)
- Slower execution (network latency)
- Requires API keys
- **But**: Provides genuine confidence in provider integration

**Example**:
```ruby
# Integration test with real API call
it 'generates text with Claude', run_api: true do
  response = ClaudeHelper.new.chat(
    model: 'claude-sonnet-4.5',
    messages: [{ role: 'user', content: 'Say hello' }]
  )

  # Real provider response
  expect(response[:text]).to match(/hello|hi|greetings/i)
  expect(response[:model]).to eq('claude-sonnet-4.5')
end
```

### Frontend Tests (test/frontend/)

**Approach**: No-mock testing (real DOM, real libraries)

**Rationale**: See [Frontend Testing Documentation](frontend/no_mock/README.md) for detailed philosophy

**Key Points**:
- Uses real DOM via jsdom
- Loads actual JavaScript libraries (jQuery, etc.)
- Tests user workflows, not implementation details
- Verifies actual DOM state changes

### Why This Multi-Strategy Approach Works

| Test Type | Speed | Cost | Confidence | Use Case |
|-----------|-------|------|------------|----------|
| Unit (mocked) | ⚡ Fast | Free | Medium | Component isolation, edge cases |
| Integration (real API) | 🐌 Slow | 💰 Paid | High | Provider compatibility, real behavior |
| Frontend (no-mock) | ⚡ Fast | Free | High | User interactions, DOM behavior |

**The key**: Use the right tool for the right job. Mocks are excellent for unit tests, but real APIs are essential for integration confidence.

## API Integration Testing Philosophy

### Design Principles

Monadic Chat's API integration tests are designed with specific goals and constraints:

#### 1. Real API Calls Over Mocks

**Why**: Mocks cannot catch real-world issues

Mocks can't detect:
- Provider API changes (new parameters, deprecated endpoints)
- Rate limiting behavior and retry logic
- Network timeout handling under real conditions
- Error message format changes
- Authentication flow updates
- Response streaming edge cases

**Trade-off**: Real API calls cost money and time, but provide genuine confidence

#### 2. Cost Tracking and Budget Control

**Infrastructure**: Every test run logs actual API costs

- Costs tracked in `~/monadic/log/test_api_costs.json`
- Per-provider cost breakdown
- Historical cost tracking across test runs
- Enables cost regression detection

**Benefits**:
- Budget-aware test execution
- Identify expensive test scenarios
- Optimize test coverage vs cost tradeoff
- Track provider pricing changes over time

**Example Cost Log**:
```json
{
  "timestamp": "2025-10-26T10:30:00Z",
  "total_cost_usd": 0.47,
  "providers": {
    "openai": {"requests": 12, "cost": 0.23},
    "anthropic": {"requests": 8, "cost": 0.18},
    "gemini": {"requests": 5, "cost": 0.06}
  }
}
```

#### 3. Test Level Strategy (Depth vs Cost)

**ENV-Driven Execution Modes**:

```bash
# LEVEL_1: Smoke tests (fast, cheap)
# - Basic connectivity
# - Simple text generation
# - ~$0.10 per run
TEST_LEVEL=1 RUN_API=true rake spec_api:smoke

# LEVEL_2: Functional tests (moderate)
# - Tool calling
# - Multi-modal inputs
# - Streaming responses
# - ~$1.50 per run
TEST_LEVEL=2 RUN_API=true rake spec_api:all

# LEVEL_3: Edge cases (comprehensive, expensive)
# - Large context windows
# - Complex tool chains
# - Error recovery scenarios
# - ~$5.00 per run
TEST_LEVEL=3 RUN_API=true rake spec_api:all
```

**Use Cases**:
- **CI/CD**: LEVEL_1 on every commit
- **Pre-release**: LEVEL_2 before merging to main
- **Nightly builds**: LEVEL_3 comprehensive validation

#### 4. Parallelism and Rate Limiting

**Strategy**: Provider-level parallelism with per-provider serialization

```ruby
# Providers run in parallel (OpenAI, Claude, Gemini simultaneously)
providers.map do |provider|
  Thread.new do
    # Tests for single provider run serially to respect rate limits
    run_provider_tests(provider)
  end
end.each(&:join)
```

**Benefits**:
- Faster test execution (providers run concurrently)
- Respects each provider's rate limits
- Isolated failures (one provider error doesn't block others)
- Efficient resource utilization

**Rate Limit Configuration**:
```ruby
# Per-provider QPS limits (see table in "Real API smoke defaults" section)
# Example: OpenAI at 0.5 QPS = ~2 second spacing between requests
API_RATE_QPS_OPENAI=0.5
API_RATE_QPS_ANTHROPIC=0.5
API_RATE_QPS_GEMINI=0.4
```

#### 5. Graceful Degradation

**Philosophy**: Transient provider errors should not fail entire test suite

**Implementation**:
- Retry logic with exponential backoff
- Provider-specific timeout configurations
- Skip tests when API keys missing (not error)
- Mark transient failures as pending, not failed
- Detailed failure logs for debugging

**Example**:
```ruby
it 'generates text with Claude' do
  begin
    response = call_claude_api(...)
    expect(response).to have_text_content
  rescue Faraday::TooManyRequestsError => e
    skip "Rate limited (retry after #{e.retry_after}s)"
  rescue Faraday::TimeoutError
    skip "Provider timeout (network issue, not test failure)"
  end
end
```

### Test Matrix Architecture

**Coverage**: 9 providers × 7 app types = 63 test combinations

**Providers**:
1. OpenAI (GPT-4, GPT-5, o1/o3 reasoning)
2. Anthropic (Claude 3.5, Claude 4.5)
3. Gemini (Gemini 1.5, Gemini 2.0)
4. Mistral
5. Cohere (Command R+)
6. DeepSeek
7. Perplexity
8. xAI (Grok)
9. Ollama (local)

**App Types**:
1. Simple chat (text generation)
2. Tool calling (function execution)
3. Vision (image analysis)
4. Streaming responses
5. Multi-modal (text + images)
6. Reasoning (o1/o3, extended thinking)
7. Web search integration

**Selective Execution**:
```bash
# Test specific provider
PROVIDERS=openai RUN_API=true rake spec_api:smoke

# Test specific capability across providers
rspec spec/integration/api_smoke/vision_spec.rb

# Test single app type
rspec spec/integration/api_smoke/tool_calling_spec.rb
```

### Cost Optimization Strategies

#### 1. Smart Test Selection

```bash
# Run cheapest tests first (fail fast)
rake spec_api:smoke  # $0.10

# Only run expensive tests when smoke passes
rake spec_api:all    # $1.50
```

#### 2. Model Selection

```ruby
# Use cheaper models for basic functionality tests
OPENAI_TEST_MODEL=gpt-4.1-mini  # Instead of gpt-5
ANTHROPIC_TEST_MODEL=claude-haiku-4.5  # Instead of claude-sonnet-4.5
```

#### 3. Minimize Context

```ruby
# Keep test prompts short
prompt = "Say hello"  # ✅ Cheap
prompt = system_prompt + long_context + query  # ❌ Expensive
```

#### 4. Reuse Expensive Operations

```ruby
# Cache embeddings, vector stores, file uploads
let(:uploaded_file) { upload_once_per_suite }

# Avoid re-uploading same test data
before(:all) { setup_shared_resources }
after(:all) { cleanup_shared_resources }
```

### Debugging API Test Failures

#### 1. Enable Detailed Logging

```bash
API_LOG=true EXTRA_LOGGING=true RUN_API=true rake spec_api:smoke
```

#### 2. Check Cost Log

```bash
cat ~/monadic/log/test_api_costs.json | jq '.providers'
```

#### 3. Run Single Provider

```bash
PROVIDERS=openai RUN_API=true rspec spec/integration/api_smoke/basic_spec.rb
```

#### 4. Increase Timeout

```bash
API_TIMEOUT=120 RUN_API=true rake spec_api:smoke
```

#### 5. Review Test Artifacts

```bash
cat ./tmp/test_runs/latest_compact.md
cat ./tmp/test_runs/latest/summary_full.md
```

### Best Practices

#### 1. Avoid Strict String Matching

```ruby
# ❌ Bad: Brittle, provider-specific
expect(response).to eq "Hello! How can I help you today?"

# ✅ Good: Flexible, intent-based
expect(response).to match(/hello|hi|greetings/i)
expect(response.length).to be > 0
```

#### 2. Use Presence Checks Over Exact Values

```ruby
# ❌ Bad: Assumes specific tool order
expect(tools).to eq ["search_web", "calculate", "get_weather"]

# ✅ Good: Verifies capability
expect(tools).to include("search_web")
expect(tools.size).to be >= 1
```

#### 3. Handle Provider Differences

```ruby
# Different providers may return different metadata
case provider
when 'openai'
  expect(response).to have_key(:model)
when 'anthropic'
  expect(response).to have_key(:stop_reason)
end

# But core functionality should be consistent
expect(response).to have_text_content
expect(response).not_to have_errors
```

#### 4. Tag Expensive Tests

```ruby
it 'processes large document', :expensive do
  # Only runs at LEVEL_3
end

it 'generates 10K token response', :slow, :expensive do
  # Clearly marked for cost awareness
end
```

### Related Documentation

- **Test Runner**: `docs_dev/test_runner.md` - Unified test orchestration
- **Provider Matrix Helper**: `spec/support/provider_matrix_helper.rb`
- **Cost Tracking**: `~/monadic/log/test_api_costs.json`
- **Frontend Testing**: `docs_dev/frontend/testing.md` - No-mock approach

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

- A custom formatter emits artifacts under `./tmp/test_runs/<timestamp>/` (only the latest directory is kept by default):
  - `summary_compact.md` — short digest (LLM‑friendly)
  - `summary_full.md` — failures/pending details with filtered traces
  - `rspec_report.json` — machine‑readable
  - `env_meta.json` — env + git metadata
- Latest shortcuts:
  - `./tmp/test_runs/latest` (symlink), `./tmp/test_runs/latest_compact.md`
- To keep older runs, set `SUMMARY_PRESERVE_HISTORY=true` (or `SUMMARY_KEEP_HISTORY=true`) before invoking the suite. Without this flag, previous run directories are removed automatically.
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
