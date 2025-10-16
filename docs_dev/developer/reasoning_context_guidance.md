# Reasoning Context Configuration

This note explains how Monadic Chat handles GPT-5 reasoning context and how it differs from the existing `context_size` knob in app MDSL files.

## Concepts

- **`context_size` (MDSL)**: limits how many turns of the regular chat history (user/assistant/tool messages) we include when building requests. It trims the session buffer to reduce token usage and noise.
- **`reasoning_context` (internal)**: stores the most recent reasoning blocks produced by GPT-5 in Responses API mode. We attach up to three segments back to the `reasoning.context` field on the next request so the model can reuse its own thinking.

These two mechanisms operate independently:

| Feature              | Source                       | Purpose                              |
|----------------------|------------------------------|--------------------------------------|
| `context_size`       | App MDSL (`llm` block)       | Limit prior conversation turns        |
| `reasoning_context`  | Session parameters (adapter) | Reuse GPT-5 reasoning between turns   |

## Default Behaviour

- Apps that list `gpt-5` first in their `model` array now also specify `reasoning_effort "minimal"` by default.
- The OpenAI adapter automatically caches up to `REASONING_CONTEXT_MAX = 3` reasoning segments per session when GPT-5 returns them, and reattaches that cache to subsequent Responses API calls.
- The cache is cleared when no reasoning text is returned or when a new session begins.

## MDSL Exposure

We intentionally do **not** surface `reasoning_context` as an MDSL knob. The cache is an internal transport detail that should stay in sync with the adapter and Responses API contracts. Exposing it in MDSL would make it harder to evolve the retry/caching strategy and could lead to subtle bugs if apps attempt to override the format.

Instead, app authors should:

1. Set `reasoning_effort` explicitly (usually `"minimal"` unless deep chain-of-thought is required).
2. Tune `context_size` based on how much of the user conversation is relevant.
3. Rely on the adapter to handle reasoning cache lifecycle automatically.

## Operational Tips

- When debugging latency, inspect `~/monadic/log/extra.log` for `Processing responses API query` entries alongside the reported `reasoning_tokens` count.
- If reasoning blocks become excessively large, review system prompts and reduce redundant instructions before adjusting adapter parameters.
- Only increase the reasoning cache size if you have a concrete use case that benefits from longer reasoning carryover and you have profiled the trade-offs.

