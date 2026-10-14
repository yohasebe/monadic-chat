# PDF Database

The PDF Database gives some apps a store of PDFs that the AI can search during conversations. The PDFs are processed and stored on your computer; no API key is needed to store or search them.

?> **PDF Database vs. Knowledge Base** — these are two separate features. The **PDF Database** panel is shown only for the apps that have it (the OpenAI versions of Chat Plus and Research Assistant), and each app keeps its own PDFs. The [Knowledge Base](../apps/knowledge-base.md) is a separate library of saved conversations and imported documents. A PDF imported into one is not visible in the other.

## How It Works

- PDFs are processed and searched on your computer, also offline
- They are stored in a Docker volume of Monadic Chat

## Managing Your PDF Collection

The PDF Database panel in the web interface (its Local PDF section) shows imported documents:

- **Import**: Upload a new PDF; it is processed in the background
- **Refresh**: Update the list to show recently added documents
- **Delete (per-item)**: Remove a single PDF with confirmation
- **Clear All**: Remove every PDF of the current app with confirmation

PDFs imported into one app are not visible in another.

## Considerations

- **Data persistence**: Documents are stored in the `monadic-chat-qdrant-data` Docker volume
- **Backup**: Use **Export Document DB** in the Actions menu to back up your data (encrypted or plain), and **Import Document DB** to restore it
- **Container rebuilds**: Export your database before rebuilding containers to prevent data loss
