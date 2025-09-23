Title: PDF Storage Integration (Local PGVector and OpenAI Vector Store)

Overview
- This document describes how Local and Cloud PDF storage are wired end‑to‑end, the relevant endpoints, and UI behavior.

Local (PGVector)
- Endpoint: `POST /pdf` – extract → split → embeddings → PGVector.
- Listing: WebSocket message `PDF_TITLES` → `pdf_titles` payload.
- Delete: `DELETE_PDF` (single) and `DELETE_ALL_PDFS` (clear).

Cloud (OpenAI)
- Upload: `POST /openai/pdf?action=upload` → Files API (purpose: assistants) → Vector Store add.
- Listing: `GET /openai/pdf?action=list` → returns files; enriches each entry via `/v1/files/{id}` to include `filename`.
- Delete: `DELETE /openai/pdf?action=delete&file_id=...` (single), `DELETE /openai/pdf?action=clear` (all).
- Reuse: `OPENAI_VECTOR_STORE_ID` (ENV) if present; otherwise a fallback meta JSON is used/created in `data/`.
 - Deletion behavior:
   - Single delete: detach file from Vector Store, then delete from Files (vectors not searchable afterward).
   - Clear All: with `OPENAI_VECTOR_STORE_ID` → keep store, remove all files; without it → delete the store and clear meta.
 - Cost note: Vector Stores incur storage cost by size × time. An empty store has negligible cost; attached files contribute to usage.

Responses API (OpenAI)
- File Search is added when a Vector Store is configured and mode is `cloud`.
- Source of VS id (in order): session → app‑specific ENV → registry → global ENV → fallback JSON.
- If tools are present, reasoning is removed for compatibility where required.
- For PDF Navigator, a hint encourages using File Search; includes a compact metadata footer.
- Routing: `resolve_pdf_storage_mode(session)` selects `cloud|local` (session override > `PDF_STORAGE_MODE`/fallback > availability). In `cloud`, local DB tools are suppressed and `file_search` is injected.

UI specifics
- Settings panel: global "PDF Storage Mode" selector (Local/Cloud). `/api/pdf_storage_defaults` reflects the current setting.
- Import modal: no per‑upload storage toggle; ingestion respects the global mode.
- PDF Database panel: both lists share the same look & feel; Refresh/Clear All (with confirm) and per‑item delete.
- Cloud list auto‑refreshes after a successful cloud import.

Env defaults API
- `GET /api/pdf_storage_defaults` returns `{ default_storage, pgvector_available }` where `default_storage` is derived from `PDF_STORAGE_MODE` (or legacy `PDF_DEFAULT_STORAGE`).
- `GET /api/pdf_storage_status` returns `{ mode, vector_store_id, local_present, cloud_present }` (no `hybrid`).

Dynamic config refresh
- `Monadic::Utils::PdfStorageConfig.refresh_from_env` watches `~/monadic/config/env` and hot-reloads `PDF_STORAGE_MODE` / `PDF_DEFAULT_STORAGE` when the file timestamp changes.
- The helper trims blank values: removing a key from the env file immediately reverts to the default without restarting the backend.
- The refresh happens on the next API/UI poll (e.g., PDF imports, status widget). There is no polling daemon; the helper is invoked by request handlers so there is no added idle overhead.
- Use `Monadic::Utils::PdfStorageConfig.reset_tracking!` in specs to force a re-read when simulating env changes.

Styling
- Local/Cloud list rows use a unified “row card” style.
- Assistant messages wrap metadata under `.pdf-meta` for a compact footer.

Notes
- This integration assumes a single admin and a single OpenAI project.
- If you later fix a project id, consider adding an `OpenAI-Project` header.
- Search requires at least one file attached to the Vector Store; a store with zero files yields no matches.

Migration
- A safe, idempotent task migrates the legacy meta file `pdf_navigator_openai.json` into the new registry:
  - `rake vector_db:migrate_to_registry`
  - Scope: writes under app_key `default`. Extend as needed if you had multiple app scopes previously.

Performance Notes
- Request‑scoped caching: `resolve_pdf_storage_mode(session)` memoizes its decision per invocation context to avoid duplicate checks.
- Vector Store ID lookup: `resolve_openai_vs_id(session)` memoizes per session cache version to prevent repeated ENV/registry/meta scans.
- Fast local presence check: use `TextEmbeddings#any_docs?` (`SELECT 1 FROM docs LIMIT 1`) instead of listing all titles.
- Config lookup: `get_pdf_storage_mode` is memoized; invalid values fall back to `local`.
- Safety: all fast paths fall back to prior behavior on errors; no change to mode precedence or UI semantics.
