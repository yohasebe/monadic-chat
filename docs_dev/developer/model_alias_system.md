# Model Alias and Version Filtering

`model_spec.js` usually holds one entry per base model. A dated model name (a base name plus a date or version suffix) that has no entry of its own uses the entry of its base name. The Web UI also uses the suffixes to shorten the model list in All mode.

## Date Suffixes

Both sides recognize the same suffixes. `<base>` is the model name without the suffix.

| Format | Shape | Check |
|---|---|---|
| `YYYY-MM-DD` | `<base>-2025-08-07` | none |
| `YYYYMMDD` | `<base>-20250929` | year 2020–2030, month 1–12, day 1–31 |
| `MM-YYYY` | `<base>-03-2025` | year 2020–2030, month 1–12 |
| `MM-DD` | `<base>-06-17` | month 1–12, day 1–31 |
| `YYMM` | `<base>-2509` | year 20–30, month 1–12 |
| `exp-MMDD` | `<base>-exp-1219` | month 1–12, day 1–31 |
| `NNN` | `<base>-001` | none (a version number, sorted as a pseudo-date) |

A suffix that fails its check is not a date: `-4.1`, `-32b` and `-3100` stay part of the name.

## Ruby

`Monadic::Utils::ModelSpec` (`lib/monadic/utils/model_spec.rb`):

- `normalize_model_name(name)` removes the suffix.
- `resolve_model_alias(name)` returns `name` if `model_spec.js` has it, otherwise the normalized name if that entry exists, otherwise `name`.
- `get_model_spec(name)` and every accessor built on it (`get_model_property`, `supports_thinking?`, …) look up the resolved name.
- `model_exists?(name)` counts a dated name whose base entry exists; `registered?(name)` counts only an exact entry.

## JavaScript

`public/js/monadic/model_utils.js`:

- `extractDateSuffix(name)` returns `{dateString, parsedDate, format}` or null; `getBaseModelName(name)` removes the suffix.
- `getModelSpecWithFallback(name, property)` uses the base entry when the dated name has no entry, or when its entry lacks `property`. `modelRequiresConfirmation`, `isModelDeprecated`, `getModelSuccessor` and `isModelUiHidden` use it.
- `filterToLatestVersions(models)` groups names by base name and keeps, per group:
  - the only name, when there is one;
  - otherwise the dateless name (if present) and the dated name with the latest `parsedDate`.

## Model List in the Web UI

`getModelsForApp(appConfig, showAll)` builds the model dropdown:

- **Curated (default)**: the app's `models`, otherwise `providerDefaults[provider].chat`, otherwise the app's `model`. Deprecated models are removed. No version filtering.
- **All mode**: the `model_spec.js` keys that match the provider's `modelPattern` (`PROVIDER_MODEL_BEHAVIOR`), minus deprecated and `ui_hidden` models, then `filterToLatestVersions`, then `filterModelsForAllMode` (removes `requires_confirmation`, TTS, music, embedding, speech-to-speech and `tool_capability: false` models). The app's MDSL `models` are put first.
- **Speech-to-speech apps** always show their MDSL `models`.
- **Ollama** has no All mode: the app's `models`, otherwise its `model`.

An app's `models` is its MDSL `models`. When the MDSL declares none, `convert_to_class` (`dsl.rb`) sets it to `providerDefaults[provider].chat`. Only when that list is empty does the app use the provider's model list from `Monadic::Utils::ProviderModelCache.fetch`, which falls back to the MDSL `model` and `providerDefaults` when the API call fails. A model the provider API lists therefore does not appear in Curated mode unless it is in `providerDefaults` or the MDSL.

## Keeping `model_spec.js` Small

- Add only the base name when the dated versions share its capabilities.
- Add a dated entry only when its capabilities differ from the base entry, or when no dateless name exists. A dated entry with its own key is used as is and is not merged with the base entry on the Ruby side.

## Adding a Date Format

Add the pattern to `extractDateSuffix()` and `getBaseModelName()` in `model_utils.js` and to `normalize_model_name()` in `model_spec.rb`, and add cases to the tests of both.

## Related Files

- `docker/services/ruby/lib/monadic/utils/model_spec.rb`
- `docker/services/ruby/public/js/monadic/model_utils.js`
- `docker/services/ruby/public/js/monadic/model_spec.js`
- `docker/services/ruby/lib/monadic/utils/provider_model_cache.rb`
- `docs_dev/developer/model_spec_vocabulary.md`
