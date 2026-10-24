# Vector Database

Monadic Chat includes a vector database for searching by meaning across the Knowledge Base, the PDF Database, and the help documentation. This page explains how it is used.

## Overview :id=overview

The vector database:
- Converts text into vectors (embeddings) on your computer
- Stores the vectors in the Qdrant container, together with information about where each piece of text came from
- Finds text by similarity of meaning rather than by matching keywords
- Is used by the Knowledge Base, the PDF Database, and the Monadic Chat Help app

Embedding and search run locally; no API key is needed for them.

## Technical Implementation :id=technical-implementation

### Service Containers

Two containers work together:

- **`monadic-chat-qdrant-container`** runs the [Qdrant](https://qdrant.tech) vector database. It stores the text, the vectors, and the information used to filter and group the results.
- **`monadic-chat-embeddings-container`** converts text into vectors with a multilingual embedding model, on the CPU. The model handles English, Japanese, and many other languages.

Both containers start with Monadic Chat and need no configuration.

### Text Processing Flow

When a file is imported into the Knowledge Base:

1. **Text extraction**:
   - PDFs are processed with [Docling](https://github.com/docling-project/docling) (layout analysis and OCR) in the Extractor container when the Knowledge Base Quality Pack is installed and running. Otherwise the Python container extracts the text and tables of PDFs without OCR, so the text of scanned, image-only PDFs is not extracted
   - Office files (`.docx`, `.xlsx`, `.pptx`) are read in the Python container
   - Markdown and source code are read directly
   - The text is split into sections, at headings in Markdown and at top-level definitions in source code

2. **Embedding**: Each section is converted into a vector by the embeddings container

3. **Storage**: The sections and their vectors are stored in Qdrant, together with the document's title, source, and type

4. **Retrieval**:
   - A question is converted into a vector with the same model
   - Qdrant returns the sections whose meaning is closest to the question
   - The sections are given to the LLM together with the question, and the LLM answers based on them

## What Is Stored :id=database-schema

- **Knowledge Base**: saved conversations and imported files, as documents and their sections
- **PDF Database**: PDFs imported through the [PDF Database](../basic-usage/pdf_storage.md) panel. Each app sees only the PDFs imported in it; the PDF Database is separate from the Knowledge Base
- **Help data**: the Monadic Chat documentation, used by the Monadic Chat Help app

## Scope :id=visibility

Each Knowledge Base entry belongs either to the app (and provider) it was saved in, or to `Global`. The Knowledge Base browser shows every entry. Apps that support Knowledge Base search use it only when **Use Knowledge Base for retrieval (this session)** is on in the Knowledge Base panel, and they find the entries saved in that app and the `Global` entries. Live Conversation searches it through its own **Tools** switch. See the [scope model](/apps/knowledge-base.md) on the Knowledge Base page.

## Use in the Knowledge Base :id=use-in-knowledge-base

1. Click **Save** in the Knowledge Base panel to save the current conversation, or click **Import file** in the Knowledge Base browser (**Browse**)
2. Monadic Chat extracts, splits, embeds, and stores the content, as described [above](#technical-implementation)
3. Ask questions about the content in an app that searches the Knowledge Base, as described under [Scope](#visibility)
4. Monadic Chat finds the most relevant sections, first by document and then by section
5. The LLM answers based on the sections it receives

During an import, the file is copied to `~/monadic/data/library/imports/`; the copy is deleted when the import ends.

## Use in Monadic Chat Help :id=use-in-monadic-help

The Monadic Chat Help app searches the help data with the same Qdrant and embeddings containers. The help data is installed from **Help Data** in the Monadic Chat Info panel; installing it needs no API key. The Monadic Chat Help app itself uses OpenAI, so chatting with it needs an OpenAI API key. See [Help System](../advanced-topics/help-system.md).
