#!/bin/sh

# Prepare log directory
mkdir -p /monadic/log

# Check if Ollama container exists (skip if docker command not available)
if command -v docker > /dev/null 2>&1; then
  if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "monadic-chat-ollama-container"; then
    export OLLAMA_AVAILABLE="true"
    echo "Ollama container detected" >> /monadic/log/server.log
  else
    export OLLAMA_AVAILABLE="false"
    echo "Ollama container not found" >> /monadic/log/server.log
  fi
else
  export OLLAMA_AVAILABLE="false"
  echo "Docker command not available, assuming Ollama not available" >> /monadic/log/server.log
fi

# Print server start message
echo "[SERVER STARTED]" >> /monadic/log/server.log
echo "Starting Falcon server at $(date)" >> /monadic/log/server.log

# Run Falcon server in foreground with Async support
# -n 1 uses single worker (solves session sharing, optimal for personal use)
# -b binds to all interfaces on port 4567
# Runs in foreground to keep container alive
exec bundle exec falcon serve -n 1 -b http://0.0.0.0:4567 >> /monadic/log/server.log 2>&1
