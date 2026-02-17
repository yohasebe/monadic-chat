# Parallel Dispatch: Web Search Integration

## Overview

The `ParallelDispatch` shared tool module (`lib/monadic/shared_tools/parallel_dispatch.rb`) supports web search for sub-agents. When enabled, each sub-agent call includes provider-appropriate web search capabilities without introducing tool-call loops.

## Architecture

### Web Search Strategy Routing

Each provider in `PROVIDER_CONFIG` has a `websearch_strategy` that determines how web search is integrated:

| Strategy | Provider(s) | Mechanism |
|---|---|---|
| `:responses_api` | OpenAI, Grok | Responses API (`/v1/responses`) with `web_search` tool |
| `:grounding` | Gemini | `google_search` grounding tool in GenerateContent |
| `:native_tool` | Claude | `web_search_20250305` server-side tool in Messages API |
| `:native` | Perplexity | Built-in search (no changes needed) |
| `:tavily` | Mistral, Cohere, DeepSeek | Tavily API prefetch + prompt injection |

### Activation Flow

```
MDSL features { websearch true }
  -> UI checkbox (#websearch) default ON
  -> params["websearch"] = true/false (based on user toggle)
  -> session[:parameters]["websearch"]
  -> dispatch_parallel_tasks reads session
  -> sub_agent_api_call(websearch: ws_enabled)
  -> strategy-specific sub_call method
```

### Priority

```
Explicit parameter (websearch: true/false) > Session setting > Default (false)
```

## Key Methods

- `responses_api_sub_call` - OpenAI/Grok Responses API with `web_search` tool
- `gemini_websearch_sub_call` - Gemini with `google_search` grounding
- `anthropic_websearch_sub_call` - Claude with `web_search_20250305`, extracts text blocks only
- `tavily_prefetch_and_inject` - Tavily search prefetch, injects results as context before prompt
- `standard_sub_call` - Extracted from original `sub_agent_api_call`, handles non-websearch routing

## Tavily Fallback Behavior

- **TAVILY_API_KEY not set**: Raises `RuntimeError` (prevents silent failure)
- **Tavily API error**: Falls back to original prompt (best-effort)
- **Search query**: Truncated to 400 chars, `search_depth: "basic"`, `max_results: 3`

## Testing

```bash
bundle exec rspec spec/unit/shared_tools/parallel_dispatch_spec.rb
```

Test groups cover: PROVIDER_CONFIG strategies, websearch propagation, all 4 websearch sub_call methods, routing logic, Tavily error handling.
