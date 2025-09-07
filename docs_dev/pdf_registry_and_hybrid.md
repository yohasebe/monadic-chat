Title: Vector DB – Registry and Dedup (Hybrid Removed)

Overview
- Objective (historical): unify Local (PGVector) and Cloud (OpenAI Vector Store) with app‑scoped storage.
- Note: Hybrid routing has been removed from the application. This document remains as historical reference.

Core Components
- Registry (data): `~/monadic/data/document_store_registry.json`
  - atomic write (tmp→rename)
  - per app: `cloud.vector_store_id`, `cloud.files[] (file_id, filename, hash, created_at)`
- Routing modes (current): `local | cloud` (hybrid removed)
  - Responses API file_search injected when mode = `cloud` and app has `pdf_vector_storage: true`
- Local tools: generic handlers in `MonadicApp` (find/list/get) with per‑app DB name `monadic_user_docs_<app_key>`

Endpoints
- `/openai/pdf?action=upload` — upload file, dedup by SHA256+size, attach to app VS, update registry
- `/openai/pdf?action=list` — list VS files; returns `vector_store_id`
- `/openai/pdf?action=delete|clear` — delete single/all; update registry accordingly
- `/api/pdf_storage_status` — returns mode, vs id, local/cloud presence

Prompt Note
- The prompt reflects the single configured source (local or cloud) and does not mention hybrid.

Cleanup (Electron)
- “Clean Up Cloud PDFs”: delete only monadic-* Vector Stores and app‑origin files (protects 3rd‑party usage).

Open Items
- Extend registry to local scope (namespaces migration), listing UI, and integration tests for dedup flows.
