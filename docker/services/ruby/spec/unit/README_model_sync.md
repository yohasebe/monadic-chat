# Model Specification Sync Report

`spec/unit/model_spec_validation_spec.rb` compares the model names in `public/js/monadic/model_spec.js` with the model lists the providers' APIs return. It only prints a report: a difference does not fail the example.

## Running

From `docker/services/ruby/`:

```bash
# The report
bundle exec rspec spec/unit/model_spec_validation_spec.rb -e "generates a comprehensive report" --format documentation

# The same, through the script
./bin/check_model_sync
```

The example calls the live provider APIs (`list_models` of each helper).

## API Keys

A provider is checked only when its key is set in the environment or in `~/monadic/config/env`; otherwise its line says `Skipped (no API key)`.

| Provider | Key | Names compared |
|---|---|---|
| OpenAI | `OPENAI_API_KEY` | `gpt…`, `o1`–`o9…`, `chatgpt…`, `codex…` |
| Claude | `ANTHROPIC_API_KEY` | `claude…` |
| Cohere | `COHERE_API_KEY` | `command…`, `embed…`, `rerank…`, `c4ai…` |
| Mistral | `MISTRAL_API_KEY` | `mistral…`, `open-…`, `codestral…`, `pixtral…`, `ministral…`, `magistral…`, `devstral…`, `voxtral…` |
| Grok (xAI) | `XAI_API_KEY` | `grok…` |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek…` |

Models that `should_exclude_from_model_spec?` matches (speech, transcription, voice and similar models) are left out of the API list before comparing.

## Report

For each provider:

- `Models in API`: the number of models the API returned, after exclusion
- `Models in spec`: the number of `model_spec.js` keys that match the provider's name pattern
- `Missing in spec`: models the API returned that `model_spec.js` does not have
- `Potentially deprecated`: `model_spec.js` keys that the API did not return
- `All models are in sync!` when both lists are empty
- `Error - …` when the API call failed

## Related Files

- `spec/unit/model_spec_validation_spec.rb`
- `public/js/monadic/model_spec.js`
- `lib/monadic/adapters/vendors/*_helper.rb`
- `bin/check_model_sync`
