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

Web search is on only when the call passes `websearch: true` and the message being answered may search (`TurnSettings#websearch`: `WEB_SEARCH_IN_CHATS` and the app's MDSL). It is never inherited: a Tavily, DeepSeek or Mistral sub-call sends its query before the subtask runs.

| Strategy | Providers | How |
|---|---|---|
| `:responses_api` | OpenAI, xAI | Responses API with the `web_search` tool (`responses_api_sub_call`) |
| `:grounding` | Gemini | `google_search` grounding (`gemini_websearch_sub_call`) |
| `:native_tool` | Anthropic | Messages API with the server-side `web_search` tool, `max_uses` 5; only text blocks are kept (`anthropic_websearch_sub_call`) |
| `:tavily` | Cohere | Tavily search before the call, results put in front of the prompt (`tavily_prefetch_and_inject`) |
| `:deepseek_search` | DeepSeek | DeepSeek's Search API before the call, results put in front of the prompt (`deepseek_prefetch_and_inject`) |
| `:mistral_search` | Mistral | A one-shot Conversations API request with the `web_search` tool before the call, its answer and sources put in front of the prompt (`mistral_prefetch_and_inject`) |

Tavily:

- Without `TAVILY_API_KEY` the task fails with an error.
- Query: the first 400 characters of the prompt, `search_depth: "basic"`, `max_results: 3`.
- A Tavily error or an empty result leaves the prompt unchanged.

DeepSeek:

- Uses `DEEPSEEK_API_KEY` (`Monadic::SharedTools::DeepSeekSearch.search`); nothing goes to Tavily.
- Query: the prompt with whitespace collapsed, its first 128 characters; `count: 3`. Each result's summary is injected.
- An error or an empty result leaves the prompt unchanged.

Mistral:

- Uses `MISTRAL_API_KEY` (`Monadic::SharedTools::MistralSearch.search`) and Mistral's default chat model for the search; the subtask still runs on the selected model. Nothing goes to Tavily.
- Query: the prompt with whitespace collapsed, its first 400 characters.
- An error leaves the prompt unchanged.

## Tests

```bash
cd docker/services/ruby
bundle exec rspec spec/unit/shared_tools/parallel_dispatch_spec.rb spec/unit/shared_tools/deepseek_search_spec.rb \
  spec/unit/shared_tools/mistral_search_spec.rb
```
