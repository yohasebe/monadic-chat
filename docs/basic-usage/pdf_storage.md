# PDF Storage Modes

Monadic Chat offers two ways to store and search through PDF documents: Local PDF (using PGVector) and Cloud PDF (using OpenAI Vector Store). This flexibility allows you to choose between full local control and cloud-hosted convenience.

## Understanding Storage Modes

### Local PDF (PGVector)

The local storage mode processes PDFs on your machine and stores them in a PostgreSQL database with the pgvector extension. This gives you complete control over your data:

- PDFs are converted to text embeddings and stored locally
- All processing happens on your computer
- Data persists in the PGVector Docker container
- Recommended when you want full local control of your documents

### Cloud PDF (OpenAI Vector Store)

The cloud storage mode uploads your PDFs to OpenAI's servers and uses their Vector Store service for searching:

- PDFs are uploaded to OpenAI Files
- Documents are attached to a shared Vector Store
- OpenAI handles all indexing and search operations
- Recommended for zero-setup convenience and when you're already using OpenAI services

## Choosing Your Storage Mode

You can select your preferred storage mode in the Settings panel under "PDF Storage Mode":

- **Local (PGVector)** - Default option, stores everything locally
- **Cloud (OpenAI Vector Store)** - Uses OpenAI's hosted service

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
- Uses PostgreSQL's pgvector extension for similarity search
- Search happens entirely on your machine
- No external API calls for searching

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

- **Data Persistence**: Documents are stored in the PGVector Docker volume
- **Backup**: Use the Export Document DB feature from the Electron menu to back up your data
- **Container Rebuilds**: Export your database before rebuilding containers to prevent data loss

## Deletion Behavior

### Per-File Deletion
- **Local**: Removes the document from the PGVector database
- **Cloud**: Deletes the file from OpenAI Files and removes it from the Vector Store

### Clear All
- **Local**: Removes all documents from the PGVector database
- **Cloud**: Removes all attached files from the Vector Store

?> After clearing all files from a Vector Store, searches will return no results because the search corpus is empty.
