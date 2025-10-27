# Token Counting Strategy (Internal)

This document describes the internal policy for token counting and how it
interacts with provider-reported usage.

## Goals
- Ensure safe pre-send context shaping against model-specific context windows
  and `max_tokens` limits.
- Provide stable, consistent token statistics in the UI.
- Avoid unnecessary complexity and operational fragility.

## Policy

We split responsibilities into two layers:

1) Pre-send context shaping (authoritative)
   - Uses the unified tokenizer pipeline (tiktoken via Flask service).
   - Applies per-model constraints from the SSOT (context window, safety margin,
     reserved output tokens, and any provider-specific overheads) to drop or
     truncate older messages before sending.
   - Rationale: This is the safety gate that must be deterministic and under
     our control to prevent provider-side errors.

2) Post-send statistics (optional)
   - We may show provider-reported usage (input/output) for the latest turn
     in the UI, as it typically aligns closely with billing.
   - This is disabled by default to avoid confusion and ensure a single source
     of truth for token numbers. It can be enabled via `TOKEN_COUNT_SOURCE`.

## Configuration

- `TOKEN_COUNT_SOURCE`
  - Default: `python_only`
  - Values:
    - `python_only`: Always use tiktoken/Flask for counting (recommended).
    - `provider_only` or `hybrid`: Allow using provider-reported usage for the
      latest turn (when available). Hybrid still relies on tiktoken/Flask for
      pre-send shaping.

## Rationale and trade-offs
- Provider usage is great for display, but often lacks per-role granularity and
  may not be available in all streaming modes. We therefore keep provider usage
  as an optional enhancement and retain tiktoken for the authoritative path.
- This keeps complexity low, ensures safety, and avoids user-visible inconsistency.

## Notes for implementers
- Do not rely exclusively on provider usage for pre-send shaping.
- Any code path that sets per-message `tokens` from provider usage must check
  the `TOKEN_COUNT_SOURCE` flag before applying the override.
- Import/export: messages may include a `tokens` field; retain it if present.
