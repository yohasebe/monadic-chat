# Substitution Pipeline

The Substitution Pipeline rewrites text at the boundary between the user and the model. Two providers use it:

- **Privacy Filter**: masks personal data before the model sees it (`<<PERSON_1>>`) and restores it in the response. User documentation: `docs/advanced-topics/privacy-filter.md`.
- **Vocabulary**: `${TOKEN}` variables (such as `${SHARED}`) that the model writes and Monadic Chat resolves. User documentation: `docs/docker-integration/shared-folder.md` ("The `${SHARED}` Variable", "Other Interface Variables").

## Classes

| Class | File | Role |
|---|---|---|
| `Monadic::Substitution::Pipeline` | `lib/monadic/substitution/pipeline.rb` | Ordered list of providers; runs each stage and resolves tokens |
| `Monadic::Substitution::Provider` | `lib/monadic/substitution/provider.rb` | Base class; every hook is a no-op by default |
| `Monadic::Substitution::Context` | `lib/monadic/substitution/context.rb` | Read surface over the session hash and the app (`app_name`, `messages`, `turn_count`) |
| `Monadic::Substitution::Registry` | `lib/monadic/substitution/registry.rb` | `${TOKEN}` ownership: rejects two providers claiming one name, and built-in tokens shaped like a Privacy placeholder |
| `Providers::PrivacyFilter` | `lib/monadic/substitution/providers/privacy_filter.rb` | Privacy Filter; also reachable as `Monadic::Utils::Privacy::Pipeline` |
| `Providers::Vocabulary` | `lib/monadic/substitution/providers/vocabulary.rb` | Vocabulary tokens |
| `Monadic::Substitution::Vocabulary` | `lib/monadic/substitution/vocabulary.rb` | Built-in token table (`BUILTINS`), default set, pipeline builder |

## Provider Hooks

| Hook | Privacy Filter | Vocabulary |
|---|---|---|
| `on_input(text, ctx)` | masks personal data | no-op |
| `system_prompt_addendum(ctx)` | — | "## Shared variables" section listing the enabled tokens |
| `on_tool_invoke(name, args, ctx)` | — | expands owned tokens in the arguments, deep over Hash/Array/String |
| `on_output_render(text, ctx)` | restores placeholders | wraps tokens in `<code class="vocab-token">` (not used on the live path; see Display) |
| `owns_token?` / `resolve` / `token_names` | — | the enabled tokens |
| `failure_mode` | `:closed` (errors propagate) | `:open` (errors are logged and the value so far is kept) |

`Pipeline` runs providers in registration order. `resolve_token(name)` returns the first owner's value or nil. `vocabulary_map` merges each provider's `resolved_map`.

## Two Token Forms

| Feature | Form | Made by |
|---|---|---|
| Privacy Filter | `<<TYPE_N>>` (`<<PERSON_1>>`, `<<EMAIL_ADDRESS_2>>`) | the Privacy container (`docker/services/privacy/`) |
| Vocabulary | `${TOKEN}`, single-word UPPER_CASE | `Vocabulary::BUILTINS` |

`Registry.validate_builtins!` checks that built-in tokens are unique, UPPER_CASE, and do not end in `_<digits>`.

## Privacy Filter

The vendor adapters do not run the Privacy Filter through `Pipeline`. They call it directly:

- `apply_privacy_to_messages` (`base_vendor_helper.rb`) masks the user and assistant messages before each request (Gemini: `apply_privacy_to_gemini_contents`). The system prompt is not masked.
- `after_receive_from_llm` restores the response; `sanitize_for_tts` / `sanitize_restored_for_tts` prepare text for speech.
- The instance is kept in `session[:_privacy_pipeline]`. Its registry lives at `session[:monadic_state][:privacy]`; `PrivacyFilter#state` raises `NotImplementedError` so no state is written to `session[:substitution_state]`.

Failure handling:

- **Masking fails closed.** On a backend error, `on_failure: :block` (default) raises `Monadic::Utils::Privacy::BackendError` and the request is not sent. `on_failure: :pass` sends the text unmasked, except when the chat has words the user marked, which still raises. `apply_privacy_to_messages` has no rescue.
- `library_search` replaces its results with `LibrarySearch::WITHHELD_MESSAGE` when masking fails.
- **Restoring falls back to the masked text.** If restoration fails, the user sees the placeholders.

A rescue on the masking path must withhold or raise, never return the input text.

## Vocabulary

### Tokens

| Name (`use :name`) | Token | Value | Display | Default |
|---|---|---|---|---|
| `shared` | `SHARED` | `Environment.shared_volume` | decorate | yes |
| `today` | `TODAY` | `Date.today` (YYYY-MM-DD) | expand | yes |
| `model` | `MODEL` | `parameters["model"]` | expand | yes |
| `app` | `APP` | the app's `display_name` | expand | yes |
| `lang` | `LANG` | `conversation_language`, or `ui_language` when it is `auto` | expand | yes |
| `last_generated_image` | `LAST_GENERATED_IMAGE` | first file of the app's `last_images` state | expand | no |
| `last_uploaded_image` | `LAST_UPLOADED_IMAGE` | last image of the latest user message with images | expand | no |
| `notebook` | `NOTEBOOK` | `notebook_filename` in the app's `context` state | expand | no |

A token whose value is nil is left as the literal `${TOKEN}`.

### Which Tokens an App Has

`Vocabulary.tokens_for(app_settings)` returns `DEFAULT_TOKENS` (`shared today model app lang`) plus the names the app adds, or nothing when the app sets `vocabulary false`. MDSL:

```ruby
vocabulary do
  use :last_generated_image   # adds a non-default token
end

vocabulary false              # no tokens at all
```

`VocabularyConfiguration` (`lib/monadic/dsl/configurations.rb`) raises on an unknown name and stores `{ tokens: [...], enabled: true|false }` in `settings[:vocabulary]`. The Image Generator apps use `last_generated_image` and `last_uploaded_image`; the Jupyter Notebook apps use `notebook`.

Every app also gets the shared-folder file tools: `MonadicDSL.inject_file_operations!` imports `:file_operations` unless the app already does.

### Wiring

- **Pipeline**: `Vocabulary.build_pipeline(session, app_settings)` builds a pipeline with only the Vocabulary provider and keeps it in `session[:_substitution_pipeline]`. It returns nil when the app has no tokens. `BaseVendorHelper#substitution_pipeline_for` calls it.
- **Tool calls**: each vendor's tool dispatch calls `expand_tool_args_for_vocabulary(args, session, app_settings)` before the session is added to the arguments. Text inside backticks is not expanded.
- **System prompt**: the `:vocabulary_variables` rule of `SystemPromptInjector` (priority 65) adds the provider's addendum.
- **Display**: `streaming_handler.rb` puts `vocabulary_map` on the final assistant message (building the pipeline if needed); `html_handler.rb` passes it on. Shape:

  ```ruby
  { "SHARED" => { "value" => "/monadic/data", "display" => "decorate" },
    "TODAY"  => { "value" => "2026-05-31",   "display" => "expand" } }
  ```

- **Variables panel**: `app_data.rb` sets `apps[name]["vocabulary_info"]` from `Vocabulary.describe_for(session, settings)` (`[{token, description, display, value}]`); `vocabulary-panel.js` shows it.
- **New chat**: `Monadic::Workspace::Chats.begin_new!` (Reset, app change, import) drops the session keys that are not kept, `_substitution_pipeline` and `_privacy_pipeline` included. `chat_state` never saves these two keys.
- **Export**: `vocabulary_map` and `privacy_known_entities` are not in `PRIVACY_EXPORT_MESSAGE_KEYS` (`privacy_handler.rb`), so shared exports do not carry them.

### Display in the Browser

`ws-vocabulary-handler.js` walks the rendered message, inline `<code>` included:

- `decorate`: keeps `${TOKEN}` in a `.vocab-token` span with the value as a tooltip. Clicking it calls `window.electronAPI.revealPath` in the Electron app, or copies the value in a browser.
- `expand`: replaces the token with its value in a `.vocab-value` span (not clickable).

`ipcMain('reveal-path')` in `app/main.js` maps `/monadic/data` to the host shared folder, opens the shared folder itself, and shows anything else in its parent folder.

## Files

- `lib/monadic/substitution/`
- `lib/monadic/utils/privacy/`
- `lib/monadic/dsl/configurations.rb`, `lib/monadic/dsl.rb` (`vocabulary`, `inject_file_operations!`)
- `lib/monadic/adapters/base_vendor_helper.rb`
- `lib/monadic/utils/system_prompt_injector.rb`
- `lib/monadic/utils/websocket/{streaming_handler,html_handler,misc_handlers,app_data,privacy_handler}.rb`
- `lib/monadic/workspace/chats.rb`
- `public/js/monadic/ws-vocabulary-handler.js`, `public/js/monadic/vocabulary-panel.js`
- `app/main.js`

## Tests

- `spec/unit/substitution/`
- `spec/golden/privacy/` (recorded Privacy container responses; `capture.rb --verify`)
- `spec/unit/utils/privacy/`
- `spec/unit/dsl/vocabulary_configuration_spec.rb`, `spec/unit/utils/system_prompt_injector_spec.rb`
- `test/frontend/ws-vocabulary-handler.test.js`, `vocabulary-panel.test.js`, `vocabulary-panel-live.test.js`, `markdown-renderer-vocab-tokens.test.js`, `ws-privacy-handler.test.js`
