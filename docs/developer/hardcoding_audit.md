# Hardcoding Audit (OpenAI & Providers)

This page tracks model-name hardcoding and the migration to a spec‑driven (SSOT) approach.

Last updated: 2025-09-05

## Summary
- Responses API selection, web search capability, reasoning, tool support, streaming, and latency notices are now driven by `model_spec.js` (SSOT), not hardcoded lists.
- We intentionally keep a coarse exclude list only for model discovery to hide non‑chat SKUs returned by provider `/models`.

## OpenAI Helper (lib/monadic/adapters/vendors/openai_helper.rb)

### High‑Impact items (migrated)
- Responses API model detection: now from `model_spec.js` (`api_type: "responses"`) via `ModelSpec.responses_api?`.
- Web search support: now from `model_spec.js` (`supports_web_search`) via `ModelSpec.supports_web_search?`.
- Reasoning model detection: now from presence of `reasoning_effort` in `model_spec.js`.
- Tool capability: now from `model_spec.js` (`tool_capability: true/false`).
- Streaming support: now from `model_spec.js` (`supports_streaming: true/false`).
- Slow model notice: now from `model_spec.js` (`latency_tier: "slow"` or `is_slow_model: true`).
- Verbosity support: now from `model_spec.js` (`supports_verbosity: true`).

### Remaining by design
- Excluded models for discovery: we keep a narrow, partial‑match deny list in the helper to filter `/models` results (embeddings, TTS, moderation, realtime, legacy, images). This impacts discovery only; all feature gating is spec‑driven.

## Rationale
- SSOT reduces drift and simplifies adapters. New SKUs are supported by updating `model_spec.js`, not multiple code paths.
- Discovery still needs a defensive filter because providers may return many non‑chat SKUs that aren’t in our spec yet.

## Next Targets
- Replace any residual model‑string heuristics (e.g., debug branches) with spec flags where useful.
- Consider adding `streaming_duplicate_fix` style flags only if unavoidable; prefer event‑type–driven stream handling.

