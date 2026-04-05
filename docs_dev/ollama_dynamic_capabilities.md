# Ollama Dynamic Capability Detection

## Overview

Unlike cloud providers (OpenAI, Anthropic, etc.) where model capabilities are well-known at build time, Ollama models are installed locally by users and vary per machine. A user might install `qwen3-vl:8b-thinking` (vision + tools + thinking) or `llama3.2:3b` (text only). To adapt the UI and backend behavior correctly, Monadic Chat queries Ollama's `/api/show` endpoint at runtime to discover each model's actual capabilities.

## Architecture

```
Browser                Ruby Backend              Ollama
───────                ────────────              ──────
model_loader.js  ─GET─▶ /api/ollama/models  ─────▶ /api/show (per model)
                ◀─JSON─┤                   ◀──────┤ capabilities[], context_length
                       │
Object.assign(modelSpec, ollama_models)
```

## Implementation Layers

### 1. Ollama-facing layer (`ollama_helper.rb`)

**`fetch_model_capabilities(model)`** — Module function that calls `POST /api/show` with the model name. Returns a hash `{capabilities: [...], context_length: N, fetched_at: Time}` or `nil` on failure. Results are memoized in `@capabilities_cache` (TTL: 5 minutes) to avoid repeat lookups during tight message loops.

**`list_models_with_capabilities`** — Iterates over `list_models` (bare names) and calls `fetch_model_capabilities` for each, returning a hash keyed by model name, shaped to match frontend `modelSpec` entries.

**Fallback chain**:
1. **Primary**: `/api/show` capability data (accurate, per-model)
2. **Secondary**: Name-based heuristic when fetch fails (e.g. `qwen3-vl:*` → vision=true, `*-thinking`/`-r1` → thinking=true)
3. **Tertiary**: Static fallback entry in `model_spec.js` for the recommended model (`qwen3-vl:8b-thinking`)

### 2. HTTP layer (`api_routes.rb`)

**`GET /api/ollama/models`** — Returns `{models: {<name>: {<capability flags>}}}` as JSON. Returns empty `{models: {}}` when Ollama is unreachable, so the frontend degrades gracefully instead of erroring.

### 3. Frontend layer (`model_loader.js`)

**`loadOllamaCapabilities()`** — Fetches from `/api/ollama/models`, returns the models hash or `{}` on failure.

During initialization, the result is merged on top of the static `modelSpec` using `Object.assign`. Dynamic entries override static ones so the UI reflects the user's actual installed models.

## Capability Detection

The `/api/show` endpoint returns a `capabilities` array like `["completion", "vision", "tools", "thinking"]`. These map directly to modelSpec flags:

| Ollama capability | modelSpec flag |
|-------------------|----------------|
| `vision` | `vision_capability` |
| `tools` | `tool_capability` |
| `thinking` | `supports_thinking` |
| `completion` | (implicit — all chat models) |

The `context_length` is nested under `model_info.<arch>.context_length` (e.g. `model_info.qwen3vl.context_length`). Because the architecture prefix varies per model, the parser scans for any key ending in `.context_length` to remain architecture-agnostic.

## Why Not Static Entries?

The earlier approach (pre-2026-04-05) added individual model entries to `model_spec.js`. This was discarded because:

- **Non-viable for Ollama's scale**: The Ollama library has hundreds of models, each with multiple sizes/quantizations
- **Name-based heuristics are fragile**: `qwen3:4b` turned out to support thinking despite not having `-thinking` in its name
- **User environment varies**: Users install different models; hardcoding can't keep up
- **Ollama provides authoritative data**: `/api/show` is the canonical source — using it eliminates drift

The single remaining static entry (`qwen3-vl:8b-thinking`) exists only as a safety net for when Ollama is temporarily unreachable at page load. See the comment in `model_spec.js` near that entry.

## Cache Lifecycle

- **Per-model cache** (`@capabilities_cache`): 5-minute TTL. Populated lazily on first request per model.
- **Invalidation**: `reset_capabilities_cache` is exposed for tests. In production, TTL expiry handles staleness naturally.
- **Memory cost**: Negligible — a few hundred bytes per installed model.

## Related Files

- `docker/services/ruby/lib/monadic/adapters/vendors/ollama_helper.rb` — capability fetching + cache
- `docker/services/ruby/lib/monadic/routes/api_routes.rb` — HTTP endpoint
- `docker/services/ruby/public/js/monadic/model_loader.js` — frontend merge logic
- `docker/services/ruby/public/js/monadic/model_spec.js` — static fallback
- `docker/services/ruby/spec/unit/adapters/vendors/ollama_helper_spec.rb` — unit tests
