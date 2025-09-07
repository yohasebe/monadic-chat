# SSOT Expansion Plan (Apply to Non‑OpenAI Providers)

Last updated: 2025-09-05

## Goals
- Centralize the “single source of truth (SSOT)” for model capabilities, constraints, and recommended params in `model_spec.js`, gradually removing hardcoded logic and name heuristics from vendor helpers.
- Safely roll out what we did for OpenAI (Responses vs Chat selection, web search, reasoning, tool capability, streaming support, latency hints, verbosity, etc.) to other providers.

## Scope and priority
1. Anthropic (Claude)
2. Google (Gemini)
3. Cohere
4. xAI (Grok)
5. Mistral
6. Perplexity
7. DeepSeek
8. Ollama (included, but later due to local/runtime availability)

## Current issues (typical patterns)
- Name/pattern‑based branches remain in helpers (e.g., `include?("sonnet")`).
- Provider‑specific endpoint choices and parameter disabling are implemented ad‑hoc instead of via SSOT.
- Capability differences (tools/JSON/streaming/vision) are scattered, making new SKU onboarding and docs sync expensive.

## Objectives (port OpenAI approach to others)
- Move capability decisions into `model_spec.js`:
  - `api_type` (responses/chat/completions)
  - `supports_web_search`
  - `reasoning_effort` ([options, default])
  - `tool_capability` (true/false)
  - `supports_streaming` (true/false)
  - `vision_capability` (true/false)
  - `supports_verbosity` (true/false)
  - `latency_tier` (e.g., "slow")
- Vendor helpers shrink to “transport + minimal quirks” (e.g., message shape, error normalization).

## Provider‑specific starting points and migration

### Anthropic (Claude)
- File: `docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`
- Typical hardcodes: thinking/sonnet/oplus detection, JSON mode allowance, tool‑call limits.
- Migration:
  - Define `reasoning_effort`/`supports_thinking` in spec and gate via `supports?(:thinking)` style checks.
  - Spec‑gate `tool_capability`/`supports_streaming`/`vision_capability`.
  - Unify endpoint/param differences in normalization layer (e.g., system→developer mapping).

### Google (Gemini)
- File: `.../vendors/gemini_helper.rb`
- Focus: contents/parts transformation, function_declarations, image IO handling.
- Migration:
  - Spec‑gate `vision_capability`/`tool_capability`/`supports_streaming`.
  - Capture IO limits and mutual exclusions in `constraints` (e.g., tool+json).

### Cohere
- File: `.../vendors/cohere_helper.rb`
- Focus: v2 typed parts shape, reasoning equivalent, JSON/tools differences.
- Migration:
  - Spec‑gate `tool_capability`/`supports_streaming`/`vision_capability`/`reasoning_effort` where applicable.

### xAI (Grok)
- File: `.../vendors/grok_helper.rb`
- Focus: native websearch params, image‑capable model types, streaming event varieties.
- Migration:
  - Spec‑gate `supports_web_search`/`vision_capability`/`supports_streaming`.

### Mistral
- File: `.../vendors/mistral_helper.rb` (if present)
- Focus: presence of chat/tool/streaming; family differences (large/small/mini).
- Migration:
  - Spec‑gate `tool_capability`/`supports_streaming`; add `latency_tier` if needed.

### Perplexity
- File: `.../vendors/perplexity_helper.rb`
- Focus: built‑in vs external search, long‑context/streaming differences.
- Migration:
  - Spec‑gate `supports_web_search`; extend `capabilities.web_search.via` for native vs external.

### DeepSeek
- File: `.../vendors/deepseek_helper.rb`
- Focus: thinking/reasoning handling, streaming variants, image capability.
- Migration:
  - Spec‑gate `reasoning_effort`/`supports_streaming`/`vision_capability`.

### Ollama
- Focus: local runtime model variety; API compatibility variance.
- Migration:
  - Spec‑gate `tool_capability`/`supports_streaming` (phase in by availability).

## Common implementation guide
1. Extend ModelSpec utilities (Ruby)
   - `responses_api?(model)`, `supports_web_search?(model)`, `model_has_property?(model, "reasoning_effort")`, `get_model_property(model, key)`
   - Add syntactic helpers like `supports_streaming?(model)` if needed
2. Normalization layer
   - Utilities for message shape conversion (OpenAI messages / Gemini contents / Cohere typed parts / xAI arrays)
   - Drop/Clamp unsupported params (specify via `accepts` / `constraints` where possible)
3. Response/Error normalization
   - Success: unify key fields (e.g., `text`), and normalize errors into a common structure

- Emergency override (optional): e.g., for Claude, allow `CLAUDE_LEGACY_MODE=true` to temporarily enable streaming/tools/vision/pdf. Useful for rollback during phased rollout.
  - Testing angle: add a single case verifying that enabling `CLAUDE_LEGACY_MODE` flips `supports_streaming`/`tool_capability`/`vision_capability`/`supports_pdf` to true.
- Observability and rollback
  - With `CAPABILITY_AUDIT=1`, log which capability was decided by which source (spec/default/fallback)
  - Provide env‑guard to revert to legacy logic during rollout
- Migration dashboard (optional)
  - Lightweight YAML/JSON overview per provider (spec_driven/hybrid/legacy status)

## Phased rollout (small and safe)
- Phase 0 (observe): Inventory name‑based branches (`rg` listing) and map them to capability vocabulary
- Phase 1 (spec‑first with fallback): Prefer `ModelSpec.get_model_property(model, "tool_capability")`; fall back when undefined
- Phase 2 (normalization): Share message/param normalization and call from helpers
- Phase 3 (list removal): Remove legacy lists/heuristics once coverage is sufficient
- Phase 4 (contract tests): Validate expected behavior via spec (e.g., don’t send tools when `tool_capability: false`)

## Test reinforcement (spec‑driven checks)
- ModelSpec compliance examples
  - Do not send tools when `tool_capability=false`
  - Force `stream=false` when `supports_streaming=false`
  - Inject web search only when `supports_web_search=true`
  - Add/remove reasoning params based on presence of `reasoning_effort`

## Risks and mitigations
- Spec gaps: implicit knowledge in existing branches → add observation logs and fallback; roll out gradually
- UI timing: selection order/async → trailing triggers and helper consolidation
- Cost/latency: mis‑classification for streaming/search → keep `supports_streaming`/`supports_web_search` updated in spec

## Acceptance criteria (all providers)
- No regression across main apps (Chat/Chat Plus/Code Interpreter/Research Assistant, etc.)
- New SKUs can be enabled by spec updates only (no helper changes)
- Logs/tests clearly show spec‑driven branches

## Example task list
- Claude: specify `tool_capability`/`supports_streaming` → replace in helper → light smoke test
- Gemini: specify `vision_capability`/`tool_capability`/`supports_streaming` → replace
- Cohere: replace `tool_capability`/`supports_streaming`, unify typed parts normalization
- xAI: replace `supports_web_search`/`vision_capability`/`supports_streaming`
- Mistral/Perplexity/DeepSeek/Ollama: same (phased)

## Priority (proposal)
1. Anthropic (popular, medium complexity)
2. Gemini (popular, medium‑high complexity)
3. DeepSeek (simple)
4. Cohere (medium)
5. xAI (medium)
6. Mistral (complex)
7. Perplexity (special)
8. Ollama (most special)

## References
- model_spec: `docker/services/ruby/public/js/monadic/model_spec.js`
- ModelSpec utilities: `docker/services/ruby/lib/monadic/utils/model_spec.rb`
- Vendor helpers: `docker/services/ruby/lib/monadic/adapters/vendors/*_helper.rb`
- UI utilities/selection control: `docker/services/ruby/public/js/monadic/*.js`

---
This plan prioritizes safety and small iterations. Start by moving one capability per provider (e.g., `tool_capability`) to spec‑driven control, build confidence, then expand normalization and remove legacy logic.

## Next steps (proposal)
- Phase 0: For Anthropic, make only `tool_capability` spec‑first (fallback to legacy when undefined)
- Phase 1: Add `supports_streaming` → replace in helper (fallback when undefined)
- Split into small PRs and add minimal spec‑driven tests to prevent regressions

