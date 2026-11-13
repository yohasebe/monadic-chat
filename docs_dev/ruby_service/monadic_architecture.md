# Monadic Mode (Server Side)

The user-facing description is `docs/advanced-topics/monadic-mode.md`. This page lists where the code reads the `monadic` flag and how Session State is stored.

## Session State Storage

`Monadic::SharedTools::MonadicSessionState` (`lib/monadic/shared_tools/monadic_session_state.rb`):

- `monadic_save_state(app: nil, key:, payload:, session: nil, version: nil)` stores `{data:, version:, updated_at:}` in `session[:monadic_state][app][key]`. The version is the previous one plus 1 unless given.
- `monadic_load_state(app: nil, key:, default: nil, session: nil)` returns JSON with `success`, `app`, `key`, `version` (0 when nothing is stored), `updated_at` and `data` (`default` when nothing is stored).
- Errors are returned as `{success: false, error: …}` JSON.

The `session_context` group (`lib/monadic/shared_tools/session_context.rb`) and the tools modules of Chat Plus, Research Assistant, Math Tutor, Novel Writer, Translate, Voice Interpreter, Language Practice Plus, Jupyter Notebook, Image Generator and Video Generator are built on it.

## Session State Kept by Turn

An app whose MDSL sets `turn_state true` (`Monadic::TurnState.enabled?`, `lib/monadic/turn_state.rb`) keeps its state from what each reply changed:

- `monadic_save_state`, `monadic_load_state`, `monadic_update_state` (read and change one value with no other change of the reply in between) and `monadic_put_item` / `monadic_remove_item` / `monadic_load_items` (items of a collection, each under an id the server makes) write to the running reply's record. The record is fixed to the reply's chat, epoch and app (`Workbench::Caller.current`); a change without a running reply, to another app's name, or from a second reply of the same chat (`TurnState::Busy`) is refused.
- `html_handler` seals the record into the message as `state_changes` where it seals `workbench_made` (inside the reply's `:saving`). A reply that ends without its message lets it go (`reply_state` → `TurnState.close`). A record begun before the chat changed under it (`TurnState.changed!`: a message deleted, a file read in, a chat resumed; or the chat's epoch) is let go at the seal.
- Reading folds the chat's messages oldest first over the base (`session[:monadic_state][app]`: the state the chat began with, e.g. a file of an earlier version): for each value the newest change wins, for each item the newest put or removal (a removal stops the base from showing through). Deleting a turn removes its changes. Items keep the order of their earliest remaining record. The fold is cached per chat until its messages or revision change.
- `TurnState::Form` (`lib/monadic/turn_state/form.rb`) checks the changes and the base the same way for saving, the history (`History::Serializer` keeps `state_changes` per message and the base as `monadic_state`), shared files (`privacy_clean_messages`; a masked file masks `data`, keys included, and keeps the form) and imports (`session_routes`; what does not fit is left out and counted as `state_dropped`). The client's `state_changes` are dropped (`streaming_handler`).
- Novel Writer keeps its settings as the value `novel_context`, each character as an item of `characters`, and counts the amount written from the story's sections (`Workbench::Document.section_texts`). A file of an earlier version has its characters made items of the base once, with the ids kept in the base (`_items`, `_ids`).

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
| `ai_user_agent.rb` | Formats the conversation for the AI User with the flag |

`monadic true` adds no tools; the app imports `session_context` or defines its own load and save tools.

## Speech From a Tool Parameter

`tts_target :tool_param, "<tool>", "<parameter>"` makes auto speech read the given parameter of the tool call (stored in `session[:tts_text]`) instead of the response text. Voice Interpreter and Language Practice Plus use it.

## Related Documentation

- `docs/advanced-topics/monadic-mode.md`
- `docs/advanced-topics/session-context.md`
- `docs/advanced-topics/monadic_dsl.md`
