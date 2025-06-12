#!/bin/bash
# Check if PGVector container needs rebuilding due to help data updates

# Path to help export ID file
# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_ID_FILE="$SCRIPT_DIR/help_data/export_id.txt"

# Check if export ID file exists
if [ ! -f "$EXPORT_ID_FILE" ]; then
  echo "No help export ID found"
  exit 0
fi

# Get current export ID
CURRENT_ID=$(cat "$EXPORT_ID_FILE")

# Get container's export ID
CONTAINER_ID=$(docker exec monadic-chat-pgvector-container cat /help_export_id.txt 2>/dev/null || echo "")

if [ "$CURRENT_ID" != "$CONTAINER_ID" ]; then
  echo "Help database has been updated. Container rebuild required."
  echo "Current ID: $CURRENT_ID"
  echo "Container ID: $CONTAINER_ID"
  exit 1
else
  echo "Help database is up to date."
  exit 0
fi