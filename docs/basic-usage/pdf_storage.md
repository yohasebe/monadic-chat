# PDF Storage Modes

Monadic Chat offers two ways to store and search through PDF documents: Local PDF (using a local Qdrant + multilingual-e5-base stack) and Cloud PDF (using OpenAI Vector Store). This flexibility lets you choose between full local control and cloud-hosted convenience.

## Understanding Storage Modes

### Local PDF (Qdrant + multilingual-e5-base)

The local storage mode processes PDFs entirely on your machine. Embeddings are computed by a local sentence-transformer container and stored in a Qdrant vector database — no external API key is required for either step.

- PDFs are converted to text embeddings locally using `multilingual-e5-base`
- All processing happens on your computer
- Vectors and metadata are persisted in the Qdrant Docker volume
- Works offline and requires no provider API key for storage or retrieval
- Recommended when you want full local control of your documents

### Cloud PDF (OpenAI Vector Store)

The cloud storage mode uploads your PDFs to OpenAI's servers and uses their Vector Store service for searching:

- PDFs are uploaded to OpenAI Files
- Documents are attached to a shared Vector Store
- OpenAI handles all indexing and search operations
- Recommended for zero-setup convenience and when you're already using OpenAI services

## Choosing Your Storage Mode

You can select your preferred storage mode in the Settings panel under "PDF Storage Mode":

- **Local** — Default option, stores everything locally
- **Cloud (OpenAI Vector Store)** — Uses OpenAI's hosted service

## Managing Your PDF Collections

### PDF Database Panel

The PDF Database panel in the web interface shows your document collections with a consistent interface for both local and cloud storage:

- **Refresh**: Update the list to show recently added documents
- **Delete (per-item)**: Remove individual PDFs with confirmation
- **Clear All**: Remove all PDFs with confirmation

When you upload a PDF to cloud storage, the list automatically refreshes to show the new document.

## How Searching Works

The search experience differs slightly between storage modes:

**Local Mode**:
- Uses Qdrant's HNSW index over locally-computed embeddings
- Search happens entirely on your machine
- No external API calls for embedding queries or retrieval

**Cloud Mode**:
- Automatically integrates OpenAI File Search into API calls
- Search is handled by OpenAI's Vector Store service
- Results come from OpenAI's servers

## Important Notes

### Cloud Mode Considerations

When using cloud storage, keep in mind:

- **Data Location**: PDFs are stored in your OpenAI account
- **Cost**: For OpenAI Vector Store pricing, refer to [OpenAI API Pricing](https://openai.com/api/pricing/)

### Local Mode Considerations

When using local storage:

- **Data Persistence**: Documents are stored in the `monadic-chat-qdrant-data` Docker volume
- **Backup**: Use the Export Document DB feature from the Electron menu to back up your data as a `.tar.gz` snapshot
- **Container Rebuilds**: Export your database before rebuilding containers to prevent data loss

### Upgrading from earlier versions

If you are upgrading from 1.0.0-beta.14 or earlier, the previous storage format is incompatible with the current local stack:

- Existing locally-stored PDFs do not migrate automatically
- Re-import your PDFs after upgrading to populate the Qdrant collections
- The legacy `monadic-chat-pgvector-data` Docker volume can be removed once re-import is complete

## Deletion Behavior

### Per-File Deletion
- **Local**: Removes the document and its chunks from the Qdrant collections
- **Cloud**: Deletes the file from OpenAI Files and removes it from the Vector Store

### Clear All
- **Local**: Removes all documents and chunks scoped to the current app from the Qdrant collections
- **Cloud**: Removes all attached files from the Vector Store

?> After clearing all files from a Vector Store, searches will return no results because the search corpus is empty.
