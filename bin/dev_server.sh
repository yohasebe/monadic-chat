#!/bin/bash

# Development server launcher for Monadic Chat
# This script starts support containers and runs the Ruby server locally
#
# PREREQUISITES:
#   Docker Desktop must be running before executing this script.
#
#   RECOMMENDED: Run 'electron .' in another terminal first, which will
#   automatically start and manage Docker Desktop. Then run this script.
#
#   Alternatively: Start Docker Desktop manually from Applications, wait
#   for it to fully initialize, then run this script.

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUBY_DIR="$PROJECT_ROOT/docker/services/ruby"

echo "Starting Monadic Chat development server..."
echo

# Check if Docker daemon is responding
if ! docker info > /dev/null 2>&1; then
  echo "========================================================================"
  echo "⚠️  Docker daemon is not responding"
  echo "========================================================================"
  echo
  echo "RECOMMENDED: Run 'electron .' in another terminal to manage Docker."
  echo "Then run this script again."
  echo
  exit 1
fi

echo "✅ Docker daemon is responding"
echo

# Stop Ruby container if running (we'll run it locally)
if docker ps -a --format '{{.Names}}' | grep -q '^monadic-chat-ruby-container$'; then
  echo "Stopping Ruby container (will run locally instead)..."
  docker container stop monadic-chat-ruby-container > /dev/null 2>&1 || true
fi

# Start support containers
SUPPORT_CONTAINERS=(
  "monadic-chat-pgvector-container"
  "monadic-chat-python-container"
  "monadic-chat-selenium-container"
)

for container in "${SUPPORT_CONTAINERS[@]}"; do
  if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
      echo "Starting ${container}..."
      docker container start "$container"
    else
      echo "✓ ${container} is already running"
    fi
  else
    echo "⚠️  ${container} does not exist. Run 'electron .' and press Start to build containers first."
  fi
done

echo
echo "========================================================================"
echo "Starting local Falcon server..."
echo "Access the application at: http://localhost:4567"
echo "Press Ctrl+C to stop"
echo "========================================================================"
echo

# Change to Ruby directory and start Falcon server
cd "$RUBY_DIR"

# Set macOS fork safety environment variable for Falcon
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

exec bundle exec falcon serve -b http://0.0.0.0:4567 -c config.ru
