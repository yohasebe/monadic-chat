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
  is_internal BOOLEAN DEFAULT FALSE,
  metadata JSONB NOT NULL,
  embedding vector(3072),
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
  is_internal BOOLEAN DEFAULT FALSE,
  metadata JSONB NOT NULL,
  embedding vector(3072),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
-- Note: ivfflat indexes removed due to 2000 dimension limit with text-embedding-3-large (3072 dims)
-- Consider using HNSW index or no vector index for now
CREATE INDEX IF NOT EXISTS idx_help_items_doc_id ON help_items(doc_id);
CREATE INDEX IF NOT EXISTS idx_help_docs_language ON help_docs(language);
CREATE INDEX IF NOT EXISTS idx_help_docs_file_path ON help_docs(file_path);
CREATE INDEX IF NOT EXISTS idx_help_docs_is_internal ON help_docs(is_internal);
CREATE INDEX IF NOT EXISTS idx_help_items_is_internal ON help_items(is_internal);
