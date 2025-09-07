Title: PDF Storage Modes (Local/Cloud)

Overview
- Monadic Chat supports two storage modes for PDF ingestion:
  - Local PDF (PGVector): PDFs are converted to text embeddings and stored in the local PGVector database.
  - Cloud PDF (OpenAI): PDFs are uploaded to OpenAI Files and attached to a shared Vector Store for File Search.

Choosing a mode
- Set the global mode from the Settings panel: PDF Storage Mode
  - Local (PGVector) – recommended when you want full local control.
  - Cloud (OpenAI Vector Store) – recommended for a hosted, zero‑setup index.
- The default is configured via `PDF_STORAGE_MODE` (`local` or `cloud`).
  - For backward compatibility, `PDF_DEFAULT_STORAGE` is still honored if `PDF_STORAGE_MODE` is not set.

Lists and actions
- The PDF Database panel shows both local and cloud lists with a consistent UI.
- Each list supports Refresh, per‑item delete（with confirmation）, and Clear All（with confirmation）.
- Cloud list refreshes automatically after a successful cloud import.

Searching
- Local mode uses the built‑in PGVector similarity search.
- Cloud mode automatically injects OpenAI File Search into Responses API calls.

Environment variables
- `PDF_STORAGE_MODE` – `local` (default) or `cloud`.
- `PDF_DEFAULT_STORAGE` – legacy fallback when `PDF_STORAGE_MODE` is not set.
- `OPENAI_VECTOR_STORE_ID` – reuse an existing Vector Store. If not set, one is created at first import and hinted in logs.

Notes
- Cloud mode stores PDFs in your OpenAI account. Use the same project in the UI and API key for consistency.
- Local mode persists inside the PGVector volume; export/backup is available from the Electron menu.

Registry
- App‑scoped registry lives at `~/monadic/data/document_store_registry.json` (atomic writes). Tracks Vector Store id and imported files.

Costs (Cloud)
- OpenAI Vector Stores are billed by storage size and time (GB per day). Keeping a Vector Store with attached files may incur cost. An empty store (no attached files) is effectively zero usage.

Deletion policy (Cloud)
- Per‑file delete removes the file from the Vector Store and deletes it from Files. The file’s vectors are no longer searchable.
- Clear All:
  - If `OPENAI_VECTOR_STORE_ID` is set: the Vector Store container is kept, but all attached files are removed (search corpus becomes empty).
  - If not set: the Vector Store itself is deleted.
- FAQ: “Files removed, store remains — can I still search?” No. If a Vector Store has no attached files, search returns no matches.
