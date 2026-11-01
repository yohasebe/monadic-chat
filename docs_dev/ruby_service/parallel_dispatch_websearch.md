# Parallel Dispatch

The `parallel_dispatch` group (`lib/monadic/shared_tools/parallel_dispatch.rb`) provides `dispatch_parallel_tasks`, which sends several prompts to the app's own provider at once and returns the answers together.

## Call

`dispatch_parallel_tasks(tasks:, timeout: nil, websearch: nil, session: nil)`

- `tasks`: 1 to `MAX_PARALLEL_TASKS` (5) hashes with `id` and `prompt`.
- `timeout`: seconds per task, default 120, at most 300.
- Only one call per user turn (`session[:parallel_dispatch_called]`); a second call returns an error telling the model to use the earlier results.
- Model: the session's model, otherwise the provider default.
- Each task runs in a child thread; progress is sent to the session's WebSocket. The result is JSON with each task's `id`, `success` and `content` or `error` ("Timed out after …s" on timeout).

## Provider

`resolve_provider_config` picks the `PROVIDER_CONFIG` entry whose helper module the app includes (OpenAI when none matches). Sub-calls use only that provider's API.

## Web Search

Web search is on when `websearch` is true, otherwise when the session's `websearch` parameter is true.

| Strategy | Providers | How |
|---|---|---|
| `:responses_api` | OpenAI, xAI | Responses API with the `web_search` tool (`responses_api_sub_call`) |
| `:grounding` | Gemini | `google_search` grounding (`gemini_websearch_sub_call`) |
| `:native_tool` | Anthropic | Messages API with the server-side `web_search` tool, `max_uses` 5; only text blocks are kept (`anthropic_websearch_sub_call`) |
| `:tavily` | Mistral, Cohere, DeepSeek | Tavily search before the call, results put in front of the prompt (`tavily_prefetch_and_inject`) |

Tavily:

- Without `TAVILY_API_KEY` the task fails with an error.
- Query: the first 400 characters of the prompt, `search_depth: "basic"`, `max_results: 3`.
- A Tavily error or an empty result leaves the prompt unchanged.

## Tests

```bash
cd docker/services/ruby
bundle exec rspec spec/unit/shared_tools/parallel_dispatch_spec.rb
```
