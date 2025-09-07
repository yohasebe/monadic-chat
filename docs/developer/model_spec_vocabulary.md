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

- supports_web_search: boolean
  - Whether the model has native web search capability.

- is_reasoning_model: boolean
  - Whether the model is a reasoning/thinking model.

- reasoning_effort: [ [options], default ]
  - Example: [["minimal","low","medium","high"], "low"].

- supports_thinking: boolean
  - Whether a provider supports a dedicated thinking/thought budget feature.

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
- ModelSpec.responses_api?(model)

These accessors apply conservative defaults (e.g., streaming defaults to true when undefined) in line with existing helper behavior.

## UI Guidance

- Image/PDF button
  - Show button when the app supports images and `vision_capability` is true.
  - If `supports_pdf_upload` is true, label as "Image/PDF" and allow `.pdf` in file input.
  - Otherwise, label as "Image" and do not allow `.pdf`.
  - For URL-only PDFs (e.g., Perplexity), keep `supports_pdf_upload: false` and instruct users to include PDF URLs in the message.

## Adding Models

When adding a new model SKU, prefer this canonical vocabulary in `model_spec.js`. If a provider exposes additional fields, keep them vendor-scoped and document as needed.

