# SSOT Adoption Prep Notes (Anthropic/Claude) — Phase 0: Observation & Inventory

Last updated: 2025-09-05

## Scope
- File: `docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`
- Goal: Identify name-based and hardcoded branches and map them to `model_spec.js` vocabulary.

## Existing hardcodes/branches (to inventory)

1) Model list filtering/fallbacks
- Exclude `"claude-2"` from `/models` discovery.
- Return a fixed fallback array of model IDs on API failure.
- Impact: Requires manual updates when new SKUs arrive. Legacy exclusions can be encoded in SSOT rules.
- Proposal: Add `deprecated: true` and/or `list_exclude: true` (discovery-only) to spec. Keep defensive discovery filters minimal (similar to OpenAI).

2) Beta feature flags (bulk assignment)
- Always add to `anthropic-beta` header:
  - `prompt-caching-2024-07-31`
  - `pdfs-2024-09-25`
  - `output-128k-2025-02-19`
  - `extended-cache-ttl-2025-04-11`
  - `interleaved-thinking-2025-05-14`
  - `fine-grained-tool-streaming-2025-05-14`
- Risk: Mixed availability across models/accounts.
- Proposal: Add `beta_flags: []` in spec per model/family and generate headers from it.

3) Streaming default
- `body["stream"] = true` unconditionally.
- Risk: Not supported in some models/modes; conflicts with strict JSON in cases.
- Proposal: Gate by spec `supports_streaming`. If undefined, fall back to current behavior.

4) Web search
- Logic: `websearch && ModelSpec.supports_web_search?(model)` → inject native tool (`web_search_20250305`).
- Status: Already SSOT-driven. Good.
- Proposal: Structure capabilities: `capabilities.web_search: { type: "native"|"external"|"none", via: "tool"|"parameter" }`.

5) Thinking (reasoning)
- Logic: `ModelSpec.supports_thinking?(model)` and `reasoning_effort != "none"`.
- When enabled:
  - Force `temperature = 1`
  - `body["thinking"] = { effort, max_output_tokens, suffix }`
- Status: Mostly SSOT-driven. Good.
- Proposal: Ensure `reasoning_effort` ([options, default]) alignment; clarify `constraints` for streaming compatibility.

6) Tools capability/selection
- Current: No explicit gate; forwards `tools` if present and auto-sets `tool_choice`.
- Risk: Sends tools to models that don’t support them.
- Proposal: Introduce spec `tool_capability`; when false, omit `tools/tool_choice` (align with OpenAI).

7) Images/PDF (Vision)
- Current: Accepts PDFs/images and converts to Claude document/image blocks (assumes `pdfs-2024-09-25` beta).
- Risk: Not available for some models/accounts.
- Proposal: Add `vision_capability: true/false` and `supports_pdf: true/false` in spec and gate behavior.

8) API version
- Fixed `anthropic-version: 2023-06-01`.
- Proposal: Add `api_version` in spec to enable future switches (default remains current).

## Vocabulary to add/curate in model_spec.js (Anthropic)
- Basics:
  - `api_version`: "2023-06-01"
  - `latency_tier`: "slow" (optional)
- Capabilities:
  - `supports_web_search`: true/false (already used)
  - `reasoning_effort`: [["minimal","low","medium","high"], default]
  - `supports_thinking`: true/false (fast path)
  - `tool_capability`: true/false
  - `supports_streaming`: true/false
  - `vision_capability`: true/false
  - `supports_pdf`: true/false
  - `supports_verbosity`: true/false (if needed)
- `beta_flags`: ["prompt-caching-...", "pdfs-...", ...]
- `constraints` (optional):
  - `json_mode_with_tools: "forbidden"|"buggy"`
  - `thinking_with_streaming: "ok"|"limited"`

## Phase 1 candidates (safe, minimal diffs)
1) `tool_capability` gate
- Omit `tools/tool_choice` when false. Limited blast radius, low regression risk.

2) `supports_streaming` gate
- Set `stream=false` when false. Default stays current behavior if undefined.

3) `vision_capability`/`supports_pdf` gate
- Do not send image/PDF blocks when false (return error or hide UI).

4) `beta_flags` generation
- Join spec flags into `anthropic-beta`. If undefined, keep current hardcoded list.

## Code hotspots (where to change)
- Model list: `list_models` (claude-2 exclusion + fallback array)
- Web search: `use_native_websearch` check (SSOT) + tool injection
- Thinking: config by `supports_thinking?` and `reasoning_effort`
- Streaming: `body["stream"] = true` (→ gate by `supports_streaming`)
- Tools: conditions for `tool_choice` (→ gate by `tool_capability`)
- Vision: image/PDF block injection (→ gate by `vision_capability/supports_pdf`)
- Beta: `anthropic-beta` hardcoded list (→ assemble from `beta_flags`)

## Validation (minimal smoke)
- Chat/Chat Plus apps with websearch ON/OFF and thinking ON/OFF should pass.
- When attaching an image/PDF, unsupported models should either error clearly or UI should hide the entry point (handled separately on UI side).
- Toggle streaming ON/OFF and ensure correct behavior.

## Next steps
- Phase 1: Make `tool_capability` and `supports_streaming` spec-first (fallback to current logic when undefined).
- Then add `vision_capability`/`supports_pdf` and `beta_flags`.
- Split changes into small PRs and log decision sources (spec/default/fallback) for observability.
