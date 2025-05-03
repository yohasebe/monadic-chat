#!/bin/sh

# Prepare log directory
mkdir -p /monadic/log

# Run Thin server with optimized settings for faster startup
thin start -R config.ru -p 4567 -e development -d -l /monadic/log/server.log

# Check if the thin server started successfully
if [ $? -ne 0 ]; then
  echo "Failed to start thin server at $(date)" >> /monadic/log/server.log
fi

# Keep the container running
tail -f /dev/null
