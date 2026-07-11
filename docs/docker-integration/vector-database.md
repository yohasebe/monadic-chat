# Vector Database

Monadic Chat includes a vector database system that enables semantic search across documentation and user-uploaded PDFs. This document explains how that system works and how it is used inside the application.

## Overview :id=overview

The vector database functionality in Monadic Chat:
- Converts text into numerical vector representations (embeddings) locally
- Stores these vectors in a Qdrant container alongside structured metadata
- Enables semantic similarity search rather than keyword matching
- Powers the Knowledge Base app and the Monadic Help app

The pipeline is fully local — no external API key is required to embed text or to search the vector database.

## Technical Implementation :id=technical-implementation

### Service Containers

Two cooperating containers handle vector storage and embedding inference:

- **`monadic-chat-qdrant-container`** runs the [Qdrant](https://qdrant.tech) vector database. It stores documents, chunks, and their embeddings, plus payload metadata used for filtering and grouping.
- **`monadic-chat-embeddings-container`** runs a small FastAPI service wrapping the [`intfloat/multilingual-e5-base`](https://huggingface.co/intfloat/multilingual-e5-base) sentence-transformer model. It converts text into 768-dimensional vectors on the host CPU.

Both containers start automatically with Monadic Chat and require no configuration.

### Text Processing Flow

![Vector Database Flow](../assets/images/rag.png ':size=700')

Here is the processing flow in the Knowledge Base import pipeline:

1. **Content Extraction**:
   - PDFs are routed through the Extractor container ([Docling](https://github.com/docling-project/docling) with OCR and layout analysis) when the Knowledge Base Quality Pack is installed; otherwise they are processed via [pdfplumber](https://github.com/jsvine/pdfplumber) to extract text and tables, with structure recovered as Markdown
   - Office files (`.docx`/`.xlsx`/`.pptx`) are extracted via `python-docx` / `openpyxl` / `python-pptx`
   - Markdown and source-code files are read directly; section boundaries come from headings and top-level definitions respectively
   - The extracted content is split into per-section chunks (≈200–4000 chars) with importer-specific boundary rules

2. **Embedding Generation**:
   - Each text segment is sent to the embeddings container, which produces a 768-dimensional vector using `multilingual-e5-base`
   - The model handles English, Japanese, and many other languages with comparable quality
   - Vectors are L2-normalized so cosine similarity reduces to a dot product

3. **Vector Storage**:
   - Each chunk becomes a Qdrant point under the `library_turns` collection, with the embedding as the vector and `{conversation_id, scope_app, turn_idx, text, ...}` as payload
   - A conversation-level point lives in the `library_summaries` collection with title, source, content_type, and a placeholder summary embedding, enabling document-level cascade retrieval

4. **Retrieval Process**:
   - When a user asks a question, the query is embedded with the same model (with the `query:` prefix)
   - Qdrant returns the most similar text segments using cosine similarity over an HNSW index
   - The relevant segments are provided to the LLM along with the user's query
   - The LLM generates a response grounded in those segments

## Schema :id=database-schema

Qdrant organises data into named collections. Monadic Chat uses the following:

- **`library_summaries`** — One point per conversation/document. Payload: `{conversation_id, scope_app, content_type, source, title, language, license, topics, messages, participants, ...}`. Used as the cascade entry point for retrieval and as the source-of-truth for the Knowledge Base browse list.
- **`library_turns`** — One point per chunked text segment. Vector: chunk embedding. Payload: `{conversation_id, scope_app, turn_idx, speaker_id, text, ...}`. Main RAG retrieval unit consumed by the `library_search` tool.
- **`help_docs` / `help_items`** — Points for the Monadic Help documentation index. Built into the Ruby image at packaging time and loaded once on first start.

All collections use 768-dimensional vectors with cosine distance and HNSW indexing for fast filtered search.

## Scope Filtering :id=visibility

Library entries carry a `scope_app` payload — either an app + provider class name (e.g. `ChatOpenAI`) or the literal `Global` sentinel. The Knowledge Base UI sees every entry regardless of scope, while retrieval filters on `scope_app IN [current app, "Global"]`: app-scoped entries are retrievable only from the app + provider they were saved in, and `Global` entries are retrievable from every app via the `library_search` tool. This replaces the previous per-app PDF isolation model — the Library is project-wide, and cross-app access is opted into per entry via the `Global` scope (see the [scope model](/apps/knowledge-base.md) on the Knowledge Base page).

## Use in the Knowledge Base :id=use-in-knowledge-base

The Knowledge Base app uses this system to provide unified content Q&A:

1. Users save the current chat session or click **Import file** in the Browse modal
2. The system extracts, chunks, embeds, and stores the content, following the [processing flow](#technical-implementation) above
3. Users ask questions about the content; other apps can ask too via `library_search` when the user has flipped the entry to `Global`
4. The system retrieves the most relevant chunks using a cascade query (summaries → turns) over the Qdrant collections above
5. Retrieved chunks are passed to the LLM to ground its answer

Imported files are also persisted under `~/monadic/data/library/imports/` for traceability.

## Use in Monadic Help :id=use-in-monadic-help

The Monadic Help app uses the same Qdrant + embeddings stack but reads from the `help_docs` and `help_items` collections, which are pre-built from the documentation at packaging time, shipped inside the Ruby image as a JSON dump, and loaded into Qdrant once on first start. Because both embedding inference and storage are local, help search works without any provider API key. For the build pipeline, runtime bootstrap, and configuration variables, see the [Help System](../advanced-topics/help-system.md) documentation.
