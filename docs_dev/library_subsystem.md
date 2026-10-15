# Library Subsystem

The Library is the store behind the Knowledge Base. Saved conversations and imported files go into Qdrant, embedded by the embeddings service (the model set by `MODEL_NAME` in `docker/services/embeddings/server.py`, 768 dimensions, cosine distance). The code is in `lib/monadic/library/`.

Front ends:

- **Knowledge Base app** (`apps/knowledge_base/`, one MDSL per provider, tools in `knowledge_base_tools.rb`): list, search, details, stats, scope change, delete and text import through `Monadic::Library::Manager`.
- **Knowledge Base sidebar panel** (`public/js/monadic/library-panel.js`): Save, Browse, Import file, rename, scope, delete and the "Use Knowledge Base" toggle, over the WebSocket messages in `lib/monadic/utils/websocket/library_handler.rb` and the HTTP import route.
- **`library_search` shared tool** (`lib/monadic/shared_tools/library_search.rb`): retrieval from inside a chat turn.

The per-app PDF store (`pdf_docs` / `pdf_items`) is a separate store; see [Per-App PDF Store](#per-app-pdf-store).

## Collections

Defined in `Monadic::VectorStore::Schema` (`lib/monadic/vector_store/schema.rb`). Each has one named vector, `content`.

| Collection | Contents |
|---|---|
| `library_summaries` | One point per entry. The vector embeds the first 1,500 characters of the first two turns (or the title when there are no turns) |
| `library_turns` | One point per turn |
| `library_messages` | Created with the others; nothing writes to it |

Point ids are random UUIDs. `conversation_id` in the payload links an entry's summary and turns. `Store#upsert_points` rejects a point without `conversation_id` or `scope_app`.

### Summary Payload

`conversation_id`, `scope_app`, `content_type` (default `conversation`), `source`, `language`, `title`, `license`, `topics`, `duration_seconds`, `participants_count`, `messages_count`, `turns_count`, `created_at`, plus `messages` and `participants` for the Conversation Viewer. When the JSON of `messages` exceeds 1,000,000 bytes, `messages` is left out and `messages_skipped_reason` is set.

### Turn Payload

`conversation_id`, `scope_app`, `turn_idx`, `speaker_id`, `speaker_role`, `text`, `start_message_id`, `end_message_id`, `start_offset_seconds`, `end_offset_seconds`, `message_count`.

## Scope

Every entry has a `scope_app`: an app class name (e.g. `ChatOpenAI`) or `Global`.

- Retrieval (`library_search`, the RAG inventory) filters on `scope_app` ∈ {the requesting app's `app_name`, `Global`}. Provider variants are different apps.
- The Knowledge Base UI and the Knowledge Base app's list/details/stats see every entry.
- Defaults: Save uses the scope the UI sends, otherwise the current `app_name`, otherwise `Global`. File import uses `libraryScopeApp`, otherwise `Global`. `Manager.import_from_text` defaults to `Global`.
- `Manager.update_scope_app` rewrites `scope_app` on every point of the entry in all Library collections (scroll + upsert with vectors).

## Ingestion

All paths end in `Monadic::Library::Hierarchical.ingest(conversation, store:, scope_app:)`, which segments the conversation into turns, embeds the summary text and the turns as passages, and upserts them. The input is a `monadic-conversation` v1 hash (`schema/monadic-conversation-v1.json`, validator `Monadic::Library::Schema`).

### Turn Segmentation

`Monadic::Library::TurnSegmenter`:

- One speaker (documents, monologues): each message is a turn.
- Several speakers: consecutive messages by the same speaker form one turn.

### Conversation Importers

`Manager.import_from_text(store:, input:, options:, scope_app:)` parses a JSON string if possible and picks the first importer in `Importers::REGISTRY` whose `can_import?` accepts the input:

1. `MonadicChatExport` (`parameters` + `messages`; source `monadic-chat`)
2. `GeminiContents`
3. `AnthropicMessages`
4. `ChatML`
5. `PlainText` (source `plain-text`)

Importers accept `options[:conversation_id]`, `:title` and `:license`.

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

`POST /library/import` (`lib/monadic/routes/library_import_routes.rb`), form fields `libraryFile`, `libraryTitle`, `libraryLicense`, `libraryScopeApp`:

1. Rejects the upload when its size cannot be read or exceeds `LIBRARY_IMPORT_MAX_BYTES` (default 100 MiB).
2. Writes it to `<data>/library/imports/<epoch>_<hex>_<filename>`. The file stays there after the import.
3. Registers an `ImportTracker` entry and returns `202` with `import_id` and `status_url`.
4. A background thread runs `FileImporter.build_conversation` and `Manager.import_conversation`.

`GET /library/import/status/:id` returns the stage: `queued` → `extracting` → `embedding_storing` → `done` or `error`. `ImportTracker` is in memory; finished entries are removed one hour after they finish. The panel polls from 800 ms up to 5 s between requests and gives up after 30 minutes.

## Save

`LIBRARY_SAVE` (`handle_ws_library_save`) takes `messages`, `parameters`, `title`, `license`, `monadic_state`, `scope_app` and `conversation_id`. It refuses, before writing anything, when:

- the session has a Privacy pipeline or `_privacy_session_enabled`;
- `messages` is empty;
- the app in `parameters['app_name']` has `library_save: false`;
- `parameters` is missing.

`verify` fields are removed from the messages. When `conversation_id` is given, the existing points with that id are deleted and the conversation is ingested again under the same id, so `mc:conv:<id>` links keep working. The panel keeps the id until Reset, a new session, an app change, or deletion of that entry in Browse.

`LIBRARY_SUGGEST_TITLE` asks the current provider for a title (`Monadic::Library::TitleSuggester`): up to 4 user/assistant messages, 240 characters each, title at most 60 characters, sent through the session's Privacy pipeline when there is one. Any failure returns `res: failure` and the title field stays empty. The panel reuses a suggestion until the conversation grows.

Other messages: `LIBRARY_LIST`, `LIBRARY_STATS`, `LIBRARY_GET_CONVERSATION`, `LIBRARY_RENAME` (title, at most 200 characters), `LIBRARY_SET_SCOPE`, `LIBRARY_DELETE`, `LIBRARY_RAG_TOGGLE`, `LIBRARY_RAG_QUERY`.

## App Capabilities

`MonadicDSL.finalize_capabilities!` sets `library_save` and `library_search` for every app:

- Default: both true.
- MDSL `features` can set them to false. `library_search true` with `library_save false` is a configuration error.
- Apps with `privacy do; enabled true; end` get both false; declaring either as true is a configuration error.

Apps with `library_search` true get the `library_search` tool group (`visibility: "conditional"`) unless they import it themselves.

## Retrieval

### Session Toggle

The "Use Knowledge Base" toggle sets `session[:parameters]['library_rag_enabled']` (default off; only `true` or `"true"` counts as on). `ProgressiveToolManager.visible_tools` offers `library_search` exactly while the toggle is on, whether the app imports it as conditional (the default) or always visible; the group is left out of the skill menu and cannot be unlocked with `request_tool`. If it is called while the toggle is off, `library_search` returns a message telling the model to ask the user to turn it on.

### System Prompt

The `library_rag` rule in `SystemPromptInjector` (priority 70) applies when the toggle is on and the app's `library_search` is true. It adds:

- an instruction to call `library_search` before answering factual questions and to keep the `[Title](mc:conv:<id>)` links;
- an inventory of the entries the app can retrieve, counted by `source` and `content_type` (`Monadic::Library::Inventory`), left out when empty or unreachable;
- the optional `content_type` and `source` parameters.

### `library_search`

`library_search(query:, top_n: 3, content_type: nil, source: nil, session:)`:

1. Reads `app_name` from the session for the scope filter.
2. Runs `Retriever.cascade_search` with `top_n` clamped to 1–10 and a filter on `content_type` / `source` when given.
3. Checks each hit for words the user marked (`Privacy::Outbound`); a hit with a marked word withholds the whole result.
4. Formats the hits: title link `[Title](mc:conv:<id>)`, source, speaker role, turn, score, and up to 480 characters of text.
5. When the session has an enabled Privacy pipeline, masks the text through it. If masking fails, the result is withheld and the failure is reported.

The tool group counts as available when the embeddings service answers its health check.

### Cascade Search

`Monadic::Library::Retriever.cascade_search`:

1. Embeds the query (`embed_query`).
2. Searches `library_summaries` with the scope filter and the extra filter, top 20.
3. For each summary hit, searches `library_turns` for that `conversation_id` with the scope filter, top 3. The extra filter is not applied here because turns do not carry `source` or `content_type`.
4. Sorts all turn hits by score and returns the top `top_n`, each with the entry's title, source and language.

The frontend opens the Conversation Viewer when an `mc:conv:` link is clicked.

## Per-App PDF Store

`Monadic::Pdf::Store` (`lib/monadic/pdf/store.rb`) keeps PDFs uploaded through `POST /pdf` in `pdf_docs` (one point per document) and `pdf_items` (one point per chunk). Every query filters on the store's `app_key`:

- `POST /pdf` uses `pdf_app_key_for(appName or session)`: the app class's `APP_KEY` constant if defined, otherwise its class name in lower case; `global` without an app.
- PDF text is split by `PDF2Text` into 800-token chunks with 2 overlapping lines.
- Apps with `pdf_vector_storage true` get the tools `find_closest_text`, `find_closest_doc`, `list_titles`, `get_text_snippet` and `get_text_snippets`, which read the store for the app's class name.
- The MCP server's Knowledge Base tools read the store named by their `knowledge_base` argument (default `global`).

## Files

```
lib/monadic/library/
  store.rb             # Qdrant facade: collections, scope_filter, delete_conversation
  manager.rb           # list / details / stats / rename / scope / delete / import
  importers.rb         # conversation importer registry
  importers/           # one module per format
  file_importer.rb     # extension dispatch, Python extractors, extractor service
  import_tracker.rb    # in-memory status of file imports
  turn_segmenter.rb
  hierarchical.rb      # embed + upsert
  retriever.rb         # cascade_search
  inventory.rb         # counts by source / content_type
  title_suggester.rb
  schema.rb, version.rb
lib/monadic/vector_store/schema.rb
lib/monadic/embeddings/client.rb
lib/monadic/pdf/store.rb
lib/monadic/routes/library_import_routes.rb
lib/monadic/routes/pdf_routes.rb
lib/monadic/shared_tools/library_search.rb
lib/monadic/utils/websocket/library_handler.rb
lib/monadic/utils/system_prompt_injector.rb
apps/knowledge_base/
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
