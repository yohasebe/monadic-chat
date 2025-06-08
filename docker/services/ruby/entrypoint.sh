#!/bin/sh

# Prepare log directory
mkdir -p /monadic/log

# Check if Ollama container exists
if docker ps -a --format "{{.Names}}" | grep -q "monadic-chat-ollama-container"; then
  export OLLAMA_AVAILABLE="true"
  echo "Ollama container detected" >> /monadic/log/server.log
else
  export OLLAMA_AVAILABLE="false"
  echo "Ollama container not found" >> /monadic/log/server.log
fi

# Run Thin server with optimized settings for faster startup
thin start -R config.ru -p 4567 -e development -d -l /monadic/log/server.log

# Check if the thin server started successfully
if [ $? -ne 0 ]; then
  echo "Failed to start thin server at $(date)" >> /monadic/log/server.log
fi

# Keep the container running
tail -f /dev/null
