# Monadic Mode (Server Side)

The user-facing description is `docs/advanced-topics/monadic-mode.md`. This page lists where the code reads the `monadic` flag and how Session State is stored.

## Session State Storage

`Monadic::SharedTools::MonadicSessionState` (`lib/monadic/shared_tools/monadic_session_state.rb`):

- `monadic_save_state(app: nil, key:, payload:, session: nil, version: nil)` stores `{data:, version:, updated_at:}` in `session[:monadic_state][app][key]`. The version is the previous one plus 1 unless given.
- `monadic_load_state(app: nil, key:, default: nil, session: nil)` returns JSON with `success`, `app`, `key`, `version` (0 when nothing is stored), `updated_at` and `data` (`default` when nothing is stored).
- Errors are returned as `{success: false, error: …}` JSON.

The tools modules of Research Assistant, Math Tutor, Novel Writer, Translate, Voice Interpreter, Language Practice Plus, Jupyter Notebook, Image Generator and Video Generator are built on it.

## Session State Kept by Turn

An app whose MDSL sets `turn_state true` (`Monadic::TurnState.enabled?`, `lib/monadic/turn_state.rb`) keeps its state from what each reply changed:

- `monadic_save_state`, `monadic_load_state`, `monadic_update_state` (read and change one value with no other change of the reply in between) and `monadic_put_item` / `monadic_remove_item` / `monadic_load_items` (items of a collection, each under an id the server makes) write to the running reply's record. The record is fixed to the reply's chat, epoch and app (`Workbench::Caller.current`); a change without a running reply, to another app's name, or from a second reply of the same chat (`TurnState::Busy`) is refused.
- `html_handler` seals the record into the message as `state_changes` where it seals `workbench_made` (inside the reply's `:saving`). A reply that ends without its message lets it go (`reply_state` → `TurnState.close`). A record begun before the chat changed under it (`TurnState.changed!`: a message deleted, a file read in, a chat resumed; or the chat's epoch) is let go at the seal.
- Reading folds the chat's messages oldest first over the base (`session[:monadic_state][app]`: the state the chat began with, e.g. a file of an earlier version): for each value the newest change wins, for each item the newest put or removal (a removal stops the base from showing through). Deleting a turn removes its changes. Items keep the order of their earliest remaining record. The fold is cached per chat until its messages or revision change.
- `TurnState::Form` (`lib/monadic/turn_state/form.rb`) checks the changes and the base the same way for saving, the history (`History::Serializer` keeps `state_changes` per message and the base as `monadic_state`), shared files (`privacy_clean_messages`; a masked file masks `data`, keys included, and keeps the form) and imports (`session_routes`; what does not fit is left out and counted as `state_dropped`). The client's `state_changes` are dropped (`streaming_handler`).
- Novel Writer keeps its settings as the value `novel_context`, each character as an item of `characters`, and counts the amount written from the story's sections (`Workbench::Document.section_texts`). A file of an earlier version has its characters made items of the base once, with the ids kept in the base (`_items`, `_ids`).
- The other apps with a state hold a Hash whose list fields gather entries: `monadic_load_record` / `monadic_save_record` (`lib/monadic/shared_tools/monadic_session_state.rb`) read and save it whole, keeping each entry of a list (`LISTS` in the app's tools: field => the entry's field that names it) as an item and the rest as one value; only entries added, changed or left out are recorded. `monadic_record_base!` turns the lists of a base of an earlier version into items once (Novel Writer uses it too). Without `turn_state` they read and save the Hash as one value, as before.
- What reads an app's state outside its tools (`Substitution::Vocabulary` for `${NOTEBOOK}` and the last image, `ToolImageUtils.materialize_session_image`) reads it through `TurnState.data_of`, which reads the turn state or `session[:monadic_state]` by how the app keeps it; a turn-state app never falls back to a session key a deleted turn left.
- `TurnState::Notes` (`lib/monadic/turn_state/notes.rb`) shows an app's state as a Markdown page on the work screen, `<chat folder>/notes/<title>.md`, for an app that declares it in a private `state_notes` (title, the value's key and fields to show with labels, collections with their name field and fields) and may add lines in a private `state_notes_extra(session)`. It is made from the state (each part with the turn of the message that changed it last, `by` in `TurnState.value` / `TurnState.items`), after a reply that changed the state (`html_handler`, shown on the work screen), when the chat is resumed or read from a file (`send_chat_to_page`) and after a deleted message (`message_editor`, refreshed where shown); with nothing left it is removed and taken off the work screen. The chat's folder is made for a page to show. While the page is there, the `state_notes` prompt rule names it to the model as a page to read, not to write. Each part begins with the `###### §` mark the work screen scrolls to. Novel Writer, Translate, Research Assistant, Math Tutor, Language Practice Plus, Voice Interpreter and the `session_context` group declare it.
- `monadic_log(collection:, entries:)` adds texts to a log: a collection an app only adds to for the user to read on its notes (Language Practice Plus's advice, Voice Interpreter's phrases), which its load tool does not return to the model. A text's id is made from the text (`TurnState.text_id`), so a text is added once.
- The `session_context` group (`lib/monadic/shared_tools/session_context.rb`, Chat Plus) keeps topics, people and notes as items of the collections of those names, a text's id made from the text; one tool call's changes are made together or not at all (`TurnState.change_all!`).

## What `monadic true` Changes

`features do monadic true end` sets `features[:monadic]`, which the app list sends to the UI and the session parameters carry as `monadic`.

| Where | Effect |
|---|---|
| UI (`utilities.js`, `ws-app-data-handlers.js`) | Monadic badge |

`monadic true` adds no tools; the app imports `session_context` or defines its own load and save tools.

## Speech From a Tool Parameter

`tts_target :tool_param, "<tool>", "<parameter>"` makes auto speech read the given parameter of the tool call (stored in `session[:tts_text]`) instead of the response text. Voice Interpreter and Language Practice Plus use it.

## Related Documentation

- `docs/advanced-topics/monadic-mode.md`
- `docs/advanced-topics/monadic_dsl.md`
