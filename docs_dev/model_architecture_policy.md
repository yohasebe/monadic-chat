# Model Architecture Policy

## Purpose

Define a consistent, enforceable rule for which AI models should be included in the Monadic Chat catalog (`model_spec.js`). The goal is to keep the user-facing model list aligned with the current generation architecture, prevent fragmentation, and reduce maintenance cost in vendor helpers.

## The Baseline Rule

> **The latest non-preview model of each provider is the architecture baseline. Past models whose architecture diverges from the baseline are dropped from the catalog — even before the provider marks them deprecated.**

A model "diverges" when it forces bespoke handling in the helper code or produces an inconsistent UX that the common code path cannot absorb.

### Current baselines (2026-04)

| Provider | Baseline model | Primary characteristics |
|---|---|---|
| OpenAI | `gpt-5.5` | Responses API, no sampling params, `reasoning_effort: [none, low, medium, high, xhigh]`, streaming. `gpt-5.4` family remains in the catalog as an architecturally clean subset (same spec, cheaper tier). |
| Anthropic | `claude-opus-4-7` / `claude-sonnet-4-6` | Messages API, thinking + adaptive thinking, no sampling params |
| Google | `gemini-3-flash-preview` (preview is current — special case) | `generate_content`, thinking budget |
| xAI | `grok-4-1-fast-*` | `/v1/chat/completions`, reasoning toggle via model variant |
| DeepSeek | `deepseek-v4-flash` | `/v1/chat/completions`, `thinking: { type, reasoning_effort }` object |

## The Concrete OpenAI Rule

An OpenAI model is **eligible** for inclusion if **both** of the following hold:

1. **API path**: `api_type: "responses"` (Responses API), OR explicit `/v1/chat/completions` is the provider's only endpoint.
2. **Sampling params hygiene**: The model spec declares **no** sampling params (no `temperature` / `top_p` / `presence_penalty` / `frequency_penalty`), **or** it explicitly disables them via `supports_temperature: false`, `supports_top_p: false`, etc. (the Codex family's pattern).

**Exceptions** (always kept until natural sunset):
- Models with `deprecated: true` are retained until their `sunset_date` passes.

### Ineligible characteristics (force removal)

- `streaming_not_supported: true` — the UX assumes streaming.
- `supports_streaming: false` — same.
- Incomplete spec: missing `api_type` when the provider's baseline has it.
- `latency_tier: "slow"` combined with `requires_confirmation: true` — requires bespoke UX paths that are not justified for past-generation models.

### Product-level exclusion: "long-thinking Pro" variants

Independently of the architecture rule, **"Pro" tier models that target long asynchronous reasoning workloads are excluded** from the Monadic Chat catalog. Examples: `gpt-5-pro`, `gpt-5.2-pro`, `gpt-5.4-pro`, `gpt-5.5-pro`.

**Why:** These models:
- Are priced 4-10x the base model (e.g., gpt-5.4-pro vs gpt-5.4).
- Commonly drop standard chat capabilities (web search, vision, PDF, structured output).
- Target async "answer after minutes" workflows, not interactive streaming chat.
- `requires_confirmation: true` is a symptom, not the root cause — these models don't fit Monadic Chat's interactive UX regardless of the confirmation gate.

**Exception:** If a provider's entire lineup is "pro-style" (e.g., some reasoning-only vendors), a pro model may be the only available option and should be kept with `requires_confirmation`. This is judged case-by-case.

## Application Examples

### beta.13 (2026-04-25) — OpenAI pruning round 1

**Deleted 10 models**:

| Model | Reason |
|---|---|
| `o1-pro` | No `api_type`, `supports_streaming: false` |
| `o3-pro` | `supports_streaming: false` + `latency_tier: "slow"` + `requires_confirmation` |
| `gpt-5-pro` | `streaming_not_supported: true`, 1-value reasoning vocab |
| `o3-deep-research` | No `api_type`, no `supports_web_search` (incomplete spec) |
| `o4-mini-deep-research` | Same as above |
| `o3`, `o3-mini`, `o4-mini` | Sampling params declared (temperature/top_p/penalty) |
| `gpt-4.1`, `gpt-4.1-mini`, `gpt-4.1-nano` | Sampling params declared |
| `gpt-5-chat-latest`, `gpt-5.1-chat-latest`, `gpt-5.2-chat-latest`, `gpt-5.3-chat-latest` | Sampling params declared |

**Kept**:

- GPT-5.4 family (baseline)
- GPT-5.2 / 5.2-pro (same reasoning vocabulary as 5.4)
- GPT-5.1 (Responses API, no sampling params — clean subset)
- GPT-5 / -mini / -nano (Responses API, no sampling params — clean subset)
- All codex models (`supports_*: false` flags — architecturally clean)
- `gpt-4o` / `gpt-4o-mini` (deprecated, sunset 2026-06-30)

### beta.13 (2026-04-25) — gpt-5.5 integration + Pro exclusion

When `gpt-5.5` launched, two policy actions ran together:

**Baseline shift:** `gpt-5.5` replaces `gpt-5.4` as the OpenAI baseline. The gpt-5.4 family is architecturally identical (Responses API, no sampling params, same reasoning vocabulary) and remains in the catalog as a clean subset — **no gpt-5.4 deletions were triggered**.

**Added:**
- `gpt-5.5` (architecturally clean, 5-value reasoning, Responses API)

**Removed (Pro exclusion rule applied):**
- `gpt-5.4-pro` — long-thinking tier, reduced capabilities (no vision/web search/PDF/structured output), `requires_confirmation: true`.
- `gpt-5.2-pro` — same pattern.
- `gpt-5.5-pro` — not added (would match the same exclusion).

**providerDefaults order:** gpt-5.4 retained at position 0 for cost-conscious defaults ($1.25/M input vs gpt-5.5 at $5.00/M). gpt-5.5 inserted after the 5.4 family. This reflects a product judgment: the catalog baseline (architecture source of truth) and the fallback default (cost/UX profile) can intentionally diverge.

## Applying to Other Providers

The rule structure is provider-agnostic. For each provider:

1. Identify the latest non-preview model (baseline).
2. Enumerate the baseline's architectural characteristics.
3. For each non-deprecated model in the catalog, check whether it diverges in ways that force bespoke helper code paths.
4. Drop the divergent ones (same commit style as `chore(models): drop N <provider> models incompatible with <baseline> architecture`).

## Checklist When Adding a New Model

Before adding a model entry to `model_spec.js`:

- [ ] Does this model match the current baseline's architecture?
- [ ] Does it introduce new sampling params that the baseline doesn't have? If yes, why?
- [ ] Is `supports_streaming: false` or `streaming_not_supported: true` present? If yes, the catalog should not include it.
- [ ] Is `api_type` consistent with the provider's baseline?
- [ ] If `requires_confirmation: true`, is there a strong reason (current-gen "pro" variant with legitimate cost/latency profile)?

If any answer suggests divergence, do **not** add the model. Either the baseline has shifted (update this document first) or the model is not suitable for the catalog.

## Checklist When a New Generation Launches

When a provider releases a major new generation (e.g., GPT-5.5 API GA):

1. Review the new model's architecture; confirm or update the baseline definition above.
2. Run a pruning round: identify past-generation models that diverge from the new baseline.
3. For each divergence, apply the removal checklist. Document the deletions in CHANGELOG.
4. Update `providerDefaults` in `model_spec.js` to use the new baseline.
5. Update relevant MDSL files referencing deleted models.
6. Rebuild JS bundle (`npm run build:js`) and run test suite.
7. Add a new "Application Examples" section above with the round's details.

## Rationale

This policy exists because:

- **Helper code divergence cost**: Every model with different sampling-param expectations requires a conditional branch in 10 vendor helpers. Removing divergent models removes branches, reducing maintenance cost.
- **UX consistency**: Users expect `temperature` and `reasoning_effort` sliders to behave uniformly. Divergent models create surprise.
- **Discoverability of the baseline**: When the catalog contains many generations, users have trouble finding the "right default." Keeping the catalog focused on the baseline and its clean subsets helps.
- **Sunset preemption**: Waiting for the provider's official sunset often means carrying dead code for months. Active pruning reduces this lag.

## Non-goals

- This policy is **not** about which models are "best" — it is about architectural uniformity in the catalog.
- This policy does **not** apply to `deprecated: true` models which have been explicitly marked for natural sunset (those are kept until their sunset date).
- This policy does **not** require the catalog to be exclusively the baseline — clean subsets (e.g., GPT-5.1, GPT-5) that share architecture without divergence are valid catalog members.
