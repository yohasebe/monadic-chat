# Provider-Specific Features

> **Status**: Living document
> **Audience**: Monadic Chat maintainers
> **Last updated**: 2026-04-10

## Purpose

This document catalogs **provider-specific features** used in Monadic Chat and
records the project's policy for adopting new ones. LLM providers increasingly
ship features that do not have equivalents in other providers (Anthropic's
Advisor Tool, OpenAI's Compaction API, Gemini's Thinking Budget, etc.). How we
decide to adopt these features — and how we organize the code when we do — has
long-term consequences for maintainability.

## Guiding principle: Best-of-Breed, not unified abstraction

Monadic Chat intentionally avoids building a **unified provider-feature
abstraction layer** on top of the existing helper system. Each provider helper
(`lib/monadic/adapters/vendors/*_helper.rb`) is already a sufficient level of
abstraction: it presents a consistent Ruby interface while letting each
provider use its own API to its fullest.

The rationale for not introducing a further abstraction layer:

1. **Existing layers are already enough.** The common Web UI, WebSocket
   layer, helper system, MDSL, and `ModelSpec` together form a strong
   abstraction. Adding a provider-feature registry on top would be
   "abstraction of abstraction."
2. **Maintainer context is high.** Monadic Chat's maintainers hold the
   provider-specific knowledge in their heads. A registry solves a problem
   (unfamiliarity with provider differences) that does not exist here.
3. **Early abstractions rot fast in fast-moving domains.** LLM capabilities
   change every few months. Categories we invent today (e.g.
   "planning_assistance") may not fit next year's features. Locking a taxonomy
   into code creates churn.
4. **Runtime cost is asymmetric.** The benefit of a registry appears at
   implementation time (write once, apply everywhere). The cost appears at
   debug and onboarding time (extra indirection between symptom and code).

**What we do instead:**

- Implement each provider-specific feature directly in its own `*_helper.rb`.
- Surface opt-in toggles via MDSL `features` / `betas` / `context_management`
  blocks that are already supported.
- Keep knowledge — not code — unified through this document and the Beta
  Features Dashboard in `MEMORY.md`.

**Future possibility (kept open):** If the number of providers or features
grows beyond what a single maintainer can track, revisit this decision. Until
then, the simpler approach is preferred.

## Checklist for adopting a new provider-specific feature

Before merging a provider-specific feature, verify:

- [ ] **Opt-in, not default.** The feature is gated by MDSL
  (`features do ... end`, `betas [...]`, or a dedicated block). Users who
  don't need it are not affected.
- [ ] **Graceful degradation.** If the feature becomes unavailable (API
  change, rate limit, model deprecation), the app continues to function,
  even if in a reduced mode.
- [ ] **Isolation.** All code paths live in a single `*_helper.rb` or a
  clearly-named sibling module. No cross-provider coupling.
- [ ] **Beta-header tracking.** If the feature depends on a beta header, it
  is added to the Beta Features Dashboard in `MEMORY.md` with header name,
  introduction date, and (if known) GA target.
- [ ] **Token accounting.** If the feature introduces a new token-usage
  shape (e.g. `usage.iterations[]` for Advisor Tool, reasoning tokens for
  o-series), the helper's token counter handles it correctly and the UI
  displays it without confusion.
- [ ] **Documentation.** At minimum: a short note in `docs_dev/` explaining
  the implementation, and an entry in this document's inventory table. If
  the feature is user-visible, update `docs/` + `docs/ja/`.
- [ ] **Sunset monitoring.** If the upstream feature has a deprecation or
  sunset schedule, add it to the Sunset Monitoring table in `MEMORY.md`.

## Current inventory

This table summarizes provider-specific features currently wired into Monadic
Chat. For implementation details, see the linked source or companion docs.

### Claude (Anthropic)

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Prompt caching (`cache_control: ephemeral`) | api_feature | Always on | `claude_helper.rb:513` | Default short-TTL cache applied to system prompt |
| Context editing (`clear_thinking`, `clear_tool_uses`) | beta_header | Model-gated + MDSL override | `claude_helper.rb:516-546` | Beta: `context-management-2025-06-27`. See `claude_context_management.md` |
| Model context window exceeded handling | beta_header | Always on when supported | `claude_helper.rb:545` | Beta: `model-context-window-exceeded-2025-08-26` |
| Extended thinking (adaptive/budget) | model_param | Model-gated | `claude_helper.rb:526-566` | `thinking.type: adaptive\|enabled`, `budget_tokens` |
| Web search tool (native) | server_tool | MDSL `features.websearch` | `claude_helper.rb:~631,667` | `web_search_20250305`, `max_uses` cap |
| Files API | beta_header | Per-request | `claude_helper.rb:1741` | Beta: `files-api-2025-04-14` |
| Per-app beta headers | beta_header | MDSL `betas [...]` | `claude_helper.rb:490-503` | App-level opt-in, e.g. document_generator_claude.mdsl uses `code-execution-2025-08-25`, `skills-2025-10-02` |
| Per-spec beta headers | beta_header | `model_spec.js` `betas` | `claude_helper.rb:490-503` | Model-capability-level opt-in |
| Structured output | api_feature | App config | `claude_helper.rb:~815` | `output_format` |
| Tool choice forcing | api_feature | Internal | `claude_helper.rb:~715` | `tool_choice: {type: any}` |

**Existing infrastructure to be aware of:**
`claude_helper.rb` already merges beta headers from two sources — `spec_beta`
(from `model_spec`) and `app_beta` (from MDSL `betas [...]`). **New
beta-gated features should hook into this mechanism rather than introducing
parallel beta-header handling.**

### OpenAI

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Responses API (`/v1/responses`) | api_feature | Default for supported models | `openai_helper.rb:~1172` | Reasoning token preservation across tool calls |
| Reasoning effort | model_param | Model-gated + MDSL | `openai_helper.rb:~371,516-527` | `reasoning.effort` for o-series and GPT-5-family |
| Adaptive reasoning | model_param | Model-gated | `openai_helper.rb` | Varies by model |
| Structured output (`response_format`) | api_feature | App config | `openai_helper.rb` | `json_object`, `json_schema` |
| File Inputs API + `file_id` caching | api_feature | Automatic | `openai_helper.rb` | See `developer/file_inputs_api.md` |
| Vector Store (PDF cloud) | api_feature | Runtime toggle | `openai_helper.rb` | Alternative to PGVector |
| Web search tool | server_tool | MDSL `features.websearch` | `openai_helper.rb` | Responses API server tool |
| GPT-5-Codex delegation | client_side | Shared agent module | `agents/gpt5_codex_agent.rb` | Executor/codex split is implemented client-side |

### Gemini

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Thinking level (minimal/low/medium/high) | model_param | Gemini 3 | `gemini_helper.rb:~609` | `thinking_level` |
| Thinking budget | model_param | Model-gated | `gemini_helper.rb:~650` | `thinkingBudget`, `includeThoughts` |
| Code execution | server_tool | MDSL | `gemini_helper.rb` | Provider-native sandbox |
| URL context | api_feature | App config | `gemini_helper.rb` | Inline URL fetching |
| Structured output | api_feature | App config | `gemini_helper.rb` | `response_schema` |
| Endpoint split (v1beta / v1alpha) | client_side | Automatic | `gemini_helper.rb:~707` | v1beta for thinking, v1alpha otherwise |

### Grok (xAI)

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Live search / `x_search` | server_tool | MDSL | `grok_helper.rb:~23` | Responses API server tool |
| Reasoning effort | model_param | Model-gated | `grok_helper.rb` | — |

### DeepSeek

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Reasoning (R1 / reasoner variants) | model_param | Name-based detection | `deepseek_helper.rb:~721` | Fragment output separated as reasoning |
| Tavily web search | server_tool | MDSL | `deepseek_helper.rb:22-76` | Shared Tavily adapter |

### Ollama

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| `think` flag | model_param | Capability-detected | `ollama_helper.rb:~395` | Per-model detection via `/api/show` |
| Structured output (`format`) | api_feature | Ollama 0.5+ | `ollama_helper.rb:~411` | `response_format` translation |
| Tool calling (OpenAI-compatible) | api_feature | Capability-detected | `ollama_helper.rb:~401` | — |
| Dynamic capability detection | client_side | Automatic | `ollama_helper.rb:209-228` | See `ollama_dynamic_capabilities.md` |

### Mistral, Cohere, Perplexity

| Provider | Feature | Notes |
|---|---|---|
| Mistral | Tavily web search | Shared adapter |
| Cohere | Tavily web search, reasoning-model detection | Name-based detection |
| Perplexity | `sonar-reasoning-*`, `<think>` tag stripping | Client-side cleanup |

## Semantic pairs across providers

The following features serve similar UX goals across providers but use
different APIs. We do **not** merge them into a single abstraction; we note
them here so adopters of one feature can check if the equivalent should be
considered for its counterpart.

| UX goal | Claude | OpenAI | Gemini | Others |
|---|---|---|---|---|
| **Mid-generation planning assistance** | Advisor Tool (planned) | GPT-5-Codex agent (client-side) | — | — |
| **Long-conversation compaction** | Context editing (`clear_*`) | Compaction API (planned) | — | — |
| **Extended thinking / reasoning** | `thinking.type` + `budget_tokens` | `reasoning.effort` | `thinking_level` / `thinking_budget` | DeepSeek R1 family, Ollama `think` |
| **Prompt caching** | `cache_control: ephemeral` | Automatic (Responses API) | — | — |
| **Server-side web search** | `web_search_20250305` | Responses API web_search | — | Grok live/x search; Tavily fallback for others |
| **File inputs** | Files API (`files-api-2025-04-14`) | File Inputs API + `file_id` cache | — | — |
| **Structured output** | `output_format` | `response_format` (`json_schema`) | `response_schema` | Ollama `format` |

## How to add a feature in this document

When adopting a new provider-specific feature:

1. Implement in the relevant `*_helper.rb`.
2. Add a row to the inventory table above.
3. If beta-header-gated, add to `MEMORY.md` Beta Features Dashboard.
4. If user-visible, update `docs/` and `docs/ja/`.
5. Run through the checklist at the top of this document.

## Planned adoptions

These features are under active consideration. See `MEMORY.md` for current
status and ownership.

- **Claude Advisor Tool** (`advisor-tool-2026-03-01`) — Phase 1 target.
  Integration point: `claude_helper.rb` via existing `spec_beta` / `app_beta`
  merge mechanism. MDSL surface: `betas [...]` or new dedicated opt-in.
  Consumer candidates: AutoForge Claude, Code Interpreter Claude, Coding
  Assistant Claude, Jupyter Notebook Claude.
- **OpenAI Compaction API (GA)** — Phase 3 target. Integration point:
  `openai_helper.rb`. Semantic counterpart to Claude's context editing.
