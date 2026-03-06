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

### Lint Tool

Run `npm run lint:model-consistency` (or `rake lint:model_consistency`) to check for:
- MDSL files referencing deprecated or unknown models
- `system_defaults.json` using deprecated defaults
- Agent/helper code containing deprecated model references
- Models with sunset dates within 30 days or already passed

## Adding Models

When adding a new model SKU, prefer this canonical vocabulary in `model_spec.js`. If a provider exposes additional fields, keep them vendor-scoped and document as needed.

