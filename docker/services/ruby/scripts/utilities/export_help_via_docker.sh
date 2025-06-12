#!/bin/bash
# Export help database using docker exec commands

CONTAINER="monadic-chat-pgvector-container"
EXPORT_DIR="/Users/yohasebe/code/monadic-chat/docker/services/pgvector/help_data"

# Ensure export directory exists
mkdir -p "$EXPORT_DIR"

echo "Exporting help database via Docker..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER"; then
    echo "Error: pgvector container is not running"
    exit 1
fi

# Check if database and tables exist
if ! docker exec $CONTAINER psql -U postgres -t -c "SELECT 1 FROM pg_database WHERE datname = 'monadic_help'" | grep -q "1"; then
    echo "Help database does not exist"
    exit 1
fi

# Export schema
cat > "$EXPORT_DIR/schema.sql" << 'EOF'
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
  metadata JSONB NOT NULL,
  embedding vector(3072),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
-- Note: ivfflat indexes removed due to 2000 dimension limit with text-embedding-3-large (3072 dims)
-- Consider using HNSW index or no vector index for now
CREATE INDEX IF NOT EXISTS idx_help_items_doc_id ON help_items(doc_id);
CREATE INDEX IF NOT EXISTS idx_help_docs_language ON help_docs(language);
EOF

echo "Schema exported to $EXPORT_DIR/schema.sql"

# Export help_docs data
echo "Exporting help_docs..."
docker exec $CONTAINER psql -U postgres -d monadic_help -t -A -c "SELECT row_to_json(t) FROM (SELECT * FROM help_docs ORDER BY id) t" > "$EXPORT_DIR/help_docs.tmp" 2>/dev/null

if [ -s "$EXPORT_DIR/help_docs.tmp" ]; then
    # Convert to proper JSON array
    echo "[" > "$EXPORT_DIR/help_docs.json"
    sed 's/$/,/' "$EXPORT_DIR/help_docs.tmp" | sed '$ s/,$//' >> "$EXPORT_DIR/help_docs.json"
    echo "]" >> "$EXPORT_DIR/help_docs.json"
    DOCS_COUNT=$(wc -l < "$EXPORT_DIR/help_docs.tmp")
    echo "Exported $DOCS_COUNT documents"
else
    echo "[]" > "$EXPORT_DIR/help_docs.json"
    DOCS_COUNT=0
    echo "No documents to export"
fi
rm -f "$EXPORT_DIR/help_docs.tmp"

# Export help_items data
echo "Exporting help_items..."
docker exec $CONTAINER psql -U postgres -d monadic_help -t -A -c "SELECT row_to_json(t) FROM (SELECT * FROM help_items ORDER BY id) t" > "$EXPORT_DIR/help_items.tmp" 2>/dev/null

if [ -s "$EXPORT_DIR/help_items.tmp" ]; then
    # Convert to proper JSON array
    echo "[" > "$EXPORT_DIR/help_items.json"
    sed 's/$/,/' "$EXPORT_DIR/help_items.tmp" | sed '$ s/,$//' >> "$EXPORT_DIR/help_items.json"
    echo "]" >> "$EXPORT_DIR/help_items.json"
    ITEMS_COUNT=$(wc -l < "$EXPORT_DIR/help_items.tmp")
    echo "Exported $ITEMS_COUNT items"
else
    echo "[]" > "$EXPORT_DIR/help_items.json"
    ITEMS_COUNT=0
    echo "No items to export"
fi
rm -f "$EXPORT_DIR/help_items.tmp"

# Generate metadata
EXPORT_ID=$(openssl rand -hex 16)
EXPORT_DATE=$(date "+%Y-%m-%d %H:%M:%S %z")

cat > "$EXPORT_DIR/metadata.json" << EOF
{
  "export_date": "$EXPORT_DATE",
  "export_id": "$EXPORT_ID",
  "docs_count": $DOCS_COUNT,
  "items_count": $ITEMS_COUNT
}
EOF

echo "$EXPORT_ID" > "$EXPORT_DIR/export_id.txt"

echo "Export completed successfully!"
echo "Export ID: $EXPORT_ID"