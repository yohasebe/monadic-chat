# Qdrant + Embeddings Migration (1.0.0-beta.15)

This note captures the architectural decisions behind replacing the PGVector + OpenAI `text-embedding-3-large` stack with a local Qdrant + `multilingual-e5-base` pipeline. It is internal documentation aimed at future maintainers; user-facing docs live under `docs/`.

## Why migrate

Two persistent pain points drove the change:

1. **OpenAI API key required for help search.** The Monadic Help app and the local PDF KB both depended on `text-embedding-3-large`. A user with a Claude or Gemini key but no OpenAI key could not use the built-in help system. This contradicted the project's "provider independence" tenet.
2. **PGVector overhead disproportionate to scale.** Per-user Monadic Chat installations index at most ~10K-100K chunks. Running a full PostgreSQL just to hold that data — with a 3072-dim vector that exceeds PGVector's IVFFlat limit — meant we were paying a high operational cost (DDL, migrations, init scripts, separate volume) for very little of Postgres's actual capability.

The migration also unlocks two architectural improvements: lower-dimensional vectors (768) regain HNSW indexing, and the embedding pipeline becomes parallelizable / decoupled from the storage backend.

## Architectural decisions

### Two containers, single responsibility each

- **`monadic-chat-qdrant-container`**: storage only (Qdrant official image, ~80 MB)
- **`monadic-chat-embeddings-container`**: inference only (Python + sentence-transformers + e5-base baked in, ~2.5 GB)

We considered colocating the embedding model with Qdrant (similar to Weaviate's `text2vec-transformers` module). Rejected because (a) Qdrant is Rust and the model runtime is Python — combining them requires a supervisor, (b) it goes against Qdrant's recommended deployment pattern, (c) it conflates stateful storage with stateless inference at the lifecycle level. The Privacy Filter precedent (Phase 2 of the privacy-filter feature) established "stateless ML inference = its own container" as a project-wide pattern, and we follow it here.

### Both containers are base services, not opt-in

The Help system depends on both, so they always start with Monadic Chat. Privacy Filter remains opt-in because it adds ~1 GB and is genuinely optional; embeddings is "default-on" because help search would otherwise be broken out of the box.

The embeddings image is large (~2.5 GB) because the model is baked in at build time to avoid a 30-60 second cold start on first use. This is the one notable footprint cost of the migration.

### Single Ruby abstraction layer (`Monadic::VectorStore::Base`)

The Ruby code does not call Qdrant's HTTP API directly. Instead, callers use `Monadic::VectorStore::QdrantBackend`, which implements the abstract `Base` class. The interface intentionally exposes Qdrant concepts (named vectors, payload, filters) rather than masking them — the goal is a thin pass-through, not a portable abstraction. If we ever swap Qdrant for another backend, the adapter cost is paid in that backend's implementation, not on the caller side.

### Per-app PDF isolation via payload filter

The previous design gave each app its own PG database (e.g. `monadic_user_docs_pdfnavigatoropenai`). The new design uses two Qdrant collections (`pdf_docs`, `pdf_items`) with `app_key` in every point's payload, and queries always include an `app_key` filter. This:

- Replaces N databases (one per app) with two collections
- Preserves the privacy guarantee — every read/write path threads the filter
- Keeps a single HNSW index per collection, which scales better than per-database indexes

The risk is "developer forgets to add `app_key` filter and data leaks across apps." We mitigate this in `Monadic::Pdf::Store` by hard-coding the filter at construction time: every method on a Store instance automatically includes the right filter. App code cannot bypass it without going through `VectorStore` directly.

### Help DB as a JSON dump baked into the Ruby image

Build flow: `rake help:build` runs `process_documentation.rb`, which reads `docs/*.md`, embeds via the embeddings container, and writes `docker/services/ruby/help_data/help_db.json`. The Ruby Dockerfile copies that JSON into the image. On first start, `Monadic::Help::DumpLoader` reads the JSON and bulk-imports into Qdrant.

We considered alternatives:

- **Snapshot the live Qdrant during build.** Rejected because Qdrant snapshots are version-locked and would force us to fork the official image.
- **Embed at runtime on first start.** Rejected because users would wait 1-2 minutes on first launch while ~5,000 chunks are embedded.
- **Ship pre-embedded data alongside Qdrant volume.** Rejected because volume-level data is opaque and harder to version-control.

The JSON dump is portable, version-controlled, debuggable (`cat | jq`), and dimension-checked at load time so dimension changes between releases fail fast.

### `pgvector_available` JSON field name preserved

The `/api/pdf_storage_defaults` endpoint still returns `pgvector_available` despite the backend no longer being PGVector. This is for frontend protocol compatibility — `monadic.js` consumes that key. Renaming would require a coordinated change to `monadic.bundle.min.js`. We added a comment in `pdf_routes.rb` noting that the field name is historical and now means "is the local store available". A future cleanup can rename both sides together.

## Migration impact for existing users

- **Local PDF data is not automatically migrated.** Re-upload PDFs after upgrading. We surface a one-shot upgrade notice in `lib/monadic.rb` when the legacy `monadic-chat-pgvector-data` Docker volume is detected.
- **Help search works immediately after upgrade.** The Ruby image bakes in the help DB JSON dump.
- **Existing OpenAI key users are unaffected** for chat purposes — only the embedding/storage layer changed.

## Files of interest

| Concern | Location |
|---|---|
| Schema | `lib/monadic/vector_store/schema.rb` |
| Backend interface | `lib/monadic/vector_store/base.rb` |
| Qdrant adapter | `lib/monadic/vector_store/qdrant_backend.rb` |
| Embeddings client | `lib/monadic/embeddings/client.rb` |
| Help facade | `lib/monadic/utils/help_embeddings.rb` |
| Help bootstrap | `lib/monadic/utils/help_embeddings_loader.rb` |
| Help dump loader | `lib/monadic/help/dump_loader.rb` |
| PDF facade | `lib/monadic/pdf/store.rb` |
| Build script | `scripts/utilities/process_documentation.rb` |
| Embeddings server | `docker/services/embeddings/server.py` |

## Test coverage

- 101 unit specs (`spec/unit/vector_store`, `spec/unit/embeddings`, `spec/unit/help`, `spec/unit/pdf`, `spec/unit/utils/help_embeddings_spec.rb`, `spec/unit/utils/container_dependencies_spec.rb`)
- 5 integration smoke specs (`spec/integration/qdrant`, `spec/integration/embeddings`) — skip when Docker is not running

## Open follow-ups

- The `pgvector_available` field name (frontend protocol) — rename eventually
- Multi-language help DB build (currently English only; the model handles JA/ZH/etc. but the build script does not yet ingest `docs/ja/*`)
- `process_documentation.rb` does not yet support incremental rebuild via content hashes — full rebuild only
