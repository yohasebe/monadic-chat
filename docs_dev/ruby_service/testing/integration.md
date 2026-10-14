# Integration Tests

Integration specs are in `docker/services/ruby/spec/integration/`.

## Provider Matrix

`provider_matrix/all_providers_all_apps_spec.rb` has three groups, generated for each app that exists for each provider: Basic Response, Tool Invocation, and Initial Message (apps with `initiate_from_assistant`). Replies are judged by `ResponseEvaluator` in `spec/support/response_evaluator.rb`: fixed rules first (errors, refusals, known good patterns), then an OpenAI model when the rules are inconclusive.

```bash
RUN_API=true bundle exec rspec spec/integration/provider_matrix/
PROVIDERS=openai,anthropic RUN_API=true bundle exec rspec spec/integration/provider_matrix/
DEBUG=true PROVIDERS=openai RUN_API=true bundle exec rspec spec/integration/provider_matrix/
```

- Without `PROVIDERS`: openai, anthropic, gemini, mistral, cohere, deepseek, xai, plus ollama when `INCLUDE_OLLAMA=true`.
- `PROVIDER_CONFIG` maps a provider to its class suffix, file suffix and timeout; `APP_TEST_CONFIGS` holds each app's `prompt` and `expectation`.
- The examples are skipped without `OPENAI_API_KEY`, and for providers that are not configured.

## Other Specs

| Area | Files |
|---|---|
| Media (needs `RUN_MEDIA=true`) | `api_media/image_generation_all_providers_spec.rb`, `api_media/voice_pipeline_spec.rb` |
| Jupyter | `jupyter_*_spec.rb`, `gemini_jupyter_combined_function_spec.rb` |
| Voice | `voice_*_spec.rb` |
| Browser | `selenium_integration_spec.rb` |
| Vector store | `qdrant/`, `embeddings/`, `library/`, `library_import_contract_spec.rb` |
| WebSocket | `websocket_tab_isolation_spec.rb` |
| Web search | `native_websearch_integration_spec.rb`, `parallel_dispatch_websearch_spec.rb`, `tavily_api_missing_spec.rb`, `xai_websearch_parameters_spec.rb` |
| Tokenizer | `tokenizer_spec.rb` |

## `Monadic::Utils::ResponseEvaluator`

A separate evaluator in `lib/monadic/utils/response_evaluator.rb` asks an OpenAI model whether a reply meets an expectation.

```ruby
result = Monadic::Utils::ResponseEvaluator.evaluate(
  response: reply, expectation: "The AI greeted the user", prompt: "Say hello."
)
result.match       # true / false
result.confidence  # 0.0–1.0
result.success?    # match and confidence >= 0.7
```

`batch_evaluate(response:, expectations:)` checks several expectations, and `matches?(…, threshold: 0.7)` returns a boolean.

## Environment Variables

| Variable | Effect |
|---|---|
| `RUN_API=true` | Run specs that call provider APIs |
| `RUN_MEDIA=true` | Run media generation specs |
| `PROVIDERS` | Comma-separated providers |
| `INCLUDE_OLLAMA=true` | Add Ollama to the default provider list |
| `DEBUG=true` | Print debug output |

## Guidelines

- Check that the app works (non-empty reply, no runtime error), not the wording.
- Skip on infrastructure timeouts instead of failing.
- Judge meaning with an evaluator, not string equality.
