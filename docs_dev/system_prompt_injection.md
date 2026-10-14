# System Prompt Injection

`Monadic::Utils::SystemPromptInjector` (`lib/monadic/utils/system_prompt_injector.rb`) adds text to the system prompt and to user messages according to session settings.

## Contexts

| Context | Rules | Applied to | Separator |
|---|---|---|---|
| `:system` | `SYSTEM_INJECTION_RULES` | The system prompt | `"\n\n---\n\n"` (`DEFAULT_SEPARATOR`) |
| `:user` | `USER_INJECTION_RULES` | The user message | `"\n\n"` (`USER_MESSAGE_SEPARATOR`) |

Every chat provider helper calls `augment` for the system message. The OpenAI, Gemini, Cohere and Ollama helpers also call `augment_user_message`. The DeepSeek helper appends its own web search and JSON format prompts after the augmented system message, and the app's `prompt_suffix` to the last message.

## System Rules

Rules run in descending priority.

| Priority | Rule | Condition | Adds |
|---|---|---|---|
| 100 | `language_preference` | `session[:runtime_settings][:language]` is set | `LanguageConfig.system_prompt_for_language(lang)`; for `auto`, an instruction to answer in the language of the user |
| 90 | `autonomy` | `autonomy` parameter is `high` or `low` | `AUTONOMY_HIGH_PROMPT` / `AUTONOMY_LOW_PROMPT` |
| 80 | `websearch` | `options[:websearch_enabled]`, not `options[:reasoning_model]`, and a non-empty `options[:websearch_prompt]` | The web search prompt |
| 70 | `library_rag` | `library_rag_enabled` is on and the app has `library_search` | Directive, Knowledge Base inventory and filter notes (`build_library_rag_prompt`) |
| 65 | `vocabulary_variables` | The app declares `${TOKEN}` variables in a `vocabulary` block | The list of variables to use verbatim |
| 60 | `stt_diarization_warning` | The `stt_model` parameter contains `diarize` | `DIARIZATION_STT_PROMPT` (do not take a speaker's role) |
| 50 | `math` | `math` parameter is true | `MATH_BASE_PROMPT` plus `MATH_MONADIC_PROMPT` (double backslashes, for Monadic or Jupyter apps) or `MATH_REGULAR_PROMPT` |
| 50 | `math_disabled` | `math` parameter is not true | `MATH_DISABLED_PROMPT` |
| 40 | `system_prompt_suffix` | Non-empty `options[:system_prompt_suffix]` | The suffix |
| 30 | `expressive_speech` | Auto Speech on, the app has not set `expressive_speech false`, and the TTS provider is tag-aware or instruction-mode (`TtsMarkerVocabulary`) | `TtsMarkerVocabulary.prompt_addendum_for(provider, app_is_monadic:)` |
| 29 | `plain_voice_enforcement` | Auto Speech on, no opt-out, and a TTS provider that is neither tag-aware nor instruction-mode | An instruction to write plain prose without speech markers |

## User Rules

| Priority | Rule | Condition | Adds |
|---|---|---|---|
| 10 | `prompt_suffix` | Non-empty `options[:prompt_suffix]` | The suffix |

## API

```ruby
SystemPromptInjector.augment(base_prompt:, session:, options: {}, context: :system, separator: nil)
SystemPromptInjector.augment_user_message(base_message:, session:, options: {})
SystemPromptInjector.build_injections(session:, options: {}, context: :system)
# => [{ name: :rule_name, content: "text" }, ...]
```

- A rule whose condition or generator raises is skipped; the error is logged with `EXTRA_LOGGING=true`.
- Empty contents are dropped when the parts are joined.

## Adding a Rule

1. Add the prompt text as a constant. Use `<<~'PROMPT'` (single-quoted heredoc) when it contains backslashes, such as LaTeX; a double-quoted heredoc turns `\f` in `\frac` into a form feed.
2. Add `{ name:, priority:, condition: ->(session, options) { … }, generator: ->(session, options) { … } }` to `SYSTEM_INJECTION_RULES` or `USER_INJECTION_RULES`. Read session parameters with safe navigation (`session&.[](:parameters)&.[]("key")`).
3. If the rule needs a new option, pass it in the `options:` of the helpers' `augment` calls.
4. Add examples to `spec/unit/utils/system_prompt_injector_spec.rb`, for the rule on and off and for its place in the priority order.

## Related Files

- `docker/services/ruby/lib/monadic/utils/system_prompt_injector.rb`
- `docker/services/ruby/spec/unit/utils/system_prompt_injector_spec.rb`
- `docker/services/ruby/lib/monadic/utils/language_config.rb`
- `docker/services/ruby/lib/monadic/utils/tts_marker_vocabulary.rb`
