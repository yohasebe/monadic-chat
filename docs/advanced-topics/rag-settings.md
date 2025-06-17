# RAG (Retrieval-Augmented Generation) Settings

Monadic Chat provides several configuration variables to configure chunk sizes and search behavior for both PDF Navigator and Help System. These settings should be defined in the `~/monadic/config/env` file.

## PDF Navigator Settings

### Chunk Size Configuration

- **`PDF_RAG_TOKENS`**: Number of tokens per chunk (default: 4000)
  - Controls how PDF text is split into chunks for embedding
  - Larger values provide more context but may reduce search precision
  - Recommended range: 2000-6000 tokens

- **`PDF_RAG_OVERLAP_LINES`**: Number of lines to overlap between chunks (default: 4)
  - Provides continuity between adjacent chunks
  - Helps prevent context loss at chunk boundaries
  - Recommended range: 2-10 lines

Example configuration in `~/monadic/config/env`:
```
PDF_RAG_TOKENS=5000
PDF_RAG_OVERLAP_LINES=6
```

## Help System Settings

### Documentation Processing

- **`HELP_CHUNK_SIZE`**: Character count per chunk (default: 3000)
  - Controls how documentation is split during processing
  - Larger values preserve more context
  - Recommended range: 2000-5000 characters

- **`HELP_OVERLAP_SIZE`**: Character overlap between chunks (default: 500)
  - Maintains context continuity
  - Recommended: 15-20% of chunk size

- **`HELP_EMBEDDINGS_BATCH_SIZE`**: Batch size for embedding API calls (default: 50, max: 2048)
  - Larger batches are more efficient but may timeout
  - Adjust based on your API limits

### Search Configuration

- **`HELP_CHUNKS_PER_RESULT`**: Number of chunks returned per document (default: 3)
  - More chunks provide better context
  - Affects response quality and completeness
  - Recommended range: 3-5 chunks

Example configuration in `~/monadic/config/env`:
```
HELP_CHUNK_SIZE=4000
HELP_OVERLAP_SIZE=800
HELP_EMBEDDINGS_BATCH_SIZE=100
HELP_CHUNKS_PER_RESULT=5
```

## Optimization Tips

1. **For Technical Documentation**: Use larger chunk sizes (4000-5000) to preserve code examples and detailed explanations

2. **For FAQ/Short Content**: Use smaller chunk sizes (2000-3000) for more precise matching

3. **API Performance**: If you experience timeouts, reduce `HELP_EMBEDDINGS_BATCH_SIZE`

4. **Search Quality**: Increase `HELP_CHUNKS_PER_RESULT` if answers seem incomplete

## Rebuilding After Changes

After changing these settings, rebuild the affected databases:

```bash
# For Help System
rake help:rebuild

# For PDF Navigator (re-import PDFs through the UI)
```