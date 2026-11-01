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
  - Whether the model accepts PDF file uploads. If false and `supports_pdf` is true, use URL-only (e.g. via `pdf_url`).

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
  - Whether the model supports adaptive thinking mode (Claude models with the flag).
  - When true, uses `thinking: {type: "adaptive"}` + `output_config: {effort: "..."}` instead of explicit `budget_tokens`.
  - The model self-regulates thinking depth based on the effort level.

- thinking_budget: object
  - Gemini: `{ min, max, can_disable, presets: { none, low, medium, high } }`. Claude: `{ min, default, max }`.

- latency_tier: string
  - Values: "slow" | "normal" (free-form). UI may use this to display notices.

- requires_confirmation: boolean
  - When `true`, the model is considered expensive or special and requires explicit user confirmation before use. These models are excluded from the "All Models" dropdown to prevent accidental usage.

- ui_hidden: boolean
  - When `true`, the model is hidden from the "All" models list. Curated lists (MDSL `models`, `providerDefaults.chat`) are not filtered by it. The model remains valid for backend use by agents and scripts. Use this for behavioral variants optimized for specific agent workflows (e.g., `customtools` for bash+tool prioritization) that are not appropriate for general user selection.

- supports_parallel_function_calling: boolean
  - Optional. Provider-specific parallel tool semantics.

- beta_flags: string[]
  - Anthropic-only (e.g., `anthropic-beta` header). Keep provider-specific.

- api_version: string
  - Provider-specific version tagging (e.g., "2023-06-01" for Anthropic).

- native_multiturn_reasoning: boolean
  - Cohere-specific. When `true`, a reasoning model handles the native Cohere v2 multi-turn tool flow with reasoning on, so `cohere_helper`'s single-text flattening workaround is bypassed. Set on models verified to keep the native message array. Absent/false → the flattening workaround applies.

- rejects_forced_tool_choice: boolean
  - The model returns 400 on `tool_choice` `{type: any}` / `{type: tool}`. `claude_helper` sends `{type: auto}` where it would otherwise send `any`.

- thinking_block_binding: boolean
  - The model binds each thinking block to the request prefix (system, tools, earlier messages) that produced it and rejects a replay after that prefix changed. `claude_helper` sends the `thinking-binding-controls-2026-08-01` beta with `thinking.block_binding.prefix_mismatch_behavior: drop_block` so the API drops the affected blocks and continues, and logs `input_transformations`.

- thinking_on_by_default: boolean
  - The API runs adaptive thinking when the request omits `thinking`. Some of these models cannot turn thinking off at all, or only through `between_tools`, which cannot be combined with `block_binding`. `claude_helper` therefore sends reasoning effort "none" on these models as adaptive thinking at the lowest effort in `reasoning_effort`, and the Web UI selects that lowest option when an app asks for "none" and the model does not offer it.

- unavailable_fallback: string
  - Model ID to retry with when this model returns 404 `not_found` (`<model-a>` → `<model-b>`). The helper swaps the model ID and resends the same body. See `claude_helper.rb`.

## Alias Normalization

The server normalizes aliases into canonical properties without removing the originals.

- reasoning_model -> is_reasoning_model
- websearch_capability / websearch -> supports_web_search
- is_slow_model -> latency_tier: "slow"
- responses_api (true) -> api_type: "responses"
- supports_structured_output -> structured_output

Note: `supports_pdf_upload` is never derived; set it explicitly per model where necessary (e.g.: `supports_pdf: true`, `supports_pdf_upload: false`).

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
- ModelSpec.supports_temperature?(model)

These accessors apply conservative defaults (e.g., streaming defaults to true when undefined) in line with existing helper behavior.

### The `temperature` property is the sampling SSOT

A model entry's `"temperature": [[min, max], default]` key means "this model
accepts a user-adjustable temperature". It drives two things:

- The Web UI enables its temperature slider on exactly this key.
- Helpers must NOT send a temperature for models without it
  (`ModelSpec.supports_temperature?`). No Gemini entry carries the key, so MDSL- or caller-supplied temperatures are
  dropped for Gemini models.

To let a future model accept user temperature, add the key to its spec entry;
both the UI slider and the helper gate follow automatically.

## UI Guidance

- Image/PDF/File button (3-tier)
  - Show button when the app supports images and `vision_capability` is true.
  - If `supports_file_inputs` is true, label as "File" and allow extended formats (.xlsx, .docx, .pptx, .csv, .txt, etc.).
  - Else if `supports_pdf_upload` is true, label as "Image/PDF" and allow `.pdf` in file input.
  - Otherwise, label as "Image" and do not allow `.pdf`.
  - URL input section shown only when `api_type === "responses"` and file/PDF is enabled.
  - For URL-only PDFs (e.g.), keep `supports_pdf_upload: false` and instruct users to include PDF URLs in the message.

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
    "chat": ["<default>", "<alt>", ...],
    "code": ["<code-model>", ...],
    "vision": ["<vision-model>"],
    "audio_transcription": ["<stt-model>"],
    "image": ["<image-model>", ...],
    "tts": ["<tts-model>", ...]
  },
  // ... other providers
};
```

**Categories:**
| Category | Usage |
|---|---|
| `chat` | General conversation, UI model dropdowns, MDSL defaults |
| `code` | Code generation agents (the OpenAI, Claude and Grok coding agents) |
| `vision` | Image analysis agent |
| `audio_transcription` | Audio transcription agent |
| `image` | Image generation (OpenAI, Gemini, xAI) |
| `video` | Video generation (Gemini Omni, Grok Imagine) |
| `tts` | Text-to-speech models offered for the provider; the first entry is what `default_tts_model` returns. The chat's speech selector sends the model its `ttsChoices` entry names (below), not by position here |
| `music` | Music generation (Gemini; ElevenLabs, used by Music Generator only when ELEVENLABS_API_KEY is set and the user names ElevenLabs). Resolved inside the generation tool, not a chat dropdown |

> Note: there is no `embedding` category. Help search and the Knowledge Base
> run on the embedding model in the `embeddings_service` container, not on a
> provider API.

**Ruby access** (via `Monadic::Utils::ModelSpec`):
- `get_provider_default(provider, category)` — first model in list
- `get_provider_models(provider, category)` — full list
- `default_chat_model(provider)` / `default_code_model(provider)` / `default_vision_model(provider)` / `default_audio_model(provider)` — convenience accessors
- `default_image_model(provider)` / `default_video_model(provider)` / `default_tts_model(provider)` / `default_music_model(provider)` — media generation accessors
- `provider_default_models` — the whole `providerDefaults` table
- Provider key aliases: `"google"→"gemini"`, `"claude"→"anthropic"`, `"grok"→"xai"`

**Electron access** (via `app/main.js`):
- Uses `require()` to load `model_spec.js` and reads `providerDefaults` directly
- Writes `*_DEFAULT_MODEL` into `~/monadic/config/env` from `providerDefaults[provider].chat[0]` when the user has not set it (not for Ollama)

**Priority chain** for default model resolution:
1. `CONFIG` value of `<PROVIDER>_DEFAULT_MODEL` (user override)
2. `providerDefaults[provider].chat[0]` in model_spec.js (SSOT)
3. nil

**MDSL behavior**: When a `.mdsl` file omits `model`, the DSL engine automatically populates from `providerDefaults.chat`. Apps that need specific models keep explicit `model` overrides.

## ttsChoices (Speech Selector Values)

`ttsChoices` in `model_spec.js` maps each `#tts-provider` value to `{ provider, model }` (Web Speech: `model: null`, `execution: "browser"`). A value saved by an earlier version names its successor with `alias`; a retired choice also sets `retired`, and the page shows a notice when it moves the value.

- Ruby: `Monadic::Utils::TtsProvider.choice` / `provider_of` / `model_for`; `ModelSpec.load_tts_choices` reads the table (cleared by `reload!`)
- JS: `TtsProvider.choice` / `providerOf` / `modelFor` / `idsOf` / `restoreSaved` (`tts-provider.js`)
- How a model is sent and how its text is prepared come from the model's entry: `tts_family`, and for ElevenLabs `tts_endpoint: "convert"` (the whole file instead of `/stream`), `tts_previous_text: false`, `tts_latency_option: false`. The CLI (`scripts/cli_tools/tts_query.rb`) writes a whole file and sends every ElevenLabs model to the convert endpoint
- An alias value (`openai`, `elevenlabs`, `gemini`, `web-speech`) keeps the text family the value had before (`TtsTextProcessors.family_for`), which can differ from its successor's
- `spec/unit/utils/tts_choices_spec.rb` checks that every option in `views/index.erb` is a non-alias value, that each value resolves to a registered, non-deprecated TTS model, and that both stacks give the results in `spec/fixtures/tts/`

## "All Models" Toggle Filtering Policy

The UI provides an "All" toggle next to the Model dropdown. When OFF (default), only curated models are shown (MDSL `models` → `providerDefaults.chat` → single `model`). When ON, all provider models from `modelSpec` are shown, subject to these exclusion rules:

| Rule | Property | Excluded when | Exception |
|---|---|---|---|
| Expensive/special models | `requires_confirmation: true` | Always | None |
| Tool-incapable models | `tool_capability: false` | Always | None |
| Deprecated models | `deprecated: true` | Always (both modes) | None |
| Agent-only models | `ui_hidden: true` | All mode only | None |
| Speech, music and embedding models | `tts_capability: true`, `music_capability: true`, `embedding_dimensions`, `supports_speech_to_speech: true` | All mode | None |

The toggle state is kept in the `show-all-models` cookie. Pro long-thinking tiers are excluded from the catalog (see `docs_dev/model_architecture_policy.md`).

**Implementation:** `getModelsForApp()` and `filterModelsForAllMode()` in `model_utils.js`.

## Adding Models

When adding a new model SKU, prefer this canonical vocabulary in `model_spec.js`. If a provider exposes additional fields, keep them vendor-scoped and document as needed. When updating default models, update `providerDefaults` in `model_spec.js` — this is the single source of truth.

