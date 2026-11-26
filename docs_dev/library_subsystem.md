# Library Subsystem

The Library is the store behind the Knowledge Base. Saved conversations and imported files go into Qdrant, embedded by the embeddings service (the model set by `MODEL_NAME` in `docker/services/embeddings/server.py`, 768 dimensions, cosine distance). The code is in `lib/monadic/library/`.

Front ends:

- **Library tab** of the side column (`public/js/monadic/library-panel.js`): the list, Import file, Keep this conversation, open on the work screen, open the original chat, the Conversation Viewer, rename and delete, over the WebSocket messages in `lib/monadic/utils/websocket/library_handler.rb` and the HTTP import route.
- **`library_search` shared tool** (`lib/monadic/shared_tools/library_search.rb`): retrieval from inside a chat turn.
- **MCP server** (`lib/monadic/mcp/conduit.rb`): search, list and import for MCP clients; see [MCP Server](#mcp-server).

## Collections

Defined in `Monadic::VectorStore::Schema` (`lib/monadic/vector_store/schema.rb`). Each has one named vector, `content`.

| Collection | Contents |
|---|---|
| `library_summaries` | One point per entry. The vector embeds the first 1,500 characters of the first two turns (or the title when there are no turns) |
| `library_turns` | One point per turn |
| `library_messages` | Created with the others; nothing writes to it |

Point ids are random UUIDs. `conversation_id` in the payload links an entry's summary and turns. `Store#upsert_points` rejects a point without `conversation_id` or `scope_app`. Payload indexes are listed in `Monadic::VectorStore::Schema::DEFINITIONS` (`conversation_id` and `scope_app` on every Library collection). `Store#bootstrap_collections!` (through `VectorStore::Bootstrap`) creates a missing collection with them and, once per process, adds them to a collection that already exists. `QdrantBackend#collection_exists?` reports a collection missing only on 404; any other failure raises `BackendError`.

### Summary Payload

`conversation_id`, `scope_app`, `content_type` (default `conversation`), `source`, `language`, `title`, `license`, `topics`, `duration_seconds`, `participants_count`, `messages_count`, `turns_count`, `created_at`, `original` (a kept file), `source_chat_id` (a conversation record: the chat it was made from; indexed), `revision` (a new value on every write and rename: the version a choice was made on), plus `messages` and `participants` for the Conversation Viewer. When the JSON of `messages` exceeds 1,000,000 bytes, `messages` is left out and `messages_skipped_reason` is set.

### Turn Payload

`conversation_id`, `scope_app`, `turn_idx`, `speaker_id`, `speaker_role`, `text`, `start_message_id`, `end_message_id`, `start_offset_seconds`, `end_offset_seconds`, `message_count`.

## One Shelf

Every read (`library_search`, `library_list`, the Knowledge Base UI, MCP) sees every entry. `Hierarchical.ingest` writes `scope_app` = `Global` on every point; entries of earlier versions may carry an app's class name there. Nothing filters on it.

## Ingestion

All paths end in `Monadic::Library::Hierarchical.ingest(conversation, store:, original:)`, which segments the conversation into turns, embeds the summary text and the turns as passages, and upserts them. The input is a `monadic-conversation` v1 hash (`schema/monadic-conversation-v1.json`, validator `Monadic::Library::Schema`).

### Turn Segmentation

`Monadic::Library::TurnSegmenter`:

- One speaker (documents, monologues): each message is a turn.
- Several speakers: consecutive messages by the same speaker form one turn.

### File Importers

`Monadic::Library::FileImporter.build_conversation(path:, filename:, options:)` chooses by extension:

| Extension | Importer | Text comes from | `content_type` | `source` |
|---|---|---|---|---|
| `md`, `markdown`, `mdx` | `Importers::Markdown` | the file | `markdown` | `markdown:<file>` |
| `pdf` | `Importers::Pdf` | the extractor service, otherwise `library_pdf_extractor.py` | `pdf` | `pdf:<file>` |
| `docx`, `xlsx`, `pptx` | `Importers::Office` | `library_office_extractor.py` | `document` | `office:<file>` |
| code extensions and names known to `Importers::Code` | `Importers::Code` | the file | `code` | `code:<file>` |

Other extensions raise `UnsupportedFormatError`. Markdown, PDF and Office text is split at H1–H3 headings (or at paragraphs), code at the language's definition boundaries; any block over 4,000 characters is then split at blank lines. Each block becomes one message of a single `document` speaker (role `narrator`).

The two Python extractors are in the Python image at `/monadic/scripts/utilities/` (source `docker/services/python/scripts/utilities/`) and run with `docker exec monadic-chat-python-container python <script> <path>`. The host path under the shared folder is translated to `/monadic/data/...`.

PDFs go to the extractor service (`/v1/extract`, layout analysis and OCR) when `EXTRACTOR_SERVICE=true` and its health check passes at that moment. Otherwise the pdfplumber extractor in the Python container is used; if `EXTRACTOR_SERVICE=true` but the service is down, a warning is reported through `DegradationNotifier`.

### Import Route

`POST /library/import` (`lib/monadic/routes/library_import_routes.rb`), form fields `libraryFile`, `libraryTitle`, `libraryLicense`:

1. Rejects the upload when its size cannot be read or exceeds `LIBRARY_IMPORT_MAX_BYTES` (default 100 MiB).
2. Writes it to `<data>/library/imports/<epoch>_<hex>_<filename>`. The worker thread deletes the file when the import ends, whether it succeeds or fails (`ensure`); a failure before the worker starts deletes it in the route.
3. Registers an `ImportTracker` entry and returns `202` with `import_id` and `status_url`.
4. A background thread runs `Manager.import_file` (`FileImporter.build_conversation`, then `Hierarchical.ingest` with the kept original; see [Originals](#originals)). A Python extractor that runs past `FileImporter::EXTRACT_TIMEOUT` (600 s, as long as the extractor service is given) is stopped and the import ends in `error`.

`Hierarchical.ingest` writes the summary, then the turns. When a step fails after some points were written, it deletes those points by id and raises; if that deletion fails too, it is logged and the points stay. A summary is readable before its turns are written.

`GET /library/import/status/:id` returns the stage: `queued` → `extracting` → `embedding_storing` → `done` or `error`. `ImportTracker` is in memory; finished entries are removed one hour after they finish. The panel polls from 800 ms up to 5 s between requests and gives up after 30 minutes.

## Originals

A file imported through `Manager.import_file` (the import route and the MCP `path` input) is kept by `Monadic::Library::Originals` (`lib/monadic/library/originals.rb`) in `<library_path>/originals/<sha256>` (`Environment.library_path`: `/monadic/library` in the container, `~/monadic/library` on the host; folder 0700, files 0600). Only the Ruby service mounts it (`docker/services/ruby/compose.yml`); `monadic.sh` `ensure_state_dir` creates it. The same bytes are kept once.

- `keep(path)` writes the file beside its target, checks the SHA-256, renames it into place, and holds it for the import; a kept file of that name with other bytes raises `Changed`. `release` ends the hold.
- The summary point carries `original`: `sha256`, `filename`, `extension`, `bytes`. Text imports and saved conversations have none.
- `remove_if_unused(sha256) { count }` removes the file only when no import holds it and the count (`Store#original_refs`, summaries whose `original.sha256` matches) is 0; a count that fails keeps it. Keep, release and remove_if_unused run under one lock.
- An import that fails removes its file the same way; `Manager.delete_conversation` reads the entry's `original` (`Store#original_of`), deletes the entry, then calls `remove_if_unused`.
- `read(sha256)` returns the bytes after checking them: `Missing` when the file is gone or is a link, `Changed` when the bytes differ.

The working copy in `<data>/library/imports/` is separate: the route deletes it when the import ends.

## From the Work Screen

- `LIBRARY_FROM_WORKBENCH` (`handle_ws_library_from_workbench`) takes `item_id`, `sha256` and, for a conversation record, `choice`: `Monadic::Library::DeskImport.start` reads the item's bytes at that version (`Board#file_read`), writes them to `<data>/library/imports/`, and runs `Manager.import_file` in a thread; the reply gives `import_id` and `status_url` (`ImportTracker`, as for an upload; `updated` and `leftover` for an update). Refused for a chat that hides words (`hides_words`), a tab that is not live (`not_allowed`), a name `FileImporter.importable?` refuses (`not_importable`), a file over `FileImporter::MAX_BYTES` (`too_large`), or another version (`changed`). The work screen offers it for items whose `library` flag (`Board#public_file`) is set.
- `LIBRARY_CONVERSATION_DRAFT` (`handle_ws_library_conversation_draft`, not replayed): `Monadic::Library::ConversationDraft.put` writes the chat as a Markdown document (`ConversationRecord.of`: title, app, model, date, each user and assistant turn under `## User` / `## Assistant` with its own headings set to H4 and under, files named only, what a reply read from the Library) into the chat's `workbench/` folder and adds it to the board as a file item with `draft: { 'source_chat_id' }` (kept on the item when the file is edited; `public_file` says `draft: true`); the file is deleted again when the board does not take it. The chat, app and messages are the session's. The page hides the button for an app whose `library_save` is false (`body:not(.app-cap-kb-save)` in `monadic.css`). Refused for a chat that hides words, a tab that is not live, a chat with nothing said (`empty`), or an app whose `library_save` is false (`not_saved_by_app`, `ConversationDraft.app_allows?`).
- A draft item kept in the Library (`DeskImport`): the page asks for its title first (`#libraryKeepChoice`, its first heading offered) and sends `title`. Refused for an app whose `library_save` is false (the session's app at that time), and while a keep of the same chat runs (`in_progress`); options `title` (the user's, at most 200 characters, else the first `# ` line of the bytes kept, else the file name), `content_type: conversation`, `source: monadic-chat`, `source_chat_id` (the item's, never the page's). When `Store#records_from_chat` finds records of that chat and no `choice` is given, `DeskImport::Choose` replies `error: choose` with the records (id, title, `created_at`, newest first); the page asks to update one, keep this one besides (`choice: 'new'`), or cancel. `choice: { update, seen }` updates that record only while its `revision` is still `seen` (`record_changed`, `record_missing` otherwise), through `Manager.replace_file`, which checks the revision again under the entry's lock (`Manager.with_entry`, also taken by a rename and a delete; `Manager::Changed`, reported as `record_changed`): written under the same id, then the earlier version's points deleted by id (`leftover` when that fails) and its kept file removed unless another entry has it. A failed import leaves the earlier version.

## On the Work Screen

An entry opened from the Library tab (`WORKBENCH_OPEN_LIBRARY` → `Workbench::Channel.open_library`) is a board item of kind `library` (`Board#add_library`; the same entry at the same version is selected again, not added). `Monadic::Library::EntryText.shown` decides what it shows: a kept PDF as it is (`preview: 'pdf'`, `source: 'original'`, version = the file's SHA-256), a kept Markdown or code file as its text (`preview: 'text'`, `source: 'original'`), anything else as the entry's text (`EntryText.of`: each part, under `[User]` / `[Assistant]` for a conversation; `source: 'text'`, version = the SHA-256 of that text; an Office original is named in `original` with its `content_type`). `EntryText.bytes_for(record)` reads it now at that version only: for `original`, while the entry is in the Library and its summary still names that file (`Store#original_of`), then `Originals.read`; for `text`, the entry's text.

- `Board#public_item` describes it with `kind: 'library'`, its `preview`, `version` and `sha256`; the observation names it by kind `library` and takes what is in view by its preview (lines, or a PDF's page).
- `AssetServer#serve_library` serves it (view tokens only): a PDF as `application/pdf`, text as a text file is shown, keeping its line count (`note_text`); 409 and the item marked `changed` when it is not that version, 410 and `missing` when the entry or its file is gone, 415 when the entry did not keep its whole text.
- `Look` reads it (`library_seen`) at the item's version only: a PDF as a PDF file is read (`Pdf.visible`, `Pdf.whole`, or the file where the model takes PDFs), text as a text file is, and an Office entry's kept file as it is for the whole where the model takes it (`native_library_document`).
- File-only operations (drawing, edits, pointing, keeping in the Library) do not take it: the item has no `file`.

## List

`LIBRARY_LIST` returns every entry (`Manager.list_conversations(limit: nil)`: the summaries' `ROW_FIELDS` only, all pages read, newest first, the same date ordered by id) and `total`. A record whose chat is still in the history (`History::Store#resumable?`) carries `source_chat_id` and `source_chat_resumable`; the tab's row then offers to open that chat (`HistoryPanel.resume`). Other messages: `LIBRARY_GET_CONVERSATION`, `LIBRARY_RENAME` (title, at most 200 characters), `LIBRARY_DELETE`.

## App Capabilities

`MonadicDSL.finalize_capabilities!` sets `library_save` and `library_search` for every app:

- Default: both true.
- MDSL `features` can set them to false. `library_search true` with `library_save false` is a configuration error.

Apps with `library_search` true get the `library_search` tool group (`visibility: "conditional"`) unless they import it themselves.

## Retrieval

### Setting

`Monadic::Library::InChats` (`lib/monadic/library/in_chats.rb`) reads `CONFIG['LIBRARY_IN_CHATS']` (Settings, General, Sources the AI can use; on unless `"false"`, read at server start). There is no per-chat switch; a `library_rag_enabled` parameter a session still carries is ignored.

`on?` is the only check, and it asks nothing of the Library (it is asked whenever a prompt or a tool list is built, which sends nothing). `ProgressiveToolManager.visible_tools` offers the group (`library_search`, `library_list`) exactly while it holds, whether the app imports it as conditional (the default) or always visible; the group is left out of the skill menu and cannot be unlocked with `request_tool`. `LibrarySearch.session_enabled?` and Live's `available?` use it too; while it is off, `library_search` and `library_list` return `DISABLED_MESSAGE`. An empty Library is said by the tools: `library_list` returns that it is empty.

### System Prompt

The `library_rag` rule in `SystemPromptInjector` (priority 70) applies while `InChats.on?` holds and the app's `library_search` is true. It adds `LIBRARY_PROMPT`: that the Library exists, to consult it only when asked, when the user refers to what they keep, or when it clearly helps, that `library_list` lists it, and to keep the `[Title](mc:read:<id>)` links. What the Library holds is not listed in the prompt.

### `library_list`

`library_list(page:)` returns `LibrarySearch.list_text`: every entry from `Manager.list_conversations(limit: nil)` (newest first), `LIST_PAGE` (30) per page, each as its title, `content_type`, `source` and date, with the total and the page count.

### `library_search`

`library_search(query:, top_n: 3, content_type: nil, source: nil, session:)`:

1. Refuses (`NO_RECORD_MESSAGE`) without a `workbench:` (Workbench::Caller): what is read is recorded and shown, so a reply with no chat reads nothing.
2. Runs `Retriever.cascade_search` with `top_n` clamped to 1–10 and a filter on `content_type` / `source` when given.
3. Records the search (`Monadic::Library::Readings.add`, before anything is returned; a search that cannot be recorded returns `NO_RECORD_MESSAGE`) and puts its excerpts on the work screen as `library-<reading id>.md` in the chat's `workbench/` folder (`Workbench::Put`).
4. Formats the hits: title link `[Title](mc:read:<excerpt id>)`, source, speaker role, turn, score, and up to 480 characters of text.

In a chat with a word table, the result is hidden with the rest of the request when it is sent (`hide_words_in_request!`).

The tool group counts as available when the embeddings service answers its health check.

### Readings

`Monadic::Library::Readings` (`lib/monadic/library/readings.rb`) holds a reply's searches by `request_id`: `id` (`r_` + 16 hex), `query`, `at`, `path` (the copy on the work screen), `excerpts` (`id` `x_` + 16 hex, `conversation_id`, `title`, `source`, `turn`, `text` as the model was given it) and `cited`. The reply's message takes them as `library_readings` (`seal`, which marks as `cited` the excerpts its text links to by `mc:read:<id>`); a reply that ends without its message puts them on the user's message of the request (`library_readings_without_reply`). History (`History::Serializer`), import (`session_routes`) and the shared export (`PRIVACY_EXPORT_MESSAGE_KEYS`, every string masked) keep them through `Readings.clean`. The page draws them under the message (`Workbench.drawReadings`) and opens an excerpt's copy from an `mc:read:` link; when the copy is gone (the open of that path is refused), changed, or there was none, the excerpt is shown as recorded (`libraryPanel.showExcerpt`); a link with no record says the passage is no longer available.

### Cascade Search

`Monadic::Library::Retriever.cascade_search`:

1. Embeds the query (`embed_query`).
2. Searches `library_summaries` with the extra filter, top 20.
3. For each summary hit, searches `library_turns` for that `conversation_id`, top 3. The extra filter is not applied here because turns do not carry `source` or `content_type`.
4. Sorts all turn hits by score and returns the top `top_n`, each with the entry's title, source and language.

The frontend opens the Conversation Viewer when an `mc:conv:` link is clicked.

## MCP Server

The MCP server's `monadic_search_kb`, `monadic_list_kb` and `monadic_import_kb` (`lib/monadic/mcp/conduit.rb`) use the same store: search through `Retriever.cascade_search`, the list through `Manager.list_conversations`, and import through `Importers::Markdown` and `Manager.import_conversation` (text) or `Manager.import_file` (a file in the shared folder). The chat tools ground their answer in the Knowledge Base when `knowledge_base` is given (any value).

## Files

```
lib/monadic/library/
  store.rb             # Qdrant facade: collections, filters, delete_conversation
  manager.rb           # list / details / stats / rename / delete / import
  importers.rb         # conversation importer registry
  importers/           # one module per format
  file_importer.rb     # extension dispatch, Python extractors, extractor service
  import_tracker.rb    # in-memory status of file imports
  turn_segmenter.rb
  hierarchical.rb      # embed + upsert
  retriever.rb         # cascade_search
  in_chats.rb          # the setting: may the AI consult the Library in chats
  conversation_draft.rb # a chat's record put on its work screen
  desk_import.rb       # a document of the work screen kept
  schema.rb, version.rb
lib/monadic/vector_store/schema.rb
lib/monadic/embeddings/client.rb
lib/monadic/routes/library_import_routes.rb
lib/monadic/shared_tools/library_search.rb
lib/monadic/utils/websocket/library_handler.rb
lib/monadic/utils/system_prompt_injector.rb
public/js/monadic/library-panel.js
schema/monadic-conversation-v1.json
docker/services/python/scripts/utilities/library_pdf_extractor.py
docker/services/python/scripts/utilities/library_office_extractor.py

spec/unit/library/
spec/unit/shared_tools/library_search_spec.rb
spec/unit/utils/websocket/library_handler_spec.rb
spec/integration/library_import_contract_spec.rb
test/frontend/library-panel.test.js
```
