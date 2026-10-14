# Model Specification Maintenance Guide

This document gives the rules for maintaining `model_spec.js` and the Ruby layer that reads it, when models are added, renamed or retired.

## Source of Truth

- `docker/services/ruby/public/js/monadic/model_spec.js` is the single source of truth for model capabilities (token limits, flags, presets) and for default models (`providerDefaults`).
- Ruby reads the same file through `Monadic::Utils::ModelSpec` (`lib/monadic/utils/model_spec.rb`), which parses the JS objects.
- No other file carries authoritative capability tables or hard-coded model names.

## Invariants

1. **Capability-driven lookups**: runtime code calls the accessors (`ModelSpec.supports_thinking?`, `ModelSpec.get_model_property`, `ModelTokenUtils.get_max_tokens`, …) instead of matching literal model IDs.
2. **Defaults**: `SystemDefaults.get_default_model(provider)` returns the `<PROVIDER>_DEFAULT_MODEL` value from the config, otherwise `providerDefaults[provider].chat[0]`, otherwise nil. `ModelSpec.get_provider_default` / `default_chat_model` read `providerDefaults` directly.
3. **Docs reference providers, not SKUs**: documentation uses placeholders such as `<model-id>`; the catalog lives in `model_spec.js`.
4. **Lint guardrails**:
   - `npm run lint:deprecated-models` (`scripts/lint/check_deprecated_models.rb`) checks docs, docs_dev and translations against the term list in `config/deprecated_model_terms.txt`.
   - `npm run lint:model-consistency` (`scripts/lint/check_model_consistency.rb`) checks model lifecycle consistency across the codebase.

## Change Workflow

1. **Gather inputs**: confirm the provider announcement and the supported capabilities (vision, reasoning, tool use, etc.).
2. **Update `model_spec.js`**:
   - Add or modify entries with the provider's model ID as the key.
   - Set `max_output_tokens`, `context_window` and the capability flags (see `docs_dev/developer/model_spec_vocabulary.md`).
3. **Update defaults where required**: change `providerDefaults` in `model_spec.js`. Document any new environment variable in `docs/reference/configuration.md` (EN/JA).
4. **Sync documentation and samples**: update `docs/examples/models.json.example` if the schema changed.
5. **Tests**:
   - Frontend: `test/frontend/model_spec.test.js`.
   - Ruby: specs that depend on the catalog (e.g., `spec/unit/api_models_endpoint_spec.rb`).
   - Run `npm run lint:deprecated-models`, `npm run lint:model-consistency`, the Ruby unit specs (`bundle exec rspec spec/unit` from `docker/services/ruby`) and `npm test`. For API-visible behavior, run `rake test:smoke` or `RUN_API=true PROVIDERS=<provider> rake "test:run[api]"`.
6. **Retire models**: when a provider announces a sunset, set `deprecated: true`, `successor` and `sunset_date`, and add the name to `config/deprecated_model_terms.txt`. Delete the entry after `sunset_date` (see `docs_dev/model_architecture_policy.md`).

## Review Checklist

- [ ] `model_spec.js` is valid JavaScript (`node -e 'require("./docker/services/ruby/public/js/monadic/model_spec.js")'`) and the bundle builds (`npm run build:js:verify`).
- [ ] Default model selection still returns a valid key (`ModelSpec.default_chat_model(provider)`).
- [ ] Docs and translations are updated.
- [ ] Lints and fast tests pass.

## Extension Tips

- **New provider**: register it in `MonadicDSL::ProviderConfig` (`lib/monadic/dsl/provider_config.rb`), add its `*_DEFAULT_MODEL` to the `SystemDefaults` map, add `providerDefaults` entries, and extend `spec/support/provider_matrix_helper.rb` for the test matrix.
- **New capability flag**: add the flag in `model_spec.js`, expose an accessor in `Monadic::Utils::ModelSpec`, and use it in the UI if needed. New boolean accessors return false when the flag is absent (some existing ones, such as `supports_streaming?` and `vision_capability?`, default to true).
- **Shared selection logic** (e.g., "latest dated version") belongs in `Monadic::Utils::ModelSpec` or `model_utils.js`, not in the adapters.

## Useful Commands

```bash
# Lint guard rails
npm run lint:deprecated-models
npm run lint:model-consistency

# Rebuild and verify the frontend bundle
npm run build:js:verify

# Focused API test for a provider
RUN_API=true PROVIDERS=openai rake "test:run[api]"
```
