#!/bin/bash
set -e

# Start the original entrypoint in the background
/usr/local/bin/docker-entrypoint.sh postgres &
PG_PID=$!

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to start..."
until pg_isready -h localhost -p 5432 -U postgres -q; do
  sleep 1
done

echo "PostgreSQL is ready. Checking help database..."

# Import help data if needed
if [ -f "/help_data/metadata.json" ]; then
  # Check if database exists
  if ! psql -U postgres -lqt | cut -d \| -f 1 | grep -qw monadic_help; then
    echo "Creating monadic_help database..."
    psql -U postgres -c "CREATE DATABASE monadic_help"
  fi
  
  # Check if data exists
  EXISTING_COUNT=$(psql -U postgres -d monadic_help -tc "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'help_items'" 2>/dev/null || echo "0")
  EXISTING_COUNT=$(echo $EXISTING_COUNT | tr -d ' ')
  
  if [ "$EXISTING_COUNT" = "0" ]; then
    echo "Running help database import..."
    bash /docker-entrypoint-initdb.d/20-import-help-data.sh || echo "Import script failed, but continuing..."
  else
    # Check if tables have data
    ITEM_COUNT=$(psql -U postgres -d monadic_help -tc "SELECT COUNT(*) FROM help_items" 2>/dev/null || echo "0")
    ITEM_COUNT=$(echo $ITEM_COUNT | tr -d ' ')
    
    if [ "$ITEM_COUNT" = "0" ]; then
      echo "Tables exist but are empty. Running import..."
      bash /docker-entrypoint-initdb.d/20-import-help-data.sh || echo "Import script failed, but continuing..."
    else
      echo "Help database already contains $ITEM_COUNT items"
    fi
  fi
fi

# Wait for the PostgreSQL process
wait $PG_PID