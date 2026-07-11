# Help System

Monadic Chat includes an AI-powered help system that provides contextual assistance based on the project's documentation.

## Overview :id=overview

The help system uses a local sentence-transformer model (`multilingual-e5-base`) to create a searchable knowledge base from the Monadic Chat documentation. Embeddings are computed locally and stored in Qdrant. No external API key is required to embed text or to search the knowledge base.

## Features :id=features

- **Local-only retrieval**: Both embedding inference and vector storage run on your machine; no provider API key is needed for help search
- **Multilingual**: `multilingual-e5-base` handles English, Japanese, and many other languages with comparable quality
- **Multi-chunk Retrieval**: Returns multiple relevant sections per result for comprehensive answers
- **Prebuilt JSON dump**: The help database is generated at packaging time and shipped inside the Ruby image, so it is searchable on first start
- **Internal docs toggle**: Internal documentation under `docs_dev/` is always included in the database, but it appears in search results only when `DEBUG_MODE=true`

## Requirements :id=requirements

- Running `monadic-chat-qdrant-container` (vector storage)
- Running `monadic-chat-embeddings-container` (multilingual-e5-base inference)

Both containers start automatically with Monadic Chat. The chat model used to generate answers (Claude, GPT, Gemini, etc.) still requires its own API key, but the search step itself does not.

## Usage :id=usage

### Accessing Help :id=accessing-help

1. Start Monadic Chat and ensure all containers are running
2. Select "Monadic Help" from the app menu
3. Ask questions about Monadic Chat in any language

### Common Questions :id=common-questions

- "How do I generate graphs?" → Will suggest Math Tutor or Mermaid Grapher apps
- "How can I work with PDFs?" → Will explain how to import the PDF into the Knowledge Base
- "What voice features are available?" → Will describe Voice Chat and speech synthesis options

## Building the Help Database :id=building-help-database

Most users do not need to build the database manually — it is shipped prebuilt with each release. Developers can regenerate it:

```bash
# Build help database from docs/* and docs_dev/*
rake help:build

# Rebuild from scratch (deletes existing dump first)
rake help:rebuild

# Show statistics for the current dump
rake help:stats

# Print the path of the database dump
rake help:export
```

The build pipeline starts the embeddings container if it is not already running, processes documentation files, and writes a JSON dump to `docker/services/ruby/help_data/help_db.json`. This dump is baked into the Ruby Docker image at build time.

## Architecture :id=architecture

### Storage :id=storage

The help system uses two Qdrant collections inside the shared `monadic-chat-qdrant-container`:

- **`help_docs`** — One point per documentation file. The vector is the average of its item embeddings, which lets the system rank entire documents by relevance.
  - Payload: `title`, `file_path`, `section`, `language`, `items` (count), `is_internal`, `metadata`

- **`help_items`** — One point per chunked text fragment.
  - Payload: `doc_id`, `text`, `position`, `heading`, `language`, `is_internal`, `metadata`

Both collections use 768-dimensional vectors with cosine distance and HNSW indexing.

### Build-Time Pipeline :id=build-time-pipeline

1. **Documentation processing**:
   - `rake help:build` runs `scripts/utilities/process_documentation.rb`
   - The script chunks each markdown file (default 3000 chars per chunk, 500 chars of overlap)
   - Hierarchical heading paths are preserved in payload metadata

2. **Embedding generation**:
   - Each chunk is sent to the embeddings container as a "passage"
   - The service applies the e5 `passage:` prefix and returns L2-normalized 768-dim vectors
   - Each document also gets a vector that is the mean of its items' vectors

3. **JSON dump output**:
   - The processed data is written to `docker/services/ruby/help_data/help_db.json`
   - A short fingerprint (`help_data/export_id.txt`) tracks the dump for build cache invalidation
   - The Ruby Docker image bakes the dump in at build time

### Runtime Pipeline :id=runtime-pipeline

1. **Bootstrap**:
   - On first start, Monadic Chat ensures the `help_docs` and `help_items` collections exist in Qdrant
   - If they are empty, `Monadic::Help::DumpLoader` reads the bundled JSON dump and bulk-imports it
   - Subsequent starts skip the import once the collections are populated

2. **Search**:
   - User questions are embedded with the `query:` prefix using the same model
   - Qdrant returns the most similar items via HNSW search
   - The Help app groups results by document and presents the most relevant chunks

## Configuration Variables :id=configuration-variables

The help system can be configured via environment variables in `~/monadic/config/env`:

- `HELP_CHUNK_SIZE`: Character count per chunk (default: 3000)
  - Larger chunks provide more context but may reduce search precision

- `HELP_OVERLAP_SIZE`: Characters to overlap between chunks (default: 500)
  - Provides continuity between adjacent chunks

- `HELP_CHUNKS_PER_RESULT`: Chunks returned per search result (default: 3)
  - Number of relevant chunks included in each search result

- `HELP_DATA_DUMP`: Override the path of the JSON dump (default: `/monadic/help_data/help_db.json` inside the Ruby container)

Example:
```
HELP_CHUNK_SIZE=4000
HELP_OVERLAP_SIZE=600
HELP_CHUNKS_PER_RESULT=5
```

## Development :id=development

### Adding Documentation :id=adding-documentation

1. Add or modify markdown files in the `docs/` directory (or `docs_dev/` for internal docs)
2. Run `rake help:build` to regenerate the JSON dump
3. Rebuild the Ruby container so the new dump is baked in

### Processing Details :id=processing-details

- **Section parsing**: Markdown headings up to four levels deep are tracked, and chunks carry their hierarchical heading path
- **Language filtering**: When processing English docs, files under `/ja/`, `/zh/`, `/ko/` are excluded so each language is built separately
- **Internal docs**: `docs_dev/*.md` is included only when `--include-internal` is passed (the default for `rake help:build`)

## Performance Notes :id=performance-notes

### Chunk Size Guidelines :id=chunk-size-guidelines

- **Technical documentation**: Use larger chunks (4000-5000) to preserve code examples
- **FAQ / short content**: Use smaller chunks (2000-3000) for precise matching
- **General content**: Default (3000) works well for most cases

### Search Quality :id=search-quality

- Increase `HELP_CHUNKS_PER_RESULT` if answers seem incomplete
- Adjust the `top_n` parameter in search calls for more results
- Use specific search terms for better matching

## Limitations :id=limitations

- The chat model used to answer questions still requires its own provider API key (Claude, GPT, etc.); only the search step is local
- Coverage and accuracy vary by language because each spaCy/sentence-transformer model is trained on a different corpus

## Troubleshooting :id=troubleshooting

### Common Issues :id=common-issues

1. **Help search returns no results**
   - Check that the JSON dump exists: `ls docker/services/ruby/help_data/help_db.json`
   - Verify both containers are running: `docker ps | grep -E 'qdrant|embeddings'`
   - Re-run `rake help:rebuild` to regenerate the dump

2. **Poor search results**
   - Increase chunk size for better context
   - Rebuild database with `rake help:rebuild`
   - Check whether the documentation has enough detail to answer the question

3. **Build fails with "embeddings_service did not become ready"**
   - Verify that the embeddings image was built: `docker images | grep monadic-embeddings`
   - Inspect container logs: `docker logs monadic-chat-embeddings-container`
   - The container may take 30-60 seconds on first start while loading the model

4. **Help collections are empty after upgrade**
   - The Ruby app loads the JSON dump only when the collections are empty
   - Manually clear collections via the Qdrant API and restart the Ruby container, or rebuild the container so the bundled dump is reloaded
