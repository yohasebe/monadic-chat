# Model Architecture Policy

## Purpose

Define a consistent, enforceable rule for which AI models are included in the Monadic Chat catalog (`model_spec.js`).

## The Baseline Rule

> **The latest non-preview model of each provider is the architecture baseline. Past models whose architecture diverges from the baseline are dropped from the catalog — even before the provider marks them deprecated.**

A model "diverges" when it forces bespoke handling in the helper code or produces an inconsistent UX that the common code path cannot absorb.

### Baseline characteristics

The baseline of each provider is its latest non-preview model in `model_spec.js`. The helper code expects these characteristics:

| Provider | Characteristics |
|---|---|
| OpenAI | Responses API, no sampling params, `reasoning_effort` levels, streaming |
| Anthropic | Messages API, adaptive thinking (`thinking.type: adaptive`), effort via `output_config.effort`, no sampling params |
| Google | `generate_content`, `thinking_level` options; thinking can be turned off with `thinkingBudget: 0` |
| xAI | Responses API (`/v1/responses`) |
| DeepSeek | `/v1/chat/completions`, `thinking: { type, reasoning_effort }` object |

## Deprecation Lifecycle

The baseline rule above governs *architecturally divergent* models. A second,
independent track governs models the provider has scheduled for **sunset**.

> **Mark a model `deprecated: true` with a `successor` as soon as a sunset is
> announced AND any successor exists — a preview successor is acceptable. Keep
> the slim entry as a redirect bridge, also after its `sunset_date` passes, so
> saved sessions that name the model still move to the successor.**

### `deprecated: true` is an early-migration switch, not just a label

Setting `deprecated: true` takes effect immediately, not at sunset:

- **Hidden from every selection surface.** `isModelDeprecated()` filters the
  model out of all dropdown-population paths (app config, MDSL `models`,
  `providerDefaults`) — see `public/js/monadic/model_utils.js`. New sessions
  cannot select it.
- **Pinned configs auto-migrate.** When a saved session or config references a
  deprecated model, it is rewritten to `successor` at load time with a warning
  ("Model X has been replaced with Y") — see `utilities.js` and
  `ws-app-data-handlers.js`.

Users are moved to the successor the moment the flag is set, regardless of how
far away `sunset_date` is.

### Early migration vs early deletion

These are different actions with opposite risk profiles:

- **Early migration** (set `deprecated: true` + `successor` promptly) happens
  automatically via the mechanism above. A preview successor is acceptable
  (`<model> → <successor>-preview` while no GA successor exists).
- **No early deletion**: do not remove a deprecated entry before its
  `sunset_date`. The entry is the redirect source: without it, a pinned old
  model fails as "unknown model" instead of migrating.

**Rule of thumb:** migrate aggressively (flag the moment a successor exists),
and keep the deprecated entry as the redirect source.

## The Concrete OpenAI Rule

An OpenAI model is **eligible** for inclusion if **both** of the following hold:

1. **API path**: `api_type: "responses"` (Responses API), OR explicit `/v1/chat/completions` is the provider's only endpoint.
2. **Sampling params hygiene**: The model spec declares **no** sampling params (no `temperature` / `top_p` / `presence_penalty` / `frequency_penalty`), **or** it explicitly disables them via `supports_temperature: false`, `supports_top_p: false`, etc. (the Codex family's pattern).

**Exceptions** (always kept until natural sunset):
- Models with `deprecated: true` are retained until their `sunset_date` passes (see [Deprecation Lifecycle](#deprecation-lifecycle)).

### Ineligible characteristics (force removal)

- `streaming_not_supported: true` — the UX assumes streaming.
- `supports_streaming: false` — same.
- Incomplete spec: missing `api_type` when the provider's baseline has it.
- `latency_tier: "slow"` combined with `requires_confirmation: true` — requires bespoke UX paths that are not justified for past-generation models.

### Product-level exclusion: "long-thinking Pro" variants

Independently of the architecture rule, **"Pro" tier models that target long asynchronous reasoning workloads are excluded** from the catalog (`<model>-pro`): models that drop standard chat capabilities (web search, vision, PDF, structured output) or target asynchronous "answer after minutes" workflows instead of interactive streaming chat.

**Exception:** If a provider's entire lineup is "pro-style" (e.g., some reasoning-only vendors), a pro model may be the only available option and should be kept with `requires_confirmation`. This is judged case-by-case.

## Applying to Other Providers

The rule structure is provider-agnostic. For each provider:

1. Identify the latest non-preview model (baseline).
2. Enumerate the baseline's architectural characteristics.
3. For each non-deprecated model in the catalog, check whether it diverges in ways that force bespoke helper code paths.
4. Drop the divergent ones.

## Checklist When Adding a New Model

Before adding a model entry to `model_spec.js`:

- [ ] Does this model match the current baseline's architecture?
- [ ] Does it introduce new sampling params that the baseline doesn't have? If yes, why?
- [ ] Is `supports_streaming: false` or `streaming_not_supported: true` present? If yes, the catalog should not include it.
- [ ] Is `api_type` consistent with the provider's baseline?
- [ ] If `requires_confirmation: true`, is there a strong reason (current-gen "pro" variant with legitimate cost/latency profile)?

If any answer suggests divergence, do **not** add the model. Either the baseline has shifted (update this document first) or the model is not suitable for the catalog.

## Checklist When a New Generation Launches

When a provider releases a major new generation:

1. Review the new model's architecture; confirm or update the baseline definition above.
2. Run a pruning round: identify past-generation models that diverge from the new baseline.
3. For each divergence, apply the removal checklist. Document the deletions in CHANGELOG.
4. Update `providerDefaults` in `model_spec.js` to use the new baseline.
5. Update relevant MDSL files referencing deleted models.
6. Rebuild JS bundle (`npm run build:js`) and run test suite.

## Non-goals

- This policy is **not** about which models are "best" — it is about architectural uniformity in the catalog.
- This policy does **not** apply to `deprecated: true` models which have been explicitly marked for natural sunset (those are kept until their sunset date).
- This policy does **not** require the catalog to be exclusively the baseline — older models that share the architecture without divergence are valid catalog members.
