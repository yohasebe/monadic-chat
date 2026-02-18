#!/bin/sh

# Prepare log directory
mkdir -p /monadic/log

# Print server start message
echo "[SERVER STARTED]" >> /monadic/log/server.log
echo "Starting Falcon server at $(date)" >> /monadic/log/server.log

# Run Falcon server in foreground with Async support
# -n 1 uses single worker (solves session sharing, optimal for personal use)
# -b binds to all interfaces on port 4567
# Runs in foreground to keep container alive
exec bundle exec falcon serve -n 1 -b http://0.0.0.0:4567 >> /monadic/log/server.log 2>&1
