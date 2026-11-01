# Type Conversion Between Ruby and JavaScript

App settings reach the browser through `prepare_apps_data` (`lib/monadic/utils/websocket/app_data.rb`), which converts each setting before it is sent as JSON over the WebSocket. This page lists the conversions and the rules for new settings.

## Conversions in `prepare_apps_data`

| Setting | Sent as |
|---|---|
| `auto_speech`, `easy_submit`, `initiate_from_assistant`, `math`, `mermaid`, `abc`, `monadic`, `pdf_vector_storage`, `websearch`, `jupyter`, `image_generation`, `video`, `audio_upload`, `privacy_enabled`, `library_save`, `library_search` | The value as is (booleans stay booleans) |
| `models` (Array) | JSON string; for Ollama apps, the installed Ollama models when the list is available |
| `tools` (Array or Hash) | JSON string |
| `imported_tool_groups` (Array) | JSON string, each group with `available` from `MonadicSharedTools::Registry.available?` |
| `disabled` | String (`m.to_s`) |
| Everything else, including `temperature`, `context_size`, `max_tokens`, `reasoning_effort` | String (`m.to_s`), or nil |

`vocabulary_info` is added to every app from `Monadic::Substitution::Vocabulary.describe_for`.

## JavaScript Side

- `window.toBool` (defined in `utilities.js`; other modules use it or an identical fallback) returns the boolean for a boolean, `value === 'true'` for a string, and `!!value` otherwise. Use it wherever a flag is read: the string `"false"` is truthy.
- `models` and `tools` are read with `JSON.parse`.
- Numeric settings arrive as strings; read them with `parseFloat` / `parseInt`.
- When the browser sets a flag in `params`, it uses a boolean (`params["math"] = true`), not a string.

## Adding a Setting

- **Boolean flag**: add the name to the list in `prepare_apps_data` and read it with `toBool()` in `loadParams()` and `proceedWithAppChange()`.
- **Array or object**: add a branch that sends `to_json`, and `JSON.parse` it on the browser side.
- **Number that is compared numerically in JavaScript**: parse it on the browser side, or add it to the list of values sent as is.

## Tests

- `spec/integration/app_switching_integration_spec.rb` covers app switching.

## Related Documentation

- `docs_dev/mdsl/mdsl_type_reference.md`
- `docs_dev/app_isolation_and_session_safety.md`
- `docs/advanced-topics/monadic_dsl.md`
