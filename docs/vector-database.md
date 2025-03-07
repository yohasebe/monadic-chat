# Vector Database

Monadic Chat includes a powerful vector database system that enables semantic search capabilities. This document explains how this system works and how it's used in the application.

## Overview

The vector database functionality in Monadic Chat:
- Converts text into numerical vector representations (embeddings)
- Stores these vectors in a PostgreSQL database using pgvector
- Enables semantic similarity search rather than just keyword matching
- Currently only used in the PDF Navigator app

## Technical Implementation

### Database Container

The vector database functionality runs on the pgvector container (`monadic-chat-pgvector-container`). This container:
- Runs PostgreSQL with the pgvector extension
- Provides high-performance vector storage and similarity search
- Stores both the document content and its vector representations

### Text Processing Flow

![Vector Database Flow](./assets/images/rag.png ':size=700')

Here's the processing flow in the PDF Navigator app:

1. **Text Extraction**: 
   - PDFs are processed using PyMuPDF to extract raw text
   - The text is divided into segments with a fixed token size limit of 2000 tokens per segment
   - An overlap of 2 lines is set between consecutive segments to maintain context

2. **Embedding Generation**:
   - Each text segment is converted to an embedding vector using OpenAI's embedding models
   - These embeddings preserve the semantic meaning of the text

3. **Vector Storage**:
   - Both the text segments and their vector representations are stored in the PostgreSQL database
   - The pgvector extension enables efficient vector operations

4. **Retrieval Process**:
   - When a user asks a question, their query is also converted to an embedding vector
   - The system finds text segments with the most similar embeddings to the query
   - These relevant segments are provided to the LLM along with the user's query
   - The LLM generates a response based on these relevant text segments

## Database Schema

The database uses the following schema for vector storage:

- **docs**: Stores metadata about uploaded documents
  - `id`: Unique identifier for the document
  - `title`: Document title
  - `created_at`: Timestamp when the document was added

- **texts**: Stores text segments and their embeddings
  - `id`: Unique identifier for the text segment
  - `doc_id`: Reference to parent document
  - `text`: The text content of the segment
  - `position`: Order position within the document
  - `embedding`: Vector representation of the text (stored using pgvector)
  - `metadata`: Supplementary information in JSON format.

`metadata` primarily uses the `tokens` key to store token count information. This metadata is returned to the LLM to provide context about the size of text segments.

## Use in PDF Navigator

The PDF Navigator app leverages this system to provide intelligent document Q&A capabilities:

1. Users upload PDF documents via the UI
2. The system processes the document as described above
3. Users can ask questions about the document content
4. The system retrieves the most relevant segments using vector similarity search
5. These segments are provided to the LLM to generate informative answers

The app displays which document and text segment was used for each answer, clearly communicating the source of information to users.
