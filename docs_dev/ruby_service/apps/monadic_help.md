# Monadic Help System

The Monadic Help system provides intelligent documentation search and assistance for Monadic Chat users.

## Architecture

- **Storage**: Qdrant collections (`help_docs` for document-level entries, `help_items` for chunk-level entries) running in the `qdrant_service` container.
- **Embeddings**: `intfloat/multilingual-e5-base` (768-dim, L2-normalised) served by the `embeddings_service` container. No external API key is required.
- **Build pipeline**: `rake help:build` chunks Markdown files under `docs/` (and `docs_dev/` when called with `--include-internal`) and writes a JSON dump to `docker/services/ruby/help_data/help_db.json`. The dump is baked into the Ruby image; on first start, `Monadic::Help::DumpLoader` imports it into Qdrant.

## Features

- **Multi-chunk search results**: Returns multiple chunks per document for better context. Configurable via `HELP_CHUNKS_PER_RESULT` (default: 3).
- **English-only corpus**: The build script skips `/ja`, `/zh`, `/ko` paths under `docs/`. The LLM handles translation to the user's preferred language at query time, which keeps the index small without sacrificing reach.

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `HELP_CHUNK_SIZE` | Characters per Markdown chunk during build | `3000` |
| `HELP_OVERLAP_SIZE` | Character overlap between consecutive chunks | `500` |
| `HELP_CHUNKS_PER_RESULT` | Chunks returned per document at query time | `3` |
| `HELP_DATA_DUMP` | Path to the prebuilt JSON dump (overrides image default) | `/monadic/help_data/help_db.json` |
| `EMBEDDINGS_URL` | Override the embeddings service base URL | (resolved by `Monadic::Embeddings::Endpoint`) |
| `QDRANT_URL` | Override the Qdrant base URL | (resolved by `Monadic::VectorStore::Endpoint`) |

## Building the help database

```bash
# Build dump from docs/* + docs_dev/* (full rebuild every time)
rake help:build

# Drop the existing dump first, then build
rake help:rebuild

# Show dump statistics (file path, embedding model, point counts per collection)
rake help:stats
```

The build script always processes the full corpus — there is no incremental skip path. Local CPU embedding of ~150 documents (~2,500 chunks) takes well under a minute on Apple Silicon, so the simplification is intentional.

## Search APIs (Ruby)

- `HelpEmbeddings#find_closest_text(query, top_n:, include_internal:)` — single-chunk hits.
- `HelpEmbeddings#find_closest_text_multi(query, chunks_per_result:, top_n:, include_internal:)` — grouped by document so a single doc cannot flood the result list.
- `HelpEmbeddings#find_closest_doc(query, top_n:, language:)` — document-level hits.
- `HelpEmbeddings#search(query:, num_results:)` — MCP-friendly format with `title` / `content` / `metadata` / `distance`.
