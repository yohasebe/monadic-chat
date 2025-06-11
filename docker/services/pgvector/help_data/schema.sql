-- Create help database if not exists
SELECT 'CREATE DATABASE monadic_help;' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'monadic_help');

\c monadic_help;

-- Create pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Create help_docs table
CREATE TABLE IF NOT EXISTS help_docs (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  file_path TEXT NOT NULL,
  section TEXT NOT NULL,
  language VARCHAR(10) NOT NULL,
  items INTEGER NOT NULL,
  metadata JSONB NOT NULL,
  embedding vector(1536),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(file_path, language)
);

-- Create help_items table
CREATE TABLE IF NOT EXISTS help_items (
  id SERIAL PRIMARY KEY,
  doc_id INTEGER REFERENCES help_docs(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  position INTEGER NOT NULL,
  heading TEXT,
  metadata JSONB NOT NULL,
  embedding vector(1536),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_help_docs_embedding ON help_docs USING ivfflat (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_help_items_embedding ON help_items USING ivfflat (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_help_items_doc_id ON help_items(doc_id);
CREATE INDEX IF NOT EXISTS idx_help_docs_language ON help_docs(language);
