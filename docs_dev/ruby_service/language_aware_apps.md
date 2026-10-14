# Conversation Language

The conversation language selector (`#conversation-language`) sets the language every app is asked to answer in.

## Flow

1. `SYSTEM_PROMPT` (Start Session) carries `conversation_language`; `misc_handlers.rb` stores it in `session[:runtime_settings][:language]` (`auto` when missing). It is not written into the stored system prompt.
2. `UPDATE_LANGUAGE` changes it during a session and answers with `language_updated` (`language`, `language_name`, `text_direction`).
3. The `language_preference` rule of `SystemPromptInjector` (`lib/monadic/utils/system_prompt_injector.rb`) appends `LanguageConfig.system_prompt_for_language(lang)` to the system prompt on every request. All chat vendor helpers build their system prompt through `SystemPromptInjector.augment`.

## Prompts

`Monadic::Utils::LanguageConfig` (`lib/monadic/utils/language_config.rb`):

- `auto`: answer in the language of the user's message, English when there is none, and do not mention this.
- A language code in `LANGUAGES`: answer in that language unless the user asks to switch.
- An unknown code: nothing is added.

## Text Direction

`text_direction` is `rtl` for `ar`, `he`, `fa` and `ur`, otherwise `ltr`. On `language_updated`, `ws-session-handler.js` adds or removes the `rtl-messages` class on `body`.

## Translation and Language-Learning Apps

Translate, Voice Interpreter, Language Practice and Language Practice Plus receive the same instruction. Their system prompts tell the model which languages to use for the translation or the practice itself, so the selected language applies to greetings, setup questions and explanations.
