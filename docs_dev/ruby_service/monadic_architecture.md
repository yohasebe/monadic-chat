# Monadic Mode (Server Side)

The user-facing description is `docs/advanced-topics/monadic-mode.md`. This page lists where the code reads the `monadic` flag and how Session State is stored.

## Session State Storage

`Monadic::SharedTools::MonadicSessionState` (`lib/monadic/shared_tools/monadic_session_state.rb`):

- `monadic_save_state(app: nil, key:, payload:, session: nil, version: nil)` stores `{data:, version:, updated_at:}` in `session[:monadic_state][app][key]`. The version is the previous one plus 1 unless given.
- `monadic_load_state(app: nil, key:, default: nil, session: nil)` returns JSON with `success`, `app`, `key`, `version` (0 when nothing is stored), `updated_at` and `data` (`default` when nothing is stored).
- Errors are returned as `{success: false, error: …}` JSON.

The `session_context` group (`lib/monadic/shared_tools/session_context.rb`) and the tools modules of Chat Plus, Research Assistant, Math Tutor, Novel Writer, Translate, Voice Interpreter, Language Practice Plus, Jupyter Notebook, Image Generator and Video Generator are built on it.

## What `monadic true` Changes

`features do monadic true end` sets `features[:monadic]`, which the app list sends to the UI and the session parameters carry as `monadic`.

| Where | Effect |
|---|---|
| UI (`utilities.js`, `ws-app-data-handlers.js`) | Monadic badge |
| `ws-content-renderer.js` | Passes `isMonadic` to `MarkdownRenderer.render` |
| `html_handler.rb` | Runs context extraction in a background thread after the response (`process_and_broadcast_context`, with the app's `context_schema`) for the sidebar |
| `system_prompt_injector.rb` (`__app_is_monadic?`) | Selects the monadic variant of the TTS instruction-mode addendum |
| `streaming_handler.rb` | No TTS sentinel hold-back for monadic apps |
| `claude_helper.rb` | No thinking when the model supports structured outputs |
| `deepseek_helper.rb` | Wraps the user message with `monadic_unit` (`app_extensions.rb`) |
| `ai_user_agent.rb` | Formats the conversation for the AI User with the flag |

`monadic true` adds no tools; the app imports `session_context` or defines its own load and save tools.

## Speech From a Tool Parameter

`tts_target :tool_param, "<tool>", "<parameter>"` makes auto speech read the given parameter of the tool call (stored in `session[:tts_text]`) instead of the response text. Voice Interpreter and Language Practice Plus use it.

## Related Documentation

- `docs/advanced-topics/monadic-mode.md`
- `docs/advanced-topics/session-context.md`
- `docs/advanced-topics/monadic_dsl.md`
