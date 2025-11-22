**Single Source of Truth (SSOT) Overview**
- Canonical source for model capabilities lives in `public/js/monadic/model_spec.js`.
- UI and server helpers consult this spec to enable/disable features consistently across providers.
- You can extend or override models via `~/monadic/config/models.json` (merged at runtime).

**Key Capabilities (Canonical Properties)**
- api_type: Selects API family (e.g., "responses").
- tool_capability: Enables function/tool calling.
- supports_streaming: Enables server‑sent events (streaming output).
- vision_capability: Enables image input.
- supports_pdf: Model supports PDF handling (general capability).
- supports_pdf_upload: Model supports PDF file uploads (if false, use URL only).
- supports_web_search: Enables native web search.
- is_reasoning_model: Marks reasoning/thinking models.
- reasoning_effort / supports_thinking / thinking_budget: Reasoning controls (vendor‑dependent).
- latency_tier: Slow/normal hint for UI.

**UI Behavior (Buttons and Inputs)**
- Image/PDF attach button appears when:
  - The current app enables images (app feature), and
  - The selected model has `vision_capability: true`.
- Button text and accepted file types:
  - If `supports_pdf_upload: true` → label shows “Image/PDF” and accepts `.pdf`.
  - Otherwise → label shows “Image” only, `.pdf` is not accepted.
- URL‑only PDFs (e.g., Perplexity): paste a public PDF URL into your message instead of uploading a file.

**Provider Notes (Examples)**
- Perplexity: `supports_pdf: true`, `supports_pdf_upload: false` (PDF must be given as URL). Images are supported via URL as well.
- Cohere: PDF uploads are not supported (use other providers or paste text).
- Claude/Gemini/OpenAI: Models indicate PDF/image capabilities in the spec; UI/server honor them.

**Overriding Models**
- Create `~/monadic/config/models.json` to add or modify entries.
- This file merges over the default `model_spec.js` at runtime.
- Prefer the canonical property names above for consistency.

**Troubleshooting**
- If an attach button is missing, check: app image feature, model `vision_capability`, and `supports_pdf_upload`.
- If a PDF upload is rejected, the model may require a URL (check `supports_pdf_upload`).
- Enable `EXTRA_LOGGING` to record a one‑line capability audit in server logs.

**For App Authors**
- Let `model_spec.js` drive behavior; avoid hardcoding model names.
- Prefer feature flags (e.g., `tool_capability`, `supports_streaming`) over lists.
- When in doubt, expose options in your app config, but trust SSOT to gate availability.

