# Help System

The Monadic Chat Help app answers questions about Monadic Chat based on its documentation.

## Overview :id=overview

The documentation is converted into vectors by a multilingual embedding model that runs on your computer, and stored in Qdrant. No API key is needed to install the help data or to search it.

## Features :id=features

- **Local-only retrieval**: Both embedding inference and vector storage run on your machine; no provider API key is needed for help search
- **Multilingual**: Questions can be asked in English, Japanese and many other languages
- **Multi-chunk Retrieval**: Returns multiple relevant sections per result for comprehensive answers
- **Bundled data**: The help data is built from the documentation when Monadic Chat is packaged, and ships inside the Ruby image. It is installed when you choose to
- **Public content only**: The shipped database and the installation feature use public documentation only

## Requirements :id=requirements

- Running `monadic-chat-qdrant-container` (vector storage)
- Running `monadic-chat-embeddings-container` (embedding model)

Both containers start automatically with Monadic Chat. The chat model used to generate answers still requires its provider API key. Installing the help data and searching it do not require an API key.

## Usage :id=usage

### Accessing Help :id=accessing-help

1. Start Monadic Chat and ensure all containers are running
2. Select "Monadic Chat Help" from the app menu
3. Install the bundled data from the **Help Data** panel in the sidebar. The same panel opens from **Monadic Chat Info → Help Data**, which works without an API key
4. Once installation is complete, ask questions about Monadic Chat in any language

Help search is opt-in: starting or rebuilding Monadic Chat does not install or replace the help data. The panel shows the installation status and progress.

When the bundled data is newer than the installed data, the panel offers an update. Use its update button to replace the installed help data; the installed help stays searchable until the replacement begins. When the version of the installed data cannot be verified, the panel asks you to reinstall.

The install, update, reinstall, and retry buttons start their operation without a confirmation dialog. Help search is unavailable during replacement. **Knowledge Base and conversation library data are preserved.** If installation fails, check the displayed reason and use the panel to try again.

### Common Questions :id=common-questions

- "How do I generate graphs?" → Will suggest Math Tutor or Mermaid Grapher apps
- "How can I work with PDFs?" → Will explain how to import the PDF into the Knowledge Base
- "What voice features are available?" → Will describe Voice Chat and speech synthesis options

## Building the Help Database :id=building-help-database

The help data ships with each release, so users do not build it. Developers regenerate it with:

```bash
# Build the help database from docs/* (this is what ships)
rake help:build

# Rebuild from scratch (deletes existing dump first)
rake help:rebuild

# Show statistics for the current dump
rake help:stats

# Print the path of the database dump
rake help:export

# Developers only: also index docs_dev/*. The resulting dump is rejected
# by packaging and the help data installer.
rake help:build_internal
```

The build pipeline starts the embeddings container if it is not already running, processes documentation files, and writes a JSON dump to `docker/services/ruby/help_data/help_db.json`. This dump is baked into the Ruby Docker image at build time.

## Architecture :id=architecture

### Storage :id=storage

Help data is stored locally in Qdrant, separately from Knowledge Base and conversation library data. The index covers both complete documents and their text fragments so searches can return relevant sections. Updating help data replaces only the help index.

### Build-Time Pipeline :id=build-time-pipeline

1. **Documentation processing**:
   - `rake help:build` runs `scripts/utilities/process_documentation.rb`
   - The script chunks each markdown file (default 3000 chars per chunk, 500 chars of overlap)
   - Hierarchical heading paths are preserved with each fragment

2. **Embedding generation**:
   - Each chunk is sent to the embeddings container as a "passage"
   - The service adds the `passage:` prefix the model expects and returns L2-normalized 768-dimensional vectors
   - Each document also gets a vector that is the mean of its items' vectors

3. **JSON dump output**:
   - The processed data is written to `docker/services/ruby/help_data/help_db.json`
   - The Ruby Docker image bakes the dump in at build time

### Runtime Pipeline :id=runtime-pipeline

1. **Installation**:
   - The user starts installation from the **Help Data** panel
   - Monadic Chat checks the bundled data, replaces the previous help index, and verifies the result
   - Search becomes available after installation completes; later starts use the installed data
   - Newer bundled data is offered as an update and is installed only when the user chooses to

2. **Search**:
   - User questions are embedded with the `query:` prefix using the same model
   - Qdrant returns the most similar items via HNSW search
   - The Help app groups results by document and presents the most relevant chunks

## Configuration Variables :id=configuration-variables

These variables are read from `~/monadic/config/env`.

Used by the Help app:

- `HELP_CHUNKS_PER_RESULT`: Chunks returned per search result (default: 3)
- `HELP_DATA_DUMP`: The JSON dump used by the installation (default: `/monadic/help_data/help_db.json` inside the Ruby container). Changing the path does not install the data, and a path in the shared folder is ignored

Used only when building the help data with `rake help:build`:

- `HELP_CHUNK_SIZE`: Characters per chunk (default: 3000). Larger chunks give more context per result and less precise matches
- `HELP_OVERLAP_SIZE`: Characters shared by adjacent chunks (default: 500)

Example:
```
HELP_CHUNKS_PER_RESULT=5
```

## Development :id=development

### Adding Documentation :id=adding-documentation

1. Add or modify markdown files in the `docs/` directory
2. Run `rake help:build` to regenerate the JSON dump
3. Rebuild and recreate the Ruby container so it uses the new dump
4. Open the **Help Data** panel and install or update the help data

Rebuilding alone does not change the running help database. Internal notes under `docs_dev/` are excluded from the shipped database. `rake help:build_internal` generates a development dump, but both packaging and the help data installer reject internal content, including when `DEBUG_MODE=true`.

### Processing Details :id=processing-details

- **Section parsing**: Markdown headings up to four levels deep are tracked, and chunks carry their hierarchical heading path
- **Language filtering**: When processing English docs, files under `/ja/`, `/zh/`, `/ko/` are excluded so each language is built separately
- **Internal docs**: `docs_dev/*.md` is included only by `rake help:build_internal`. `rake help:build` passes `--public-only`, which wins over `DEBUG_MODE` so a developer environment cannot leak internal docs into a release dump

## Performance Notes :id=performance-notes

### Chunk Size Guidelines :id=chunk-size-guidelines

These apply when building the help data with `HELP_CHUNK_SIZE`:

- **Technical documentation**: Use larger chunks (4000-5000) to preserve code examples
- **FAQ / short content**: Use smaller chunks (2000-3000) for precise matching
- **General content**: Default (3000) works well for most cases

### Search Quality :id=search-quality

- Increase `HELP_CHUNKS_PER_RESULT` if answers seem incomplete
- Ask with specific terms for better matches

## Limitations :id=limitations

- The chat model used to answer questions still requires its provider API key; installation and search require no API key
- Search quality differs between languages

## Troubleshooting :id=troubleshooting

### Common Issues :id=common-issues

1. **Help search is unavailable or returns no results**
   - Check the status in the **Help Data** panel and install or reinstall if it asks you to
   - Wait for an active installation to finish; if it fails, check the displayed reason and try again
   - Verify both containers are running: `docker ps | grep -E 'qdrant|embeddings'`

2. **Poor search results**
   - Install an available help data update
   - Check whether the documentation has enough detail to answer the question
   - For documentation developers, adjust chunk size, regenerate the dump with `rake help:rebuild`, and follow [Adding Documentation](#adding-documentation) to install it

3. **Build fails with "embeddings_service did not become ready"**
   - Verify that the embeddings image was built: `docker images | grep monadic-embeddings`
   - Inspect container logs: `docker logs monadic-chat-embeddings-container`
   - Wait for the model to finish loading before retrying the build

4. **The Help Data panel asks for an action**
   - Open the **Help Data** panel
   - Install if no data is installed, update when offered, or reinstall if the previous version cannot be verified
   - Restarting or rebuilding the container does not replace the help data; use the panel's action
