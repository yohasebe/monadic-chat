# Ollama Dynamic Capability Detection

## Overview

Ollama models are installed by the user, so the set of models and their capabilities differ per machine. Monadic Chat reads each installed model's capabilities from Ollama's `/api/show` endpoint at runtime instead of listing them in `model_spec.js`.

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
2. **Secondary**: when the fetch fails, name-based rules: `tool_capability: true`, vision when the name contains `-vl`, `:vl`, `vision` or `llava`, thinking when it contains `thinking` or `-r1`; context window 8192
3. **Tertiary**: the one static Ollama entry in `model_spec.js`, used when Ollama cannot be reached at page load

### 2. HTTP layer (`api_routes.rb`)

**`GET /api/ollama/models`** — Returns `{models: {<name>: {<capability flags>}}}` as JSON. Returns empty `{models: {}}` when Ollama is unreachable, so the frontend degrades gracefully instead of erroring.

### 3. Frontend layer (`model_loader.js`)

**`loadOllamaCapabilities()`** — Fetches from `/api/ollama/models`, returns the models hash or `{}` on failure.

During initialization, the result is merged on top of the static `modelSpec` using `Object.assign`. Dynamic entries override static ones so the UI reflects the user's actual installed models.

### 4. UI capability hint (`#model-no-tools`)

When the user selects an Ollama model whose `modelSpec[model].tool_capability` is **explicitly `false`**, the sidebar shows a yellow `No tool calling` indicator next to the model name (HTML element `#model-no-tools` in `views/index.erb`). This communicates that Web Search, file operations, agentic tool dispatch, and other tool-dependent features will not work with the selected model.

Gate logic lives in the `#model` change handler in `public/js/monadic.js`:

- `provider === "ollama"` AND `tool_capability` flag is **present** (own-property) AND value is not `true` → show
- Any other case → hide

The "flag must be present" condition is critical: when `/api/show` is unreachable, the name-based fallback in `list_models_with_capabilities` writes `tool_capability: true` optimistically. The corresponding spec (`ollama_helper_spec.rb`) pins that explicit `tool_capability: false` is set whenever `/api/show` returns a capabilities array that omits `"tools"`, so a missing flag genuinely means "unknown" rather than "no tools".

The hint does **not** disable the model selection — non-tool Ollama models remain perfectly usable for plain chat. The user-facing description is in `docs/advanced-topics/ollama.md` (Models Without Tool Calling).

## Capability Detection

The `/api/show` endpoint returns a `capabilities` array like `["completion", "vision", "tools", "thinking"]`. These map directly to modelSpec flags:

| Ollama capability | modelSpec flag |
|-------------------|----------------|
| `vision` | `vision_capability` |
| `tools` | `tool_capability` |
| `thinking` | `supports_thinking` |
| `completion` | (implicit — all chat models) |

The `context_length` is nested under `model_info.<arch>.context_length`. Because the architecture prefix varies per model, the parser scans for any key ending in `.context_length`. A model without it gets 8192.

## Cache Lifecycle

- **Per-model cache** (`@capabilities_cache`): `CAPABILITIES_CACHE_TTL` (300 s), filled on the first request for each model.
- **Invalidation**: `reset_capabilities_cache` (used by tests); otherwise entries expire with the TTL.

## Tool Definitions Arrive as a JSON String

`obj["tools"]` reaches the vendor helpers as a JSON string: `lib/monadic/utils/websocket/app_data.rb` serializes Array and Hash tool definitions with `to_json` before they are sent to the browser. `format_tools_for_ollama` accepts a String, an Array or a Hash; it parses a string with `JSON.parse` and returns `[]` for an empty or unparsable one. Any helper that reads its tools from `obj["tools"]` must parse a string the same way.

## Related Files

- `docker/services/ruby/lib/monadic/adapters/vendors/ollama_helper.rb` — capability fetching + cache
- `docker/services/ruby/lib/monadic/routes/api_routes.rb` — HTTP endpoint
- `docker/services/ruby/public/js/monadic/model_loader.js` — frontend merge logic
- `docker/services/ruby/public/js/monadic/model_spec.js` — static fallback
- `docker/services/ruby/spec/unit/adapters/vendors/ollama_helper_spec.rb` — unit tests
