**SSOT Normalization and Accessors (Internal)**

This document describes the server-side normalization layer and canonical accessors for model capabilities. It keeps a single vocabulary across providers.

**Goals**
- Centralize capability semantics in `model_spec.js` (SSOT).
- Avoid hardcoded model lists/regex in helpers; prefer spec flags.
- Provide a normalization pass to map provider-specific aliases to canonical names.
- Offer stable accessors with conservative defaults.

**Normalization (ModelSpec.normalize_spec)**
- Runs after base spec load and user overrides merge.
- Converts aliases into canonical properties without removing originals:
  - `reasoning_model` → `is_reasoning_model`
  - `websearch_capability` / `websearch` → `supports_web_search`
  - `is_slow_model` → `latency_tier: "slow"`
  - `responses_api: true` → `api_type: "responses"`
  - `supports_structured_output` → `structured_output`
- Does NOT auto-populate `supports_pdf_upload` (set explicitly per model).

**Canonical Accessors**
- Prefer these over raw `get_model_property` calls:
  - `tool_capability?(model)`: Non‑false → true
  - `supports_streaming?(model)`: nil→true, else boolean
  - `vision_capability?(model)`: nil→true, else boolean
  - `supports_pdf?(model)`: boolean
  - `supports_pdf_upload?(model)`: boolean
  - `supports_web_search?(model)`: boolean
  - `supports_verbosity?(model)`: boolean (supports both `supports_verbosity: true` and `verbosity: [[options], default]` formats)
  - `get_verbosity_options(model)`: returns `{ options: [...], default: "..." }` or nil
  - `responses_api?(model)`: boolean
  - Others in `lib/monadic/utils/model_spec.rb`: `supports_thinking?`, `supports_adaptive_thinking?`, `supports_temperature?`, `supports_file_inputs?`, `is_reasoning_model?`, `ui_hidden?`, `deprecated?`, `rejects_sampling_params?`, `supports_thinking_level?`; see `docs_dev/developer/model_spec_vocabulary.md`

**Helper Guidelines**
- Streaming: Gate by `supports_streaming?`; default to true for undefined.
- Tools: Gate by `tool_capability?`; drop `tools/tool_choice` for false.
  - **Tool calling is a baseline requirement.** An absent `tool_capability`
    flag means *capable* (`!= false`), not incapable. The chat entries in
    `model_spec.js` declare `tool_capability: true`; only runtime-discovered
    Ollama models can lack it, and those are supported only when tool-capable.
    Features like dynamic skill loading degrade gracefully (tools are simply
    skipped) on a non-tool model.
  - Every provider helper must derive the default from the canonical accessor
    (`ModelSpec.tool_capability?`) or the equivalent `spec.nil? ? true : !!spec`
    — never `== true`, which would flip an unknown model to non-tool and
    diverge from the rest of the stack. Preserve each provider's legacy-mode
    ENV override on top of that default.
- Vision/PDF: Validate before assembling content parts. For URL‑only PDFs, return a clear error (or instruct the user) instead of attaching base64.
- Reasoning: Use `is_reasoning_model`/`reasoning_effort` where applicable; avoid string matching on model names.
- Web search: Use `supports_web_search?` (and provider’s native config) instead of hardcoded lists.
- Audit: When `EXTRA_LOGGING` is enabled, log a single‑line capability summary including the source (spec/fallback/legacy).

**UI Guidance (Cross‑team)**
- The file–attach button is controlled by app features + `vision_capability`.
- Show “Image/PDF” only if `supports_pdf_upload: true`; otherwise show “Image”.
- Keep URL‑only PDF models (`supports_pdf: true`, `supports_pdf_upload: false`) consistent: do not allow `.pdf` in the file input.

**Testing**
- Add unit tests for:
  - Normalization mapping (aliases → canonical)
  - Accessor defaults (nil → expected default)
  - URL‑only PDFs (`supports_pdf_upload: false`) vs file uploads (Claude/Gemini/OpenAI) behaviors
- In system tests, validate button labels/accept attributes reflect SSOT flags.

---

## Helper Pattern

Helpers read capabilities from the spec instead of matching model names:

```ruby
# claude_helper.rb
supports_thinking = Monadic::Utils::ModelSpec.supports_thinking?(obj["model"])
use_adaptive = supports_thinking &&
               Monadic::Utils::ModelSpec.supports_adaptive_thinking?(obj["model"])
context_window = Monadic::Utils::ModelSpec.get_model_property(obj["model"], "context_window")
max_tokens = ModelTokenUtils.get_max_tokens(obj["model"])
```

```javascript
// model_spec.js
"<adaptive-model>": {
  "supports_thinking": true,
  "supports_adaptive_thinking": true,
  // ...
},
"<budget-model>": {
  "supports_thinking": true,
  // no supports_adaptive_thinking: budget_tokens thinking
  "thinking_budget": { "min": 1024, "default": 10000, "max": null },
  // ...
}
```

Provider-specific mechanisms read from the spec include Claude adaptive thinking vs `budget_tokens`, Gemini `thinking_level` / `thinkingBudget`, and OpenAI `api_type: "responses"`.

### Related Documentation

- **Canonical Vocabulary**: `docs_dev/developer/model_spec_vocabulary.md`
- **Anthropic Implementation**: `docs_dev/ruby_service/vendors/anthropic_architecture.md`
- **Model Spec Reference**: `docker/services/ruby/public/js/monadic/model_spec.js`
