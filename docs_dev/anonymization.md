# Anonymization (Word Tables)

Each chat may keep a word table: the words the user chose to hide, each with a type and a placeholder (`<<PERSON_1>>`). User documentation: `docs/advanced-topics/anonymization.md`.

## Pieces

| Piece | File | Role |
|---|---|---|
| `WordTable` | `lib/monadic/utils/privacy/word_table.rb` | The table: active words, words kept as they are, placeholder ids, revision; `to_h` / `from_h` with validation |
| `Words` | `lib/monadic/utils/privacy/words.rb` | The chat's table (`table`, `start!`, `marked?`), hiding (`hide_texts`, `snapshot`), putting back (`restore_reply`), speech (`spoken`), export masking (`masking`), import (`file_table`), candidates from the finder (`candidates`) |
| `Outbound` | `lib/monadic/utils/privacy/outbound.rb` | The last check of what is sent (`check_no_marked_words!`, `terms_of`), `chat_session!` (a missing or unreadable session is refused) |
| `EgressGuard` | `lib/monadic/utils/privacy/egress_guard.rb` | Checks every outbound HTTP request and WebSocket of a chat's work against its words |
| `ChatRequestScope` | `lib/monadic/workspace/chat_request_scope.rb` | Fixes the chat of a page's HTTP request from its `tab_id` before the body is read; runs a chat with a table in its `EgressGuard` scope, the response body included |
| Word-table handler | `lib/monadic/utils/websocket/word_table_handler.rb` | `WORDS_FIND` (asks the Privacy container for candidates) and `WORDS_CHANGE` (the user's decisions) |
| Page | `public/js/monadic/word-table.js` | The panel, the status, and holding a send until the user decides |

## Where Words Are Hidden

- Vendor helpers call `hide_words_in_request!` (`base_vendor_helper.rb`) on the request body; each attempt is sent inside `Words.sending`, which refuses when the table changed after the snapshot.
- Second opinions, Verify, AI User, context extraction and title suggestions hide their texts with one snapshot (`Words.hide_texts`) and put the answer back with it.
- Speech uses `Words.spoken` and checks the text as the TTS service would receive it.
- Tool arguments are restored only for the names in `Words::RESTORED_ARGUMENTS`.
- Live Conversation stays closed for a chat with a table (`sts_privacy_active?`).

## Keeping the Table

- The mark (`Words::MARK_KEY`) lives in the session; the table lives in memory (`Words::TABLES`) and in the chat's history row (`lib/monadic/history`). A chat whose mark has no readable table sends nothing.
- The connection's saved state keeps only the chat id, the app name and the mark (`WebSocketHelper.fetch_http_session_state`).
- Export (`privacy_handler.rb`): restored content carries `word_table`; masked content replaces the active words everywhere in the file and checks that none is left.
- Import (`session_routes.rb`): `Words.file_table` reads a native `word_table`, or converts a file's `registry` / `terms`.

## MDSL

`privacy do` is accepted and ignored with a warning (`MonadicDSL::SimplifiedAppDefinition#privacy`).
