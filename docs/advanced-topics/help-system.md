# Help System

Monadic Chat includes an AI-powered help system that provides contextual assistance based on the project's documentation.

## Overview :id=overview

The help system uses OpenAI's embeddings to create a searchable knowledge base from the Monadic Chat documentation. This allows for intelligent, context-aware responses to user questions.

## Features :id=features

- **Automatic Language Detection**: The system responds in the user's language while storing only English documentation
- **Multi-chunk Retrieval**: Returns multiple relevant sections for comprehensive answers
- **Incremental Updates**: Only processes changed documentation files using MD5 hash tracking
- **Batch Processing**: Efficiently processes embeddings in batches for better performance
- **Automatic Container Rebuilding**: PGVector container automatically rebuilds when help data is updated

## Requirements :id=requirements

- OpenAI API key (for embeddings and chat functionality)
- Running pgvector container

## Usage :id=usage

### Accessing Help :id=accessing-help

1. Start Monadic Chat and ensure all containers are running
2. Select "Monadic Help" from the app menu
3. Ask questions about Monadic Chat in any language

### Common Questions :id=common-questions

- "How do I generate graphs?" → Will suggest Math Tutor or Mermaid Grapher apps
- "How can I work with PDFs?" → Will explain PDF Navigator app
- "What voice features are available?" → Will describe Voice Chat and speech synthesis options

## Building the Help Database :id=building-help-database

The help database is built from the documentation during development:

```bash
# Build help database (incremental update)
rake help:build

# Rebuild from scratch
rake help:rebuild

# View statistics
rake help:stats

# Export database for distribution
rake help:export
```

## Configuration :id=configuration

### Configuration Variables :id=configuration-variables

- **`HELP_CHUNK_SIZE`**: Character count per chunk (default: 3000)
  - Controls how documentation is split during processing
  - Larger values preserve more context

- **`HELP_OVERLAP_SIZE`**: Character overlap between chunks (default: 500)
  - Maintains context continuity between chunks
  - Recommended: 15-20% of chunk size

- **`HELP_EMBEDDINGS_BATCH_SIZE`**: Batch size for API calls (default: 50, max: 2048)
  - Larger batches are more efficient but may timeout
  - Adjust based on your API limits

- **`HELP_CHUNKS_PER_RESULT`**: Number of chunks returned per result (default: 3)
  - More chunks provide better context
  - Affects response quality and completeness

### Example Configuration :id=example-configuration

Add these settings to your `~/monadic/config/env` file:

```
HELP_CHUNK_SIZE=4000
HELP_OVERLAP_SIZE=800
HELP_EMBEDDINGS_BATCH_SIZE=100
HELP_CHUNKS_PER_RESULT=5
```

## Architecture :id=architecture

### Database Structure :id=database-structure

The help system uses a separate PostgreSQL database (`monadic_help`) with pgvector extension:

- **`help_docs`**: Stores document metadata and embeddings
  - title, file_path, section, language
  - Document-level embedding for initial filtering
  - Unique constraint on (file_path, language)

- **`help_items`**: Stores individual text chunks with embeddings
  - Text content, position, heading information
  - Chunk-level embeddings for detailed search
  - Links to parent document via foreign key

### Export/Import Process :id=export-import-process

1. **Development Phase**:
   - Documentation is processed using `rake help:build`
   - Embeddings are generated via OpenAI API
   - Database is automatically exported after build/rebuild

2. **Distribution**:
   - Export files are stored in `docker/services/pgvector/help_data/`
   - Files include: schema.sql, help_docs.json, help_items.json, metadata.json
   - Export ID tracks version for automatic rebuilding

3. **User Installation**:
   - PGVector container imports data on first run
   - Import script handles JSON to PostgreSQL conversion
   - Embeddings are restored from export files

### Automatic Container Rebuilding :id=automatic-container-rebuilding

The system tracks help database updates using an export ID:

1. When help database is rebuilt, a new export ID is generated
2. The ID is stored in `help_data/export_id.txt`
3. On startup, monadic.sh compares stored ID with container ID
4. If different, PGVector container is automatically rebuilt
5. New help data is imported during container initialization

## Development :id=development

### Adding Documentation :id=adding-documentation

1. Add or modify markdown files in the `docs/` directory
2. Run `rake help:build` to update the database
3. The system will only process changed files

### Processing Details :id=processing-details

- **Incremental Updates**: MD5 hashing detects changed documents
- **Batch Processing**: Embeddings processed in configurable batches
- **Multi-language**: Excludes `/ja/` and other language directories
- **Hierarchical Context**: Preserves heading structure in metadata

### Testing :id=testing

To test the help system:

```bash
# Clean rebuild
rake help:rebuild

# Check statistics
rake help:stats

# Test in app
# 1. Start server
# 2. Open Monadic Help
# 3. Test queries in different languages
```

### Debugging :id=debugging

Enable debug output:

```bash
export EMBEDDINGS_DEBUG=true
export HELP_EMBEDDINGS_DEBUG=1
rake help:build
```

## Performance Optimization :id=performance-optimization

### Chunk Size Guidelines :id=chunk-size-guidelines

- **Technical Documentation**: Use larger chunks (4000-5000) to preserve code examples
- **FAQ/Short Content**: Use smaller chunks (2000-3000) for precise matching
- **General Content**: Default (3000) works well for most cases

### API Performance :id=api-performance

- Reduce `HELP_EMBEDDINGS_BATCH_SIZE` if experiencing timeouts
- Monitor OpenAI API rate limits
- Consider processing during off-peak hours

### Search Quality :id=search-quality

- Increase `HELP_CHUNKS_PER_RESULT` if answers seem incomplete
- Adjust `top_n` parameter in search calls for more results
- Use specific search terms for better matching

## Limitations :id=limitations

- Requires OpenAI API key (no support for other embedding providers)
- English documentation only (responses are machine-translated)
- Maximum context limited by model constraints
- Embedding dimensions fixed at 3072 (OpenAI text-embedding-3-large)

## Troubleshooting :id=troubleshooting

### Common Issues :id=common-issues

1. **"Help database does not exist"**
   - Run `rake help:build` to create the database
   - Ensure pgvector container is running

2. **Poor search results**
   - Increase chunk size for better context
   - Rebuild database with `rake help:rebuild`
   - Check if documentation has sufficient detail

3. **Export failures**
   - Ensure pgvector container is running
   - Check disk space for export files
   - Verify database connection settings

4. **Import failures**
   - Check pgvector container logs
   - Ensure export files are valid JSON
   - Verify Python and psycopg2 are installed in container

5. **Path-related issues in packaged apps**
   - Help system scripts now use relative paths instead of hardcoded absolute paths
   - Scripts automatically detect the correct base directory
   - If import fails, check that export files exist in `docker/services/pgvector/help_data/`

6. **Help database not loading in new containers**
   - Symptom: Monadic Help app's function calling stops with no response
   - Check if data exists: `docker exec monadic-chat-pgvector-container psql -U postgres -d monadic_help -c "SELECT COUNT(*) FROM help_items"`
   - Common causes:
     - PostgreSQL init scripts fail during container initialization
     - Python psycopg2 cannot connect to localhost during startup
   - The system now uses a custom entrypoint script that ensures import runs after PostgreSQL is ready
   - If the automatic import still fails, the container will continue running and you can use the help:build rake task