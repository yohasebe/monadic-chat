# Anthropic/Claude Architecture

This document describes the Anthropic (Claude) adapter, `lib/monadic/adapters/vendors/claude_helper.rb`. Model capabilities come from `model_spec.js` and are read through `Monadic::Utils::ModelSpec`.

## Request

Every request to `/v1/messages` carries:

- `anthropic-version: 2023-06-01`
- top-level `cache_control: {type: "ephemeral"}`, for every model
- `stream`: the model's `supports_streaming` (true when not set)

### Beta Headers

`anthropic-beta` is built from:

- the model's `beta_flags` in `model_spec.js` and the app's `betas` (MDSL)
- `advisor-tool-2026-03-01` when the app declares `advisor_tool`
- `mid-conversation-tool-changes-2026-07-01`
- `thinking-binding-controls-2026-08-01` for models with thinking-block binding
- `context-management-2025-06-27` when the model supports context management and the app has not turned it off (`context_management false`)
- `model-context-window-exceeded-2025-08-26`

## Thinking

- Models with `supports_adaptive_thinking: true` get `thinking: {type: "adaptive"}` and `output_config.effort`. The `reasoning_effort` values `minimal`/`low` → `low`, `medium`, `high`, `xhigh` and `max` are passed through; anything else becomes `medium`.
- Other thinking models get `thinking: {type: "enabled", budget_tokens: N}`, with N taken from `max_tokens`:

| `reasoning_effort` | Budget |
|---|---|
| `minimal` | 25% of `max_tokens`, at least 1024, at most 8000 |
| `low` | 50%, at most 16000 |
| `medium` | 70%, at most 32000 |
| `high`, `xhigh`, `max` | 80%, at most 48000 |
| other | 50%, at most 16000 |

- When reasoning is turned off on a model that thinks whenever `thinking` is omitted, the lowest effort the model offers is sent.

## Limits

- `max_tokens` comes from `ModelTokenUtils.get_max_tokens(model)` unless the request sets it.
- Images and PDFs are accepted when the model's `vision_capability` (and `supports_pdf` for PDFs) is not false. Otherwise the request returns "This model does not support image input (vision)."
- Tool calls: at most `MAX_FUNC_CALLS = 20` round trips per user turn (`session[:call_depth_per_turn]`, reset at the start of each turn). When the limit is reached, `tools` and `tool_choice` are removed and the model answers in text.

## Errors and Retries

- `post_json_with_retries` (base vendor helper) makes up to `MAX_RETRIES = 5` attempts, `RETRY_DELAY = 2` seconds apart.
- On a 404 `not_found_error`, a model with `unavailable_fallback` in `model_spec.js` is retried once with the fallback model, and the user is told once per session.
- A context window overflow is reported with the finish reason `model_context_window_exceeded`.

## Streaming

Responses are Server-Sent Events: `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_stop`. Thinking arrives in `thinking` content blocks (`thinking_delta`), separate from the `text` blocks, and is shown in the thinking panel.

## Related Files

- **Implementation**: `docker/services/ruby/lib/monadic/adapters/vendors/claude_helper.rb`
- **SSOT Definitions**: `docker/services/ruby/public/js/monadic/model_spec.js`
- **SSOT Accessors**: `docker/services/ruby/lib/monadic/utils/model_spec.rb`
- **Documentation**: `docs_dev/ssot_normalization_and_accessors.md`
