# Monadic Help System

The Monadic Help system provides intelligent documentation search and assistance for Monadic Chat users.

## Features

1. **Batch Processing for Embeddings**
   - Processes multiple text chunks in batches for improved performance
   - Configurable batch size via `HELP_EMBEDDINGS_BATCH_SIZE` environment variable
   - Default batch size: 50 (max: 2048 per OpenAI limits)

2. **Multi-Chunk Search Results**
   - Returns multiple text chunks per document for better context
   - Configurable via `HELP_CHUNKS_PER_RESULT` environment variable
   - Default: 3 chunks per document
   - Results are grouped by document with average similarity scores

3. **Incremental Updates**
   - Uses MD5 hashing to detect changed documents
   - Only rebuilds embeddings for modified files
   - Stores content hash in document metadata
   - Significantly faster rebuilds when documentation hasn't changed

4. **English-Only Documentation**
   - Processes only English documentation files (excludes /ja, /zh, /ko directories)
   - LLM handles translation to user's preferred language
   - Reduces database size and processing time

## Configuration

### Environment Variables

- `HELP_EMBEDDINGS_BATCH_SIZE`: Number of texts to process in each embedding batch (default: 50)
- `HELP_CHUNKS_PER_RESULT`: Number of text chunks to return per document in search results (default: 3)
- `EMBEDDINGS_DEBUG`: Enable debug logging for embeddings processing

### Building the Help Database

```bash
# Initial build
rake help:build

# Full rebuild (drops existing data)
rake help:rebuild

# View statistics
rake help:stats
```

## Implementation Details

### Batch Processing
The system now uses OpenAI's batch embedding API to process multiple texts in a single request:
- Reduces API calls and improves performance
- Automatically handles batching with configurable size
- Maintains correct ordering of embeddings

### Search Improvements
- `find_help_topics`: Returns multiple chunks per document for comprehensive context
- `search_help_by_section`: Filters results by documentation section with multi-chunk support
- Results include average similarity scores for better ranking

### Incremental Updates
- Each document stores an MD5 hash of its content
- During rebuilds, only documents with changed hashes are reprocessed
- Timestamps track when documents were last updated

### Language Handling
- Documentation is stored only in English
- The LLM detects user language and translates responses accordingly
- Reduces storage requirements and simplifies maintenance