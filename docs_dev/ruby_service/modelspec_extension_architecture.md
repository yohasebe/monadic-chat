# Model Specification Maintenance Guide

This document defines the operational rules for maintaining `model_spec.js` and the Ruby helper layer that reads it. Treat it as the canonical playbook whenever we add, rename, or retire provider models.

## Source of Truth

- `docker/services/ruby/public/js/monadic/model_spec.js` is the single source of truth for model capabilities (token limits, flags, presets).
- Ruby reads the same information by parsing the JS file via `ModelSpecUtils`.
- No other file may carry authoritative capability tables or hard-coded model names. Derivative data (tests, docs) must always be regenerated from `model_spec.js` changes.

## Invariants

1. **Capability-driven lookups**: runtime code must call helpers (e.g., `ModelSpecUtils.default_for(provider)` or `ModelTokenUtils`) instead of referencing literal model IDs.
2. **Environment overrides only**: defaults for each provider reside in `Monadic::Utils::SystemDefaults`. These should mirror what the UI exposes and respect `ENV` overrides.
3. **Docs reference providers, not SKUs**: public docs link to provider model pages; we never publish a hard-coded list of SKUs. Internal docs may mention placeholders but must call out that developers replace them with official IDs.
4. **Lint guardrails**: `scripts/lint/check_deprecated_models.rb` enforces the banned model term list under `config/deprecated_model_terms.txt`. Update the allow/deny list before touching `model_spec.js`.

## Change Workflow

Use the following checklist whenever a model is added, renamed, or removed. Log outcomes in PR descriptions (even if CI is not in use).

1. **Gather inputs**
   - Confirm the provider announcement and note supported capabilities (vision, reasoning, tool use, etc.).
   - Determine pricing/usage tier only if it affects default selection (otherwise keep it out of docs).

2. **Update `model_spec.js`**
   - Add or modify entries with accurate keys (provider naming convention, usually lowercase with hyphenated suffix).
   - Set `max_output_tokens`, `context_window`, and capability flags. Use ranges when providers specify minimum/maximum; pick conservative defaults when optional.
   - Maintain alphabetical order within each provider section to reduce diff noise.

3. **Update defaults where required**
   - If the provider should surface the new model by default, update `docker/services/ruby/lib/monadic/utils/system_defaults.rb` and the UI mapping in `app/main.js`.
   - Document any new environment variables in `docs/reference/configuration.md` and the Japanese counterpart.

4. **Sync documentation and samples**
   - Replace placeholders or references in `docs/features/custom-models.md` (EN/JA) only when the capability set changes.
   - Ensure `docs/basic-usage/language-models.md` (EN/JA) still points to official provider pages without embedding SKU lists.
   - Update `docs/examples/models.json.example` if the schema changed.

5. **Regenerate related tests**
   - Frontend: adjust `test/frontend/model_spec.test.js` expectations.
   - Ruby: extend or update specs that rely on capability counts (e.g., `spec/unit/api_models_endpoint_spec.rb`).
   - Run the lint script: `npm run lint:deprecated-models`.
   - Execute fast suites locally: `rake spec_unit` and `npm test`. For API-visible behavior, run `RUN_API=true rake spec_api:smoke` against the affected provider(s).

6. **Audit deprecations**
   - When a provider retires a model, remove it from `model_spec.js`, append the name to `config/deprecated_model_terms.txt`, and update the lint script if it should start failing on that term.
   - Clean up docs/samples to eliminate any lingering references.

## Review Checklist

When reviewing a model update, confirm the following before merging:

- [ ] `model_spec.js` syntax is valid (pass `npm run build:model-spec` or `node -c` equivalent).
- [ ] Default model selection still works (`ModelSpecUtils.default_for(provider)` returns a valid key).
- [ ] All required docs and translations are updated.
- [ ] Lint (`npm run lint:deprecated-models`) and fast tests (`rake spec_unit`, `npm test`) ran locally and results are shared in the PR description.
- [ ] API smoke instructions mention any new environment knobs if applicable.

## Extension Tips

- **New provider**: start by adding the provider to `ModelSpecUtils.providers`, create a default entry in `SystemDefaults`, extend `ProviderMatrixHelper` mapping, and add docs describing credential variables. Pilot with a single smoke spec before wiring every app.
- **New capability flag**: introduce the flag in `model_spec.js`, then expose it in `ModelSpecUtils` and the UI (e.g., for new reasoning presets). Keep backward compatibility by defaulting to `false`.
- **Reusable helpers**: if multiple providers share similar selection logic (e.g., “latest dated version”), prefer putting the utility in `ModelSpecUtils` rather than repeating conditionals in adapters.

## Operational Notes

- Because we do not run CI, each developer is responsible for executing the commands above and capturing the output in the PR description.
- If a rollout proves risky, gate new defaults behind an environment variable (e.g., `OPENAI_ENABLE_X_MODEL`). Remove the gate once the provider is stable in production.

## Appendices

### Useful Commands

```bash
# Validate lint guard rails
npm run lint:deprecated-models

# Regenerate frontend bundle (ensures model_spec parsing still works)
npm run build

# Focused API smoke test for a provider
RUN_API=true PROVIDERS=openai rake spec_api:smoke
```

### Contacts

- **ModelSpec steward**: Keep track of provider announcements and own lint term updates.
- **Docs steward**: Ensure docs remain SKU-free and that translations stay in sync.

Update this guide whenever the workflow or toolchain changes.
