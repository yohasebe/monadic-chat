# Model Spec Canonical Vocabulary (SSOT)

This document defines the canonical property names used across providers in `model_spec.js` and how aliases are normalized by the server (`ModelSpec` utils). Providers may expose additional vendor-specific fields (e.g., `beta_flags` for Anthropic), but the following vocabulary should be preferred where applicable.

## Canonical Properties

- api_type: string
  - Values: "responses" (OpenAI Responses API). Optional.

- tool_capability: boolean
  - Whether the model can execute tools/function calling.

- supports_streaming: boolean
  - Whether SSE/streaming is supported. If undefined, defaults to true in helpers.

- vision_capability: boolean
  - Whether the model accepts image inputs. If undefined, helpers default to true.

- supports_pdf: boolean
  - Whether the model supports PDFs in general. UI may still need `supports_pdf_upload` to decide file picker state.

- supports_pdf_upload: boolean
  - Whether the model accepts PDF file uploads. If false and `supports_pdf` is true, use URL-only (e.g., Perplexity via `pdf_url`).

- supports_file_inputs: boolean
  - Whether the model supports the OpenAI File Inputs API for extended document types (XLSX, DOCX, PPTX, CSV, TXT, etc.). When true, the UI shows "File" button with extended accept list, and the backend uses file_id caching for efficiency.

- supports_web_search: boolean
  - Whether the model has native web search capability.

- is_reasoning_model: boolean
  - Whether the model is a reasoning/thinking model.

- reasoning_effort: [ [options], default ]
  - Example: [["minimal","low","medium","high"], "low"].

- verbosity: [ [options], default ]
  - GPT-5 series output length control.
  - Example: [["low","medium","high"], "medium"].
  - Some models may only support a subset (e.g., [["medium"], "medium"]).

- supports_thinking: boolean
  - Whether a provider supports a dedicated thinking/thought budget feature.

- supports_adaptive_thinking: boolean
  - Whether the model supports adaptive thinking mode (Claude Opus 4.6+).
  - When true, uses `thinking: {type: "adaptive"}` + `output_config: {effort: "..."}` instead of explicit `budget_tokens`.
  - The model self-regulates thinking depth based on the effort level.

- thinking_budget: object
  - Structure: { min, max, can_disable, presets: { minimal, low, medium, high } }.

- latency_tier: string
  - Values: "slow" | "normal" (free-form). UI may use this to display notices.

- requires_confirmation: boolean
  - When `true`, the model is considered expensive or special and requires explicit user confirmation before use. These models are excluded from the "All Models" dropdown to prevent accidental usage.

- ui_hidden: boolean
  - When `true`, the model is hidden from user-facing UI dropdowns (both curated and "All" modes). The model remains valid for backend use by agents and scripts. Use this for behavioral variants optimized for specific agent workflows (e.g., `customtools` for bash+tool prioritization) that are not appropriate for general user selection.

- supports_parallel_function_calling: boolean
  - Optional. Provider-specific parallel tool semantics.

- beta_flags: string[]
  - Anthropic-only (e.g., `anthropic-beta` header). Keep provider-specific.

- api_version: string
  - Provider-specific version tagging (e.g., "2023-06-01" for Anthropic).

## Alias Normalization

The server normalizes aliases into canonical properties without removing the originals. This ensures backward compatibility while providing a single vocabulary for helpers.

- reasoning_model -> is_reasoning_model
- websearch_capability / websearch -> supports_web_search
- is_slow_model -> latency_tier: "slow"
- responses_api (true) -> api_type: "responses"

Note: We do not auto-populate `supports_pdf_upload` to avoid behavior changes. Explicitly set it per model where necessary (e.g., Perplexity: `supports_pdf: true`, `supports_pdf_upload: false`).

## Accessors (Server)

Helpers should prefer accessors over reading raw properties when possible:

- ModelSpec.tool_capability?(model)
- ModelSpec.supports_streaming?(model)
- ModelSpec.vision_capability?(model)
- ModelSpec.supports_pdf?(model)
- ModelSpec.supports_pdf_upload?(model)
- ModelSpec.supports_web_search?(model)
- ModelSpec.supports_thinking?(model)
- ModelSpec.supports_adaptive_thinking?(model)
- ModelSpec.supports_verbosity?(model)
- ModelSpec.get_verbosity_options(model)
- ModelSpec.responses_api?(model)
- ModelSpec.supports_file_inputs?(model)
- ModelSpec.ui_hidden?(model)

These accessors apply conservative defaults (e.g., streaming defaults to true when undefined) in line with existing helper behavior.

## UI Guidance

- Image/PDF/File button (3-tier)
  - Show button when the app supports images and `vision_capability` is true.
  - If `supports_file_inputs` is true, label as "File" and allow extended formats (.xlsx, .docx, .pptx, .csv, .txt, etc.).
  - Else if `supports_pdf_upload` is true, label as "Image/PDF" and allow `.pdf` in file input.
  - Otherwise, label as "Image" and do not allow `.pdf`.
  - URL input section shown only when `api_type === "responses"` and file/PDF is enabled.
  - For URL-only PDFs (e.g., Perplexity), keep `supports_pdf_upload: false` and instruct users to include PDF URLs in the message.

## Model Lifecycle Fields

These fields manage model deprecation and migration. They are used by the UI to filter dropdowns and by the session loader to auto-migrate saved sessions.

- deprecated: boolean
  - When `true`, the model is hidden from UI model dropdowns and flagged by the lint tool.

- sunset_date: string (ISO 8601, "YYYY-MM-DD")
  - The date when the provider will discontinue the model. The lint tool warns when a sunset date is within 30 days or has passed.

- successor: string
  - The recommended replacement model name. Used by session auto-migration: when a saved session references a deprecated model, it is transparently replaced with its successor on load, and the user is notified.

### Lifecycle Accessors (Server)

- ModelSpec.deprecated?(model)

### Lifecycle Accessors (Frontend)

- isModelDeprecated(modelName) — returns `true` if the model has `deprecated: true`
- getModelSuccessor(modelName) — returns the `successor` string, or `null`
- isModelUiHidden(modelName) — returns `true` if the model has `ui_hidden: true`

### Lint Tool

Run `npm run lint:model-consistency` (or `rake lint:model_consistency`) to check for:
- MDSL files referencing deprecated or unknown models
- `providerDefaults` models that are deprecated or unknown in modelSpec
- Agent/helper code containing deprecated model references
- Models with sunset dates within 30 days or already passed

## providerDefaults (SSOT for Default Models)

Defined in `model_spec.js` after the `modelSpec` object. Maps `provider × category → ordered model list`. The first element is the default.

```javascript
const providerDefaults = {
  "openai": {
    "chat": ["gpt-5.4", "gpt-5.2", ...],
    "code": ["gpt-5.3-codex", ...],
    "vision": ["gpt-4.1-mini"],
    "audio_transcription": ["gpt-4o-mini-transcribe-2025-12-15"],
    "image": ["gpt-image-1.5", "chatgpt-image-latest"],
    "video": ["sora-2", "sora-2-pro"],
    "tts": ["gpt-4o-mini-tts-2025-12-15", "tts-1-hd", "tts-1"]
  },
  // ... other providers
};
```

**Categories:**
| Category | Usage |
|---|---|
| `chat` | General conversation, UI model dropdowns, MDSL defaults |
| `code` | Code generation agents (OpenAI Code, Claude Code, Grok Code) |
| `vision` | Image analysis agent |
| `audio_transcription` | Audio transcription agent |
| `image` | Image generation (OpenAI, Gemini, xAI) |
| `video` | Video generation (Sora, Veo, Grok Imagine) |
| `tts` | Text-to-speech (OpenAI TTS: [0]=4o-mini, [1]=tts-1-hd, [2]=tts-1; Gemini TTS: [0]=flash, [1]=pro) |
| `embedding` | Text embedding (OpenAI: [0]=text-embedding-3-large) |

**Ruby access** (via `Monadic::Utils::ModelSpec`):
- `get_provider_default(provider, category)` — first model in list
- `get_provider_models(provider, category)` — full list
- `default_chat_model(provider)` / `default_code_model(provider)` / `default_vision_model(provider)` / `default_audio_model(provider)` — convenience accessors
- `default_image_model(provider)` / `default_video_model(provider)` / `default_tts_model(provider)` — media generation accessors
- `default_embedding_model(provider)` — embedding model accessor
- Provider key aliases: `"google"→"gemini"`, `"claude"→"anthropic"`, `"grok"→"xai"`

**Electron access** (via `app/main.js`):
- Uses `require()` to load `model_spec.js` and reads `providerDefaults` directly
- Sets `*_DEFAULT_MODEL` environment variables from `providerDefaults[provider].chat[0]` when not already configured by the user
- Replaces the previous `system_defaults.json` dependency

**Priority chain** for default model resolution:
1. ENV variable (user override)
2. `providerDefaults` in model_spec.js (SSOT)
3. Hardcoded fallback

**MDSL behavior**: When a `.mdsl` file omits `model`, the DSL engine automatically populates from `providerDefaults.chat`. Apps that need specific models (e.g., `customtools` variants, Opus tier) keep explicit `model` overrides.

## "All Models" Toggle Filtering Policy

The UI provides an "All" toggle next to the Model dropdown. When OFF (default), only curated models are shown (MDSL `models` → `providerDefaults.chat` → single `model`). When ON, all provider models from `modelSpec` are shown, subject to these exclusion rules:

| Rule | Property | Excluded when | Exception |
|---|---|---|---|
| Expensive/special models | `requires_confirmation: true` | Always | None |
| Tool-incapable models | `tool_capability: false` | Always | **Perplexity** (no tool-capable models exist for this provider) |
| Deprecated models | `deprecated: true` | Always (both modes) | None |
| Agent-only models | `ui_hidden: true` | Always (both modes) | None |

**Rationale:**
- `requires_confirmation` models (e.g., `gpt-5.4-pro`) are high-cost and should only be selected intentionally via MDSL or providerDefaults, not through casual browsing.
- `tool_capability: false` models cannot work with most apps (which define tools). The Perplexity exception exists because all Perplexity models lack tool support — excluding them would leave an empty list.
- The toggle state is persisted via cookie (`show-all-models`) across sessions.

**Implementation:** `filterModelsForAllMode()` in `model_utils.js`.

## Adding Models

When adding a new model SKU, prefer this canonical vocabulary in `model_spec.js`. If a provider exposes additional fields, keep them vendor-scoped and document as needed. When updating default models, update `providerDefaults` in `model_spec.js` — this is the single source of truth.

