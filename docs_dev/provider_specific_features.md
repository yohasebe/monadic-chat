# Provider-Specific Features

> **Status**: Living document
> **Audience**: Monadic Chat maintainers

## Purpose

This document lists the **provider-specific features** Monadic Chat uses: features one provider offers that others do not.

## Where They Are Implemented

- Each feature is implemented in its provider's helper (`lib/monadic/adapters/vendors/*_helper.rb`), using that provider's API. There is no shared feature layer across providers.
- Apps turn features on through the MDSL `features`, `betas` and `context_management` blocks.

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
- [ ] **Beta-header tracking.** If the feature depends on a beta header, the
  header is listed in this document's inventory.
- [ ] **Token accounting.** If the feature introduces a new token-usage
  shape (e.g. `usage.iterations[]` for Advisor Tool, reasoning tokens for
  reasoning models), the helper's token counter handles it correctly and the UI
  displays it without confusion.
- [ ] **Documentation.** At minimum: a short note in `docs_dev/` explaining
  the implementation, and an entry in this document's inventory table. If
  the feature is user-visible, update `docs/` + `docs/ja/`.
- [ ] **Sunset monitoring.** If the upstream feature has a deprecation or
  sunset schedule, record it with the feature's inventory row.

## Current inventory

This table summarizes provider-specific features currently wired into Monadic
Chat. For implementation details, see the linked source or companion docs.

### Claude (Anthropic)

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Prompt caching (`cache_control: ephemeral`) | api_feature | Always on | `claude_helper.rb` | Top-level `cache_control: {type: ephemeral}` on every request |
| Context editing (`clear_thinking`, `clear_tool_uses`) | beta_header | **Default-on** for supported models; MDSL override or `context_management false` to opt out | `claude_helper.rb` | Beta: `context-management-2025-06-27`. See `claude_context_management.md`. Opt-out falls back to `context_size` sliding window only |
| Model context window exceeded handling | beta_header | Always on | `claude_helper.rb` | Beta: `model-context-window-exceeded-2025-08-26` |
| Mid-conversation tool changes | beta_header | Always on (provider-wide) | `claude_helper.rb` (`build_claude_headers_and_body`) | Beta: `mid-conversation-tool-changes-2026-07-01`. Keeps the prompt cache alive when progressive tool disclosure rewrites `tools` between turns. Sent for every Claude model |
| Forced tool choice avoidance | model_param | Model-gated (`rejects_forced_tool_choice`) | `claude_helper.rb` (`configure_claude_tools`) | Models with the flag reject `tool_choice` `any`/`tool`; the helper sends `auto` and relies on the prompt to steer tool use |
| Thinking block binding (`drop_block`) | beta_header + model_param | Model-gated (`thinking_block_binding`) | `claude_helper.rb` (`build_claude_headers_and_body`) | Beta: `thinking-binding-controls-2026-08-01` + `thinking.block_binding.prefix_mismatch_behavior: drop_block`. For models that bind thinking blocks to their prefix. Drops are logged from `input_transformations` |
| Extended thinking (adaptive/budget) | model_param | Model-gated | `claude_helper.rb` | `thinking.type: adaptive\|enabled`, `budget_tokens` |
| Web search tool (native) | server_tool | MDSL `features.websearch` | `claude_helper.rb` | `web_search_20250305`, `max_uses` cap |
| Files API | beta_header | Per-request | `claude_helper.rb` | Beta: `files-api-2025-04-14` |
| Per-app beta headers | beta_header | MDSL `betas [...]` | `claude_helper.rb` | App-level opt-in, e.g. document_generator_claude.mdsl uses `code-execution-2025-08-25`, `skills-2025-10-02` |
| Per-spec beta headers | beta_header | `model_spec.js` `beta_flags` | `claude_helper.rb` | Model-capability-level opt-in |
| **Advisor Tool** | beta_header + server_tool | MDSL `advisor_tool do ... end` | `claude_helper.rb` | Beta: `advisor-tool-2026-03-01`. Auto-added when app opts in. Forces `disable_parallel_tool_use: true`. Used by the Claude versions of Auto Forge, Code Interpreter, Coding Assistant and Jupyter Notebook; the default advisor model is set in `dsl.rb` |
| Multi-turn tool context accumulation | client_side | Automatic | `claude_helper.rb` | Preserves `function_returns` across recursive `api_request("tool")` so the model sees full multi-turn tool history. The same accumulation is in `openai_helper.rb` and `grok_helper.rb` |
| Structured output | api_feature | App config | `claude_helper.rb` | `output_format` |
| Tool choice forcing | api_feature | Internal | `claude_helper.rb` (`configure_claude_tools`) | `tool_choice: {type: any}` unless `rejects_forced_tool_choice` (then `auto`); `disable_parallel_tool_use` when the advisor is on |

**Existing infrastructure to be aware of:**
`claude_helper.rb` already merges beta headers from two sources — `spec_beta`
(from `model_spec`) and `app_beta` (from MDSL `betas [...]`). **New
beta-gated features should hook into this mechanism rather than introducing
parallel beta-header handling.**

### OpenAI

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Responses API (`/v1/responses`) | api_feature | Default for supported models | `openai_helper.rb` | Reasoning token preservation across tool calls |
| Multi-turn tool context accumulation | client_side | Automatic | `openai_helper.rb` | `function_returns` is cleared on `role="user"` and then accumulated across recursive `api_request("tool")` calls so the model sees prior turns' tool_use/tool_result pairs. Applies to both `assemble_openai_chat_tool_results` (Chat Completions) and `assemble_openai_tool_results_from_responses` (Responses API). |
| Server-side compaction (`context_management`) | api_feature | **Default-on** for Responses API requests; MDSL override via `compaction do ... end` or `compaction false` to opt out | `openai_helper.rb` | Default threshold `150_000` tokens (SSOT: `MonadicDSL::CompactionConfiguration::DEFAULT_COMPACT_THRESHOLD`). Opt-out falls back to `context_size` sliding window only. Applies only to Responses API — chat/completions-only models receive no compaction |
| Reasoning effort | model_param | Model-gated + MDSL | `openai_helper.rb` | `reasoning.effort` for models with `reasoning_effort` |
| Adaptive reasoning | model_param | Model-gated | `openai_helper.rb` | Varies by model |
| Structured output (`response_format`) | api_feature | App config | `openai_helper.rb` | `json_object`, `json_schema` |
| File Inputs API + `file_id` caching | api_feature | Automatic | `openai_helper.rb` | See `developer/file_inputs_api.md` |
| Web search tool | server_tool | MDSL `features.websearch` | `openai_helper.rb` | Responses API server tool |
| Code agent delegation | client_side | Shared agent module | `lib/monadic/agents/openai_code_agent.rb` | Orchestrator/code agent split is implemented client-side |

### Gemini

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Thinking level (`thinking_level` options from the spec) | model_param | Model-gated | `gemini_helper.rb` | `thinking_level` |
| Thinking budget | model_param | Model-gated | `gemini_helper.rb` | `thinkingBudget`, `includeThoughts` |
| Code execution | server_tool | MDSL | `gemini_helper.rb` | Provider-native sandbox |
| URL context | api_feature | App config | `gemini_helper.rb` | Inline URL fetching |
| Structured output | api_feature | App config | `gemini_helper.rb` | `response_schema` |

### Grok (xAI)

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Live search / `x_search` | server_tool | MDSL | `grok_helper.rb` | Responses API server tool |
| Reasoning effort | model_param | Model-gated | `grok_helper.rb` | — |
| Multi-turn tool context accumulation | client_side | Automatic | `grok_helper.rb` | `function_returns` and `assistant_function_calls` are concat-accumulated across recursive `api_request("tool")` rounds using the `(obj[...] ||= []).concat(...)` pattern. Prior tool rounds remain visible to the model on the next API call. Cleared on `role="user"` |
| Client-driven context compaction | api_feature | MDSL `compaction do compact_threshold N end` / `compaction false` (same vocabulary as OpenAI) | `grok_compaction.rb` (mixed into `grok_helper`) | xAI is client-driven (2 endpoints), unlike OpenAI's server-side `context_management`. When the uncompacted tail exceeds the threshold, `POST /v1/responses/compact` folds older history into an opaque `cmp_*` blob cached at `session[:grok_compaction]`; input is rebuilt as `[blob, system, live_tail]`. Privacy masking applied before the compact call. Invalidated on edit/delete/reset and model/app/threshold change → degrades to full history. Apps: AutoForge / Code Interpreter / Jupyter / Coding Assistant (Grok variants) |

### DeepSeek

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| Reasoning content (V4 thinking; name-based detection for older names) | model_param | Model-gated | `deepseek_helper.rb` | Fragment output separated as reasoning |
| Tavily web search | server_tool | MDSL | `deepseek_helper.rb` | Shared Tavily adapter |

### Ollama

| Feature | Type | Activation | Source | Notes |
|---|---|---|---|---|
| `think` flag | model_param | Capability-detected | `ollama_helper.rb` | Per-model detection via `/api/show` |
| Structured output (`format`) | api_feature | Ollama 0.5+ | `ollama_helper.rb` | `response_format` translation |
| Tool calling (OpenAI-compatible) | api_feature | Capability-detected | `ollama_helper.rb` | — |
| Dynamic capability detection | client_side | Automatic | `ollama_helper.rb` | See `ollama_dynamic_capabilities.md` |

### Mistral, Cohere

| Provider | Feature | Notes |
|---|---|---|
| Mistral | Tavily web search | Shared adapter |
| Cohere | Tavily web search, reasoning-model detection | Name-based detection |

## Semantic pairs across providers

The following features serve similar UX goals across providers but use
different APIs. We do **not** merge them into a single abstraction; we note
them here so adopters of one feature can check if the equivalent should be
considered for its counterpart.

| UX goal | Claude | OpenAI | Gemini | Others |
|---|---|---|---|---|
| **Mid-generation planning assistance** | Advisor Tool (`advisor-tool-2026-03-01`) | Code agent (client-side) | — | — |
| **Long-conversation compaction** | Context editing (`clear_*`), default-on, opt-out via `context_management false` | Compaction API (default-on, threshold `150_000`), opt-out via `compaction false` | xAI: client-driven compaction (`grok_compaction.rb`). Others fall back to `context_size` sliding window. Unified MDSL pattern: both providers accept `<feature> false` to fall back to client-side trimming only |
| **Extended thinking / reasoning** | `thinking.type` + `budget_tokens` | `reasoning.effort` | `thinking_level` / `thinking_budget` | DeepSeek thinking, Ollama `think` |
| **Prompt caching** | `cache_control: ephemeral` | Automatic (Responses API) | — | — |
| **Server-side web search** | `web_search_20250305` | Responses API web_search | — | Grok live/x search; Tavily fallback for others |
| **File inputs** | Files API (`files-api-2025-04-14`) | File Inputs API + `file_id` cache | — | — |
| **Structured output** | `output_format` | `response_format` (`json_schema`) | `response_schema` | Ollama `format` |

## Default-on provider features with unified opt-out

Claude context editing and OpenAI/xAI compaction are on by default and have an
explicit `false` opt-out:

| DSL call | Behavior |
|---|---|
| *(not specified)* | **Default-on** at the provider's default settings |
| `compaction do compact_threshold N end` (OpenAI) / `context_management do edits [...] end` (Claude) | Custom settings override |
| `compaction false` (OpenAI) / `context_management false` (Claude) | **Explicit opt-out** — falls back to `context_size` sliding window only |

**Rules for implementing this pattern in a new feature:**

1. The DSL method must set `settings[<key>] = false` on explicit opt-out
   (not `nil`) so the helper can distinguish "unset" from "disabled".
2. The `class_def` emit in `dsl.rb` must use `unless settings[<key>].nil?`
   (not `if settings[<key>]`) so `false` is preserved through MDSL reload.
3. The helper must branch on `setting == false` first, then on `Hash`, and
   finally fall through to the default. Log the opt-out case via
   `Monadic::Utils::ExtraLogger.log` so the decision is traceable.
4. Default threshold constants must live in exactly one place — prefer the
   `<Feature>Configuration` class in `dsl/configurations.rb` and reference
   it from the helper (e.g. `MonadicDSL::CompactionConfiguration::DEFAULT_COMPACT_THRESHOLD`).
5. For beta-header-gated features, also skip the beta header when opted out —
   otherwise the server will expect a directive that Monadic isn't sending.

The reference implementations are the compaction handling in `openai_helper.rb`
and the context-management handling in `claude_helper.rb`.

## How to add a feature in this document

When adopting a new provider-specific feature:

1. Implement in the relevant `*_helper.rb`.
2. Add a row to the inventory table above.
3. If user-visible, update `docs/` and `docs/ja/`.
4. Run through the checklist at the top of this document.

## Rules from implemented features

- When `advisor_tool` is enabled, `disable_parallel_tool_use: true` is always set.
- Any app that calls several tools in sequence within one user request depends on the `function_returns` accumulation in the helper.
- System prompts use positive framing ("The task is already complete"), not negative examples, which models tend to reproduce.
