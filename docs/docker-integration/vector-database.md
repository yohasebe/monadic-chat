# Vector Database

Monadic Chat includes a vector database system that enables semantic search across documentation and user-uploaded PDFs. This document explains how that system works and how it is used inside the application.

## Overview :id=overview

The vector database functionality in Monadic Chat:
- Converts text into numerical vector representations (embeddings) locally
- Stores these vectors in a Qdrant container alongside structured metadata
- Enables semantic similarity search rather than keyword matching
- Powers the PDF Navigator app and the Monadic Help app

The pipeline is fully local — no external API key is required to embed text or to search the vector database.

## Technical Implementation :id=technical-implementation

### Service Containers

Two cooperating containers handle vector storage and embedding inference:

- **`monadic-chat-qdrant-container`** runs the [Qdrant](https://qdrant.tech) vector database. It stores documents, chunks, and their embeddings, plus payload metadata used for filtering and grouping.
- **`monadic-chat-embeddings-container`** runs a small FastAPI service wrapping the [`intfloat/multilingual-e5-base`](https://huggingface.co/intfloat/multilingual-e5-base) sentence-transformer model. It converts text into 768-dimensional vectors on the host CPU.

Both containers start automatically with Monadic Chat and require no configuration.

### Text Processing Flow

![Vector Database Flow](../assets/images/rag.png ':size=700')

Here is the processing flow in the PDF Navigator app:

1. **Text Extraction**:
   - PDFs are processed using PyMuPDF to extract raw text
   - The text is divided into segments with a configurable token size limit (default: 4000 tokens per segment)
   - An overlap of configurable lines (default: 4 lines) is kept between consecutive segments to maintain context
   - These values can be configured in `~/monadic/config/env` via `PDF_RAG_TOKENS` and `PDF_RAG_OVERLAP_LINES`

2. **Embedding Generation**:
   - Each text segment is sent to the embeddings container, which produces a 768-dimensional vector using `multilingual-e5-base`
   - The model handles English, Japanese, and many other languages with comparable quality
   - Vectors are L2-normalized so cosine similarity reduces to a dot product

3. **Vector Storage**:
   - Each segment becomes a Qdrant point under the `pdf_items` collection, with the embedding as the vector and `{doc_id, text, position, app_key, metadata}` as payload
   - A document-level point lives in the `pdf_docs` collection with the average of its item embeddings, enabling document-level similarity searches

4. **Retrieval Process**:
   - When a user asks a question, the query is embedded with the same model (with the `query:` prefix)
   - Qdrant returns the most similar text segments using cosine similarity over an HNSW index
   - The relevant segments are provided to the LLM along with the user's query
   - The LLM generates a response grounded in those segments

## Schema :id=database-schema

Qdrant organises data into named collections. Monadic Chat uses four:

- **`pdf_docs`** — One point per uploaded PDF. Vector: average of item embeddings. Payload: `{title, items, app_key, metadata, created_at}`.
- **`pdf_items`** — One point per chunked text segment. Vector: chunk embedding. Payload: `{doc_id, text, position, app_key, metadata}`.
- **`help_docs`** — One point per documentation file. Vector: average of item embeddings. Payload: `{title, file_path, section, language, items, is_internal, metadata}`.
- **`help_items`** — One point per chunk of documentation. Vector: chunk embedding. Payload: `{doc_id, text, position, heading, language, is_internal, metadata}`.

All collections use 768-dimensional vectors with cosine distance and HNSW indexing for fast filtered search.

## App-Level Isolation :id=app-isolation

PDFs uploaded via different apps remain separate. Each upload is tagged with an `app_key` in its payload (for example `pdfnavigatoropenai`), and queries always include an `app_key` filter. This preserves the privacy guarantee that the prior per-database design provided, without requiring multiple physical databases.

## Use in PDF Navigator :id=use-in-pdf-navigator

The PDF Navigator app leverages this system to provide document Q&A:

1. Users upload PDF documents via the UI
2. The system extracts, chunks, embeds, and stores them
3. Users ask questions about the document content
4. The system retrieves the most relevant segments using vector similarity search
5. The segments are provided to the LLM to generate informative answers

The app displays which document and text segment was used for each answer, clearly communicating the source of information to users.

?> For information about PDF storage mode options (local vs. cloud), see the [PDF Storage](../basic-usage/pdf_storage.md) documentation.

## Use in Monadic Help :id=use-in-monadic-help

The Monadic Help app uses the same Qdrant + embeddings stack but reads from the `help_docs` and `help_items` collections, which are pre-built at packaging time:

1. During the Monadic Chat build, all documentation files are processed and embedded
2. The result is shipped inside the Ruby image as a JSON dump (`help_data/help_db.json`)
3. On first start, Monadic Chat loads the dump into Qdrant once
4. When users ask questions, the same query/passage embedding workflow finds the relevant documentation snippets
5. Those snippets are passed to the LLM to generate the answer

Because both embedding inference and storage are local, the help system works without any provider API key.
