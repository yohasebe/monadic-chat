**SSOT Normalization and Accessors (Internal)**

This document describes the server-side normalization layer and canonical accessors for model capabilities. It helps Monadic Chat contributors maintain a single vocabulary across providers while staying backward compatible.

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
- Does NOT auto-populate `supports_pdf_upload` (explicit per model to avoid behavior changes).

**Canonical Accessors**
- Prefer these over raw `get_model_property` calls:
  - `tool_capability?(model)`: Non‑false → true
  - `supports_streaming?(model)`: nil→true, else boolean
  - `vision_capability?(model)`: nil→true, else boolean
  - `supports_pdf?(model)`: boolean
  - `supports_pdf_upload?(model)`: boolean
  - `supports_web_search?(model)`: boolean
  - `responses_api?(model)`: boolean

**Helper Guidelines**
- Streaming: Gate by `supports_streaming?`; default to true for undefined.
- Tools: Gate by `tool_capability?`; drop `tools/tool_choice` for false.
- Vision/PDF: Validate before assembling content parts. For URL‑only PDFs, return a clear error (or instruct the user) instead of attaching base64.
- Reasoning: Use `is_reasoning_model`/`reasoning_effort` where applicable; avoid string matching on model names.
- Web search: Use `supports_web_search?` (and provider’s native config) instead of hardcoded lists.
- Audit: When `EXTRA_LOGGING` is enabled, log a single‑line capability summary including the source (spec/fallback/legacy).

**UI Guidance (Cross‑team)**
- The file–attach button is controlled by app features + `vision_capability`.
- Show “Image/PDF” only if `supports_pdf_upload: true`; otherwise show “Image”.
- Keep URL‑only PDF models (`supports_pdf: true`, `supports_pdf_upload: false`) consistent: do not allow `.pdf` in the file input.

**Migration Plan**
- New helpers should use accessors from day one.
- Existing helpers can migrate incrementally:
  1) Replace hardcoded lists with accessors
  2) Add capability audit lines
  3) Remove dead/legacy code paths after stabilization

**Testing**
- Add unit tests for:
  - Normalization mapping (aliases → canonical)
  - Accessor defaults (nil → expected default)
  - URL‑only PDFs (Perplexity) vs file uploads (Claude/Gemini/OpenAI) behaviors
- In system tests, validate button labels/accept attributes reflect SSOT flags.

