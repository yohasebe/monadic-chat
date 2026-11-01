# Monadic Chat Help

The Monadic Chat Help app (`apps/monadic_help/`, OpenAI) answers questions from the help database. Installing the database from the UI is described in `docs_dev/developer/help_system_internal.md`.

## Storage

- Qdrant collections `help_docs` (one point per document) and `help_items` (one point per chunk), defined in `VectorStore::Schema`.
- Embeddings from the embeddings service (`intfloat/multilingual-e5-base`); no API key is needed for search.
- The dump `docker/services/ruby/help_data/help_db.json` is baked into the Ruby image at `/monadic/help_data/help_db.json` (`HELP_DATA_DUMP` overrides the path). The user installs it into Qdrant from the UI (`POST /help/database/install`).

## Building the Dump

`scripts/utilities/process_documentation.rb`, run through Rake:

```bash
rake help:build           # docs/ only; this is what ships
rake help:rebuild         # delete the dump, then build
rake help:stats           # dump path, embedding model, points per collection
rake help:export          # print the dump path
rake help:build_internal  # also docs_dev/; never packaged
```

- Only files tracked by git are indexed; `docs/ja`, `docs/zh` and `docs/ko` are skipped.
- `HELP_CHUNK_SIZE` (3000 characters) and `HELP_OVERLAP_SIZE` (500) set the chunking.
- Every build processes the whole corpus.
- `scripts/help_dump_guard.rb` (`HelpDumpGuard`) refuses to package a dump with internal points.

## Tools

| Tool | What it does |
|---|---|
| `find_help_topics(text:, top_n: 10, chunks_per_result:)` | Chunk search grouped by document (`find_closest_text_multi`) |
| `get_help_document(doc_id:)` | All chunks of one document |
| `list_help_sections(language:)` | Document titles |
| `search_help_by_section(text:, section:, top_n: 3, chunks_per_result:)` | Search within one section |

`chunks_per_result` defaults to `ENV["HELP_CHUNKS_PER_RESULT"]` or 3. Internal documents are included only when `ENV["DEBUG_MODE"] == "true"`. The search methods are in `lib/monadic/utils/help_embeddings.rb` (`find_closest_text`, `find_closest_text_multi`, `find_closest_doc`, `search`).

## Endpoints

`EMBEDDINGS_URL` and `QDRANT_URL` override the service URLs (`Monadic::Embeddings::Endpoint`, `Monadic::VectorStore::Endpoint`).
