#!/bin/bash
# Import help database from pre-built files

set -e

# During container initialization, we need to use the postgres user
export PGUSER=postgres

# Check if help data exists
if [ ! -f "/help_data/metadata.json" ]; then
  echo "No help data to import"
  exit 0
fi

echo "Importing help database..."

# Create database if it doesn't exist
psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'monadic_help'" | grep -q 1 || psql -U postgres -c "CREATE DATABASE monadic_help"

# Import schema first
if [ -f "/help_data/schema.sql" ]; then
  psql -U postgres -f /help_data/schema.sql
fi

# Check if data already exists after schema is created
EXISTING_COUNT=$(psql -U postgres -d monadic_help -tc "SELECT COUNT(*) FROM help_items" 2>/dev/null || echo "0")
EXISTING_COUNT=$(echo $EXISTING_COUNT | tr -d ' ')
if [ "$EXISTING_COUNT" != "0" ]; then
  echo "Help database already contains $EXISTING_COUNT items, skipping import"
  exit 0
fi

# Import data using a Python script for JSON handling
cat > /tmp/import_help.py << 'EOF'
#!/usr/bin/env python3
import json
import psycopg2
from psycopg2.extras import Json

# Connect to database via Unix socket during initialization
conn = psycopg2.connect(
    dbname="monadic_help",
    user="postgres",
    host="/var/run/postgresql"
)
cur = conn.cursor()

# Import help_docs
with open('/help_data/help_docs.json', 'r') as f:
    docs = json.load(f)
    
for doc in docs:
    # Convert embedding array back to pgvector format
    embedding = doc.get('embedding')
    if embedding:
        embedding_str = '[' + ','.join(map(str, embedding)) + ']'
    else:
        embedding_str = None
    
    cur.execute("""
        INSERT INTO help_docs (id, title, file_path, section, language, items, metadata, embedding, created_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s::vector, %s)
        ON CONFLICT (file_path, language) DO UPDATE SET
            title = EXCLUDED.title,
            section = EXCLUDED.section,
            items = EXCLUDED.items,
            metadata = EXCLUDED.metadata,
            embedding = EXCLUDED.embedding,
            updated_at = CURRENT_TIMESTAMP
    """, (
        doc['id'], doc['title'], doc['file_path'], doc['section'],
        doc['language'], doc['items'], Json(doc['metadata']),
        embedding_str, doc['created_at']
    ))

# Import help_items
with open('/help_data/help_items.json', 'r') as f:
    items = json.load(f)
    
for item in items:
    # Convert embedding array back to pgvector format
    embedding = item.get('embedding')
    if embedding:
        embedding_str = '[' + ','.join(map(str, embedding)) + ']'
    else:
        embedding_str = None
    
    cur.execute("""
        INSERT INTO help_items (id, doc_id, text, position, heading, metadata, embedding, created_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s::vector, %s)
        ON CONFLICT DO NOTHING
    """, (
        item['id'], item['doc_id'], item['text'], item['position'],
        item['heading'], Json(item['metadata']), embedding_str, item['created_at']
    ))

# Update sequences
cur.execute("SELECT setval('help_docs_id_seq', (SELECT MAX(id) FROM help_docs))")
cur.execute("SELECT setval('help_items_id_seq', (SELECT MAX(id) FROM help_items))")

conn.commit()
cur.close()
conn.close()

print("Help database imported successfully!")
EOF

python3 /tmp/import_help.py || {
  echo "Python import failed, retrying with alternative method..."
  
  # Alternative: Use psql with JSON processing
  psql -U postgres -d monadic_help << 'SQLEOF'
  -- Import help_docs
  CREATE TEMP TABLE temp_docs (data text);
  \copy temp_docs FROM '/help_data/help_docs.json'
  
  INSERT INTO help_docs (id, title, file_path, section, language, items, metadata, embedding, created_at)
  SELECT 
    (elem->>'id')::integer,
    elem->>'title',
    elem->>'file_path', 
    elem->>'section',
    elem->>'language',
    (elem->>'items')::integer,
    (elem->'metadata')::jsonb,
    NULL, -- Skip embeddings in fallback
    (elem->>'created_at')::timestamp
  FROM (
    SELECT jsonb_array_elements(data::jsonb) AS elem 
    FROM temp_docs
  ) t
  ON CONFLICT (file_path, language) DO NOTHING;
  
  -- Import help_items
  CREATE TEMP TABLE temp_items (data text);
  \copy temp_items FROM '/help_data/help_items.json'
  
  INSERT INTO help_items (id, doc_id, text, position, heading, metadata, embedding, created_at)
  SELECT 
    (elem->>'id')::integer,
    (elem->>'doc_id')::integer,
    elem->>'text',
    (elem->>'position')::integer,
    elem->>'heading',
    (elem->'metadata')::jsonb,
    NULL, -- Skip embeddings in fallback
    (elem->>'created_at')::timestamp
  FROM (
    SELECT jsonb_array_elements(data::jsonb) AS elem 
    FROM temp_items
  ) t
  ON CONFLICT DO NOTHING;
  
  -- Update sequences
  SELECT setval('help_docs_id_seq', COALESCE((SELECT MAX(id) FROM help_docs), 1));
  SELECT setval('help_items_id_seq', COALESCE((SELECT MAX(id) FROM help_items), 1));
SQLEOF
}

echo "Help database import completed!"