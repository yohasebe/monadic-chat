# Library / Knowledge Base subsystem

This is an internal-developer document describing the architecture and
design decisions behind the Library subsystem. It complements
`docs_dev/qdrant_embeddings_migration.md` (the migration that produced
the Qdrant + multilingual-e5-base storage layer) and the user-facing
description in `docs/basic-usage/basic-apps.md` (Knowledge Base section).

## What it is

The Library is the project-wide knowledge base: every Monadic Chat app
shares the same store. Conversation transcripts (saved chat sessions),
imported PDFs / Office documents / Markdown / source code all flow
through one ingestion pipeline and end up in two Qdrant collections:

- `library_summaries` — one vector per conversation (whole-conversation
  summary text).
- `library_turns` — one vector per turn (a "turn" is a contiguous run
  of messages by the same speaker; for non-conversation imports, each
  chunk becomes a synthetic turn).

The cascade retriever queries summaries first, then expands the top
matches into their turn-level passages. This keeps recall high without
forcing the LLM to read every turn during ranking.

## Data model

Schema is `monadic-conversation` v1, validated by
`Monadic::Library::Schema`. The on-disk shape (in Qdrant payload) for a
summary point looks like:

```json
{
  "conversation_id": "uuid",
  "content_type": "conversation | pdf | document | code | markdown",
  "title": "...",
  "source": "monadic-chat | imported file | ...",
  "language": "en | ja | ...",
  "scope_app": "ChatOpenAI | KnowledgeBaseClaude | ... | Global",
  "license": null,
  "messages_count": 0,
  "turns_count": 0,
  "created_at": "2026-04-30T12:00:00Z",
  "updated_at": "2026-04-30T12:00:00Z"
}
```

Turn points carry `conversation_id`, `turn_idx`, `speaker_role`,
`start_message_id`, `text`, and the same `scope_app`.

### Why `scope_app` instead of a separate visibility flag

The earlier design used `personal` / `shareable` strings as a binary
visibility flag. That model did not survive contact with reality:

- "Personal" had no scoping semantics — everything went into one global
  pool that the user had to navigate by hand.
- Cross-app retrieval was all-or-nothing. There was no way to say
  "this entry should be retrievable from any Chat app, but not from
  AutoForge or Code Interpreter".

The current design replaces that with a single `scope_app` field whose
value is either:

- A literal app class name (e.g. `ChatOpenAI`, `JupyterNotebookGrok`).
  The entry is only retrievable when the same app+provider combination
  is the active app.
- The literal sentinel `Global`. The entry is retrievable from every
  app via `library_search`.

The retriever then composes a Qdrant filter: `scope_app IN
[current_app, "Global"]`. This neatly expresses both "private to this
app" and "shareable knowledge artifact" without needing a separate
visibility column.

Importantly, **provider variants are separate scopes**. `ChatOpenAI`
cannot see entries saved while `ChatClaude` was active. That is by
design: the user picked a provider for a reason, and silently mixing
prior context from a different provider would be a surprise. Users who
want cross-provider sharing flip the entry to `Global`.

## Ingestion pipeline

`Monadic::Library::Manager.import_from_text` is the single entry point
for both saved chat sessions and file imports. The flow is:

1. **Parse + detect importer** (`Monadic::Library::Importers.detect`) —
   inspects the input and dispatches to one of `MonadicChatExport`,
   `ChatML`, `AnthropicMessages`, `GeminiContents`, `PlainText`,
   `Markdown`, `PDF`, `Office`, `Code`. Each importer normalises into a
   `monadic-conversation` v1 hash with `conversation_id`, `messages`,
   `participants`, and metadata.
2. **Turn segmentation** (`Monadic::Library::TurnSegmenter`) — collapses
   consecutive same-speaker messages into a single turn. For documents
   (PDF/Office/etc.) the importer has already chunked the content, so
   each chunk maps to one synthetic turn.
3. **Hierarchical embed + upsert** (`Monadic::Library::Hierarchical.ingest`)
   — embeds the conversation summary and each turn via
   `Monadic::Embeddings::Client` (the local e5-base model), then upserts
   point batches into `library_summaries` and `library_turns`.

Each Qdrant point id is a freshly-generated UUID. The `conversation_id`
in the payload (not the point id) is what links summaries to their
turns and lets the retriever expand a top-summary hit into its passages.

### File importers

PDF and Office extraction run **inside the Python container**, not the
Ruby container. This is because the pdfplumber / python-docx /
openpyxl / python-pptx stack is heavy and we did not want to drag it
into the Ruby image. The Ruby side calls `lib/monadic/library/file_importer.rb`
which `docker exec`s into the Python container with the uploaded file
as input. Output is a structured JSON the Markdown importer then
ingests.

The extractor scripts live in the Python image
(`docker/services/python/scripts/library_pdf_extractor.py` and
`library_office_extractor.py`) — they are **baked into the image**, not
mounted from the host shared volume, so a `docker rm` on the Python
container drops them. Release builds rebuild the Python image to pick
up changes.

### File-import HTTP route is asynchronous (since beta.16)

`POST /library/import` previously ran the entire pipeline (write-to-disk
→ extract → embed → Qdrant upsert) inside the Falcon worker that
picked up the request. Image-only PDFs that took the heavy extractor
+ RapidOCR path could occupy a worker for several minutes, queueing
every other HTTP/WS request behind one upload.

The route now writes the upload to disk, validates size, registers an
`ImportTracker` entry, and returns **202 Accepted** with `{ import_id,
status_url }` — then hands the heavy work off to a `Thread.new`. A
companion endpoint, `GET /library/import/status/:id`, surfaces the
worker's current stage (`queued` → `extracting` → `embedding_storing`
→ `done` / `error`).

Rationale for `Thread.new` (not `Async::Task`): the inner pipeline is
synchronous I/O against the extractor service / embeddings server /
Qdrant client, so fiber scheduling buys nothing. `Thread.new` releases
the request handler immediately and the worker block runs in parallel
with subsequent requests.

The frontend (`library-panel.js#uploadLibraryFile`) polls the status
endpoint with exponential backoff (800ms → 5s, 30 min hard cap) and
renders per-stage progress text in the same alert. New i18n keys:
`libImportStageQueued`, `libImportStageExtracting`,
`libImportStageEmbedding` (translated across all 7 supported
languages).

`ImportTracker` is in-process and ephemeral — restart loses status
entries, but in-flight imports complete in seconds-to-minutes so this
rarely matters; the import itself is committed to Qdrant regardless of
whether the tracker entry survives. Entries auto-purge after 1 hour
once they reach a terminal state, to bound memory under forgotten
polls.

Specs:
- `spec/unit/library/import_tracker_spec.rb` — UUID shape, snapshot
  isolation (callers cannot mutate tracker state), TTL purging
  semantics, concurrent-write tolerance.
- `spec/integration/library_import_contract_spec.rb` — POST returns
  202 with the right envelope, worker dispatches through
  `FileImporter` + `Manager` exactly once, status endpoint returns
  the right shape, oversized rejection short-circuits before the
  worker is set up, error path lands `stage='error'` with the
  exception message.

## Retrieval

`Monadic::Library::Retriever#cascade_search` is the only path used by
runtime callers (`library_search` shared tool, the Knowledge Base app's
inventory display). It executes:

1. **Summary pass**: filter by `scope_app IN [current_app, "Global"]`,
   embed the query with the same e5-base model used for ingestion, run
   a `query_points` against `library_summaries`, take the top-N.
2. **Turn expansion**: for each summary hit, filter
   `library_turns` to `conversation_id == hit.conversation_id` and
   re-rank within that conversation against the same query embedding.
   Aggregate the top turns across all summary hits.
3. **Format**: the consumer (`library_search.format_results`) renders
   the final string with markdown citation links of the form
   `[Title](mc:conv:<conversation_id>)`. The frontend intercepts clicks
   on the `mc:conv:` scheme and opens the Conversation Viewer modal.

The cascade design (summary → turn) was chosen over flat turn-level
search because turns have a much narrower context window than summaries
and tend to score noisily for thematic queries. Searching summaries
first is the LLM-equivalent of "find the right book before reading
pages."

### `library_search` shared tool

`MonadicSharedTools::LibrarySearch::Tools#library_search` is the
bridge between an MDSL-driven app and the retriever. Apps opt in via
`imported_tool_groups [:library_search]`. The tool is gated three
ways:

1. The Library subsystem must be reachable (`Embeddings.health` returns
   true).
2. The user has flipped the per-session RAG toggle ON in the Knowledge
   Base sidebar (default OFF, locks on first message).
3. The session carries an `app_name` parameter so the cascade has a
   scope to filter on.

When all three are satisfied, the tool runs the retriever and returns
a formatted citation block.

#### Privacy Filter integration

If `Privacy Filter` is also active in the same session, the formatted
result is **masked through the same session-level Privacy Pipeline**
that masks user-role messages, *before* it returns to the tool
dispatcher (`MonadicSharedTools::LibrarySearch.apply_privacy`). This
closes a back-channel: Knowledge Base content is stored unmasked
(deliberately — the user saw and approved that text on screen), so a
naive retrieval path would have the LLM seeing PII even though the
session's Privacy Filter was meant to prevent that. By masking
*tool-result text*, not just user-role messages, we make the Privacy
Filter symmetric with respect to all PII that flows into the LLM.

The pipeline registers any new entities into the same per-session
registry, so when the LLM later references them in its reply (via the
expected `<<TYPE_N>>` placeholder), the streaming-handler restoration
pass swaps them back to the original values for display.

## Save: defense-in-depth gates

The frontend hides or disables the Save button via CSS / JS when the
active app cannot legally save (Privacy Filter active, app declares
`library_save: false`, etc.). A stale browser tab or a programmatic
WebSocket client could still send `LIBRARY_SAVE`, so `library_handler.rb`
also enforces these gates server-side **before any storage side-effect**.
Two parallel checks run at the top of `handle_ws_library_save`:

1. **Privacy Filter active in this session** — when
   `session[:_privacy_pipeline]` is present (set by the Privacy Filter
   middleware on the LLM request path), the save is rejected with
   `"Knowledge Base save is disabled while the Privacy Filter is
   active. Use Privacy Export to retain this conversation."`. This
   guards against masked PII being inadvertently restored and persisted
   to the KB.
2. **App declares `library_save: false`** — when
   `MonadicApp.app_settings(app_name).settings[:library_save]` is
   `false` (artifact apps like AutoForge / Drawio Grapher / Image
   Generator that explicitly opt out via MDSL, *and* Privacy-Filter
   apps where `finalize_capabilities!` derives the same value), the
   save is rejected with
   `"Knowledge Base save is not supported for #{app_name}. Switch to
   a conversational app to save."`. This catches programmatic clients
   that bypass the frontend entirely.

Either rejection sends `library_saved` with `res: 'failure'` and a
human-readable `content` field, and `return`s before any storage
operation. Both paths are pinned by specs in
`spec/unit/utils/websocket/library_handler_spec.rb`.

## Save flow (chat session → KB)

The `LIBRARY_SAVE` WS message handler (`library_handler.rb`) is where
"Save the current conversation" lands. It receives:

- `messages`: the visible-to-user chat history (already restored from
  any Privacy Filter masking).
- `parameters`: the active app's session params (notably `app_name`,
  used as the default `scope_app`).
- `scope_app`: optional override. UI sends `Global` when the user picked
  the "Global" radio; omitted otherwise.
- `conversation_id`: optional. If present, this is a **re-save** of an
  already-stored conversation.

### Re-save semantics: delete-then-ingest

The first save creates a new entry with a fresh `conversation_id`.
The frontend remembers that id (`state.currentConversationId` in
`library-panel.js`) for the lifetime of the session. The next Save
click sends the same id back. The handler then performs:

1. `store.delete_conversation(existing_id)` — removes all summary +
   turn points carrying that `conversation_id`.
2. `Manager.import_from_text(options: {conversation_id: existing_id, ...})`
   — re-ingests with the exact same id reused (importers honour
   `options[:conversation_id]`).

This is delete-then-ingest, not incremental update. It is simpler than
trying to figure out which turns are new vs changed, and the cost is
acceptable because saves are user-driven (not real-time). Atomicity
relies on the assumption that delete + ingest happen quickly; a crash
in between leaves the KB without that conversation, which is a worse
outcome than a duplicate but still recoverable (the user can save
again).

The id-reuse property is important for `mc:conv:<id>` markdown links
that the LLM has already emitted in earlier conversations — those links
keep working after a re-save instead of dangling.

The frontend clears the sticky id on:

- Reset session (`SessionState.on('session:reset', ...)`)
- Start new session (`SessionState.on('session:new', ...)`)
- App switch (`SessionState.on('app:changed', ...)`)
- Browse-modal delete of the matching entry

After any of these, the next Save creates a new entry with a fresh id.

## LLM-suggested titles

`Monadic::Library::TitleSuggester` provides a best-effort default for
the Save modal's title field. It is invoked once per first save, when
the title field is blank.

### Why the active provider's LLM, not a hardcoded model

We piggy-back on whichever provider the user is currently chatting
with:

1. **API key is guaranteed** — the user is already exchanging messages
   with that provider, so the key works.
2. **Cost is bounded** — the prompt is short (≤ 4 user/assistant turns
   capped at 240 chars each), and the response is ≤ 60 chars. A single
   call is cheap on every supported provider's flagship model.
3. **No vendor matrix to maintain** — each vendor helper already exposes
   `send_query` with a uniform contract.

The implementation derives the provider from the session's `app_name` →
the `APPS` global → `app.settings['group']`, mapped to a canonical
provider key (`openai`, `anthropic`, `gemini`, `xai`, `cohere`,
`mistral`, `deepseek`, `ollama`). It then locates a
"Chat" app instance for that provider (mirroring the pattern used by
`AIUserAgent#find_chat_app_for_provider`) and calls `send_query` with
a small prompt asking for "a concise descriptive title".

### Failure handling

The suggester is best-effort. Any failure (provider not detected, API
key missing, LLM error, parse error) returns nil, and the WS handler
sends `{res: 'failure'}`. The frontend reacts by clearing the spinner
and the placeholder; the title field stays blank and the user types
their own. We deliberately do not surface error messages — a missing
title suggestion is not worth pulling the user's attention.

### Caching

The frontend caches the suggestion against the conversation length
(`state.cachedTitleSuggestion` + `cachedTitleSuggestionMessageCount`).
If the user opens the modal, gets a suggestion, cancels, and re-opens
the modal without sending any new chat turns, the cached value is
reused — no second LLM call. The cache is invalidated when the
conversation grows (new user/assistant turns) or when
`clearCurrentConversation` fires.

## Why these choices

A few decisions that were not obvious at the start:

- **Two collections (summaries + turns) instead of one** — gave the
  cascade retriever and is what makes `library_search` recall good
  enough on long conversations.
- **Per-app + Global scoping instead of per-app folders** — folders
  would have forced the user to know about hierarchy at save time.
  `Global` as a sentinel means the same payload can act as either
  shareable or app-only without restructuring storage.
- **Delete-then-ingest for re-saves** — simpler than diff-based
  updates, and rare enough (user-clicked) that the cost is acceptable.
- **Active-provider LLM for title suggestion** — avoids a vendor matrix
  and inherits the user's existing API key configuration.
- **Tool-result masking for Privacy Filter** — keeps the Privacy
  Filter contract honest without forcing the Knowledge Base to store
  pre-masked text (which would hurt retrieval recall).

## Files map

```
lib/monadic/library.rb                       # Subsystem entry point (requires)
lib/monadic/library/version.rb               # FORMAT_VERSION constant
lib/monadic/library/schema.rb                # JSON Schema validation
lib/monadic/library/store.rb                 # Qdrant facade (collections, scope_filter, delete_conversation)
lib/monadic/library/importers/               # Per-format ingestion entry points
lib/monadic/library/turn_segmenter.rb        # Same-speaker collapse
lib/monadic/library/hierarchical.rb          # Embed + upsert pipeline
lib/monadic/library/retriever.rb             # cascade_search (summary → turn)
lib/monadic/library/manager.rb               # High-level facade (import / list / details / rename / scope)
lib/monadic/library/inventory.rb             # Stats + summary listing for the sidebar
lib/monadic/library/file_importer.rb         # docker exec dispatch into Python extractors
lib/monadic/library/title_suggester.rb       # Active-provider LLM call for first-save titles

lib/monadic/shared_tools/library_search.rb   # The library_search shared tool
lib/monadic/utils/websocket/library_handler.rb # WS message handlers (LIBRARY_LIST/SAVE/DELETE/RENAME/SET_SCOPE/RAG_TOGGLE/SUGGEST_TITLE etc.)
lib/monadic/utils/system_prompt_injector.rb  # build_library_rag_prompt + library_inventory_block

public/js/monadic/library-panel.js           # Frontend: state, modal, sticky id, suggestion, cache, RAG toggle
public/js/monadic/websocket.js               # Routes library_* responses to libraryPanel handlers
views/index.erb                              # Modals: librarySaveModal / libraryBrowseModal / libraryViewerModal

docker/services/python/scripts/
  library_pdf_extractor.py                   # PDF text extraction (pdfplumber)
  library_office_extractor.py                # Office text extraction (python-docx / openpyxl / python-pptx)

spec/unit/library/                           # Schema / Store / Hierarchical / Retriever / Manager / Inventory / TitleSuggester
spec/unit/shared_tools/library_search_spec.rb
spec/unit/utils/websocket/library_handler_spec.rb
test/frontend/library-panel.test.js
```
