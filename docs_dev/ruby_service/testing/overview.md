# Ruby Service Testing

The specs are in `docker/services/ruby/spec/` and run from `docker/services/ruby` with its own bundle.

## Layout

| Path | Contents |
|---|---|
| `spec_helper.rb` | Common setup |
| `support/` | Shared helpers: `provider_matrix_helper.rb`, `response_evaluator.rb`, `provider_contract_examples.rb`, `provider_defaults_helper.rb`, `docker_container_manager.rb`, `vector_service_helper.rb`, `real_audio_test_helper.rb`, `text_response_assertions.rb`, `test_run_dir.rb`, `summary_formatter.rb`, `custom_retry.rb`, `generator_script_loader.rb` |
| `unit/` | Isolated specs, grouped by area (`adapters/vendors/`, `utils/`, `apps/`, `security/`, `dsl/`, `shared_tools/`, `scripts/`, …) |
| `integration/` | Specs against provider APIs and containers ([integration.md](integration.md)) |
| `system/`, `e2e/`, `performance/` | See [e2e.md](e2e.md) and `docs_dev/ruby_service/development.md` |
| `fixtures/`, `golden/` | Test data |

Test artifacts are written to a timestamped directory under `tmp/test_results/`, or to `TEST_OUTPUT_DIR` when it is set (`support/test_run_dir.rb`).

## Running

```bash
cd docker/services/ruby
bundle exec rspec spec/unit
bundle exec rspec spec/unit/adapters/vendors/claude_helper_spec.rb
```

## Thinking and Reasoning Specs

`spec/unit/openai_reasoning_spec.rb`, `claude_thinking_spec.rb`, `gemini_thinking_spec.rb`, `deepseek_reasoning_spec.rb`, `grok_reasoning_spec.rb`, `mistral_reasoning_spec.rb` and `cohere_thinking_spec.rb` check how each helper extracts and joins thinking content (see `docs_dev/ruby_service/thinking_reasoning_display.md`).
