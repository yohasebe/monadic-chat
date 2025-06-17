# Vector Database

Monadic Chat includes a powerful vector database system that enables semantic search capabilities. This document explains how this system works and how it's used in the application.

## Overview :id=overview

The vector database functionality in Monadic Chat:
- Converts text into numerical vector representations (embeddings)
- Stores these vectors in a PostgreSQL database using pgvector
- Enables semantic similarity search rather than just keyword matching
- Used in the PDF Navigator app and the Monadic Help app

## Technical Implementation :id=technical-implementation

### Database Container

The vector database functionality runs on the pgvector container (`monadic-chat-pgvector-container`). This container:
- Runs PostgreSQL with the pgvector extension
- Provides high-performance vector storage and similarity search
- Stores both the document content and its vector representations

### Text Processing Flow

![Vector Database Flow](../assets/images/rag.png ':size=700')

Here's the processing flow in the PDF Navigator app:

1. **Text Extraction**: 
   - PDFs are processed using PyMuPDF to extract raw text
   - The text is divided into segments with a configurable token size limit (default: 4000 tokens per segment)
   - An overlap of configurable lines (default: 4 lines) is set between consecutive segments to maintain context
   - These values can be configured in the `~/monadic/config/env` file as configuration variables: `PDF_RAG_TOKENS` and `PDF_RAG_OVERLAP_LINES`

2. **Embedding Generation**:
   - Each text segment is converted to an embedding vector using OpenAI's `text-embedding-3-large` model
   - These embeddings preserve the semantic meaning of the text
   - The embedding vectors have 3072 dimensions

3. **Vector Storage**:
   - Both the text segments and their vector representations are stored in the PostgreSQL database
   - The pgvector extension enables efficient vector operations

4. **Retrieval Process**:
   - When a user asks a question, their query is also converted to an embedding vector
   - The system finds text segments with the most similar embeddings to the query
   - These relevant segments are provided to the LLM along with the user's query
   - The LLM generates a response based on these relevant text segments

## Database Schema :id=database-schema

The database uses the following schema for vector storage:

- **docs**: Stores metadata about uploaded documents
  - `id`: Unique identifier for the document
  - `title`: Document title
  - `items`: Number of text segments in the document
  - `metadata`: Additional information about the document in JSON format
  - `embedding`: Combined embedding vector for the entire document

- **items**: Stores text segments and their embeddings
  - `id`: Unique identifier for the text segment
  - `doc_id`: Reference to parent document
  - `text`: The text content of the segment
  - `position`: Order position within the document
  - `embedding`: Vector representation of the text (stored using pgvector)
  - `metadata`: Supplementary information in JSON format

The `metadata` field primarily stores the token count for each segment, helping the LLM understand the size of retrieved text segments.

## Use in PDF Navigator :id=use-in-pdf-navigator

The PDF Navigator app leverages this system to provide intelligent document Q&A capabilities:

1. Users upload PDF documents via the UI
2. The system processes the document as described above
3. Users can ask questions about the document content
4. The system retrieves the most relevant segments using vector similarity search
5. These segments are provided to the LLM to generate informative answers

The app displays which document and text segment was used for each answer, clearly communicating the source of information to users.

## Use in Monadic Help :id=use-in-monadic-help

Monadic Chat uses two separate databases for vector storage:
- **`monadic_user_docs`** - For user-uploaded PDF documents in the PDF Navigator app
- **`monadic_help`** - For the built-in documentation search in the Monadic Help app

The Monadic Help app uses its vector database system as follows:

1. Documentation files are pre-processed and embedded during the build process
2. The help database is automatically built when you start Monadic Chat for the first time
3. When users ask questions about Monadic Chat, the system searches through embedded documentation
4. Relevant documentation sections are retrieved and provided to the LLM for generating helpful answers

The help system uses the same `text-embedding-3-large` model but maintains its embeddings in a separate database to keep documentation search isolated from user data. Note that while the database is built automatically, you need an OpenAI API key to use the Monadic Help app since it requires the embedding model for search functionality.
