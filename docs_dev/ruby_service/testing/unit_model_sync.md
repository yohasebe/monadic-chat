# Model Spec Sync Report

`spec/unit/model_spec_validation_spec.rb` ("Model Specification Report") compares the model names in `model_spec.js` with the models each provider's API lists. It prints a report and asserts nothing about the differences.

## Running

```bash
cd docker/services/ruby
bundle exec rspec spec/unit/model_spec_validation_spec.rb --format documentation
```

`bin/check_model_sync` runs the same spec by line number.

## What It Compares

For OpenAI, Claude, Cohere, Mistral, xAI and DeepSeek, when the provider's API key is set (in the environment or the config):

1. `<Helper>.list_models` from the vendor helper.
2. Models that do not belong in `model_spec.js` are dropped: audio, realtime, TTS, STT and transcription, image generation, embedding, voice, code-only and CLI-only models (`should_exclude_from_model_spec?`).
3. The `model_spec.js` keys that match the provider's name pattern.

The report lists, per provider, the counts and:

- **Missing in spec**: listed by the API, absent from `model_spec.js`.
- **Potentially deprecated**: in `model_spec.js`, not listed by the API.

A provider without a key is shown as skipped; an API error is shown and the other providers continue.

## Acting on the Report

- Add a missing chat model to `model_spec.js` with its capabilities (see `docs_dev/ruby_service/modelspec_extension_architecture.md`).
- A model the API does not list is retired as described in `docs_dev/model_architecture_policy.md`. A dated name that the API does not list may still resolve to its base entry (`docs_dev/developer/model_alias_system.md`).
