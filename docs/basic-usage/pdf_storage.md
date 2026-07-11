# PDF Database

The PDF Database gives selected apps a local store of PDFs that AI agents can search during conversations. Documents are processed entirely on your machine: text is extracted from each PDF, converted to embeddings by a local sentence-transformer container, and stored in a Qdrant vector database. No external API key is required for either step.

?> **PDF Database vs. Knowledge Base** — these are two separate features. The **PDF Database panel** described on this page provides per-app PDF storage: it appears in the sidebar only for apps that declare `pdf_vector_storage` (currently Chat Plus and Research Assistant), and each app keeps its own namespace. The [Knowledge Base](../apps/knowledge-base.md) is a different, project-wide library for saved conversations and imported documents with an app/Global scope model. Importing a PDF into one does not make it visible in the other.

## How It Works

- PDFs are converted to embeddings locally using `multilingual-e5-base`
- Vectors and metadata are persisted in the Qdrant Docker volume
- Search uses Qdrant's HNSW index over the locally-computed embeddings
- Works offline — no provider API key is needed for storage or retrieval

## Managing Your PDF Collection

The PDF Database panel in the web interface shows imported documents:

- **Import**: Upload a new PDF; the file is chunked, embedded, and indexed in the background
- **Refresh**: Update the list to show recently added documents
- **Delete (per-item)**: Remove a single PDF with confirmation
- **Clear All**: Remove every PDF in the current app's namespace with confirmation

Each app keeps its own namespace inside the Qdrant collection (the per-app `app_key` payload field), so PDFs imported into one app do not leak into another.

## Considerations

- **Data persistence**: Documents are stored in the `monadic-chat-qdrant-data` Docker volume
- **Backup**: Use the Export Document DB feature from the Electron menu to back up your data as a `.tar.gz` snapshot
- **Container rebuilds**: Export your database before rebuilding containers to prevent data loss

## Upgrading from Earlier Versions

If you are upgrading from 1.0.0-beta.13 or earlier, the previous storage format is incompatible with the current local stack:

- Existing locally-stored PDFs do not migrate automatically — re-import your PDFs after upgrading
- The legacy `monadic-chat-pgvector-data` Docker volume can be removed once re-import is complete
- Cloud PDF storage (OpenAI Vector Store) is no longer supported as of 1.0.0-beta.16. PDFs previously uploaded to OpenAI Files / Vector Store are not accessible from Monadic Chat after upgrade. The data still exists in your OpenAI account and can be removed manually from the OpenAI dashboard.
