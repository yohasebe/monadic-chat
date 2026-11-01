# Research Assistant Variants

Research Assistant has OpenAI, Claude, Gemini, Grok, Mistral, Cohere and DeepSeek variants (`apps/research_assistant/research_assistant_<provider>.mdsl`). They share `research_assistant_tools.rb`.

## Settings by Variant

| Variant | Web search | `monadic` | Progress tools | Code agent |
|---|---|---|---|---|
| OpenAI | Native (`websearch true`) | true | yes | `openai_code_agent` (conditional) |
| Claude | Native (`websearch true`) | true | yes | — |
| Gemini | Native (`websearch true`) | true | yes | — |
| Grok | Native (`websearch true`) | true | yes | `grok_code_agent` (conditional) |
| Mistral | Tavily (on when `TAVILY_API_KEY` is set) | true | yes | — |
| Cohere | Tavily (on when `TAVILY_API_KEY` is set) | true | yes | — |
| DeepSeek | Tavily (on when `TAVILY_API_KEY` is set) | — | — | — |

- "Progress tools": `load_research_progress`, `save_research_progress`, `add_finding`, `add_research_topics`, `add_search`, `add_sources`, `add_research_notes`, on Session State (`MonadicSessionState`).
- All variants import `file_operations`, `python_execution`, `file_reading`, `planning` and `parallel_dispatch` (always visible), and `image_analysis` (conditional). `web_search_tools` (conditional) is imported by all but Gemini; `web_automation` (conditional) by OpenAI, Claude, Gemini and Grok.
- All variants set `context_size 30`. The Claude variant sets its own `context_management` (tool results are cleared from 50,000 input tokens).
- The DeepSeek variant has a short system prompt that allows one call per tool per user message.

## Web Search Paths

- OpenAI, Claude, Grok: the provider's own web search, through the vendor helper. For Claude, `ANTHROPIC_NATIVE_WEBSEARCH=false` turns the native search off.
- Gemini: with function declarations in the request, the helper adds the `gemini_web_search` function instead of `google_search` grounding (see [gemini_tool_continuation_fix.md](../docs/gemini_tool_continuation_fix.md)).
- Mistral, Cohere, DeepSeek: the Tavily tools of `web_search_tools`.

`dispatch_parallel_tasks` uses the same split for its sub-calls (see [parallel_dispatch_websearch.md](../parallel_dispatch_websearch.md)).

## Related Documentation

- [DeepSeek Architecture](../vendors/deepseek_architecture.md)
- [Monadic Mode (server side)](../monadic_architecture.md)
- [OpenAI Code Agent](openai_code_agent.md)
