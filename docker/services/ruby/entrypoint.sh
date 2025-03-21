#!/bin/sh

# Attempt to start the thin server and capture any errors
thin start -R config.ru -p 4567 -e development > /monadic/log/server.log 2>&1

# Check if the thin server started successfully
if [ $? -ne 0 ]; then
  echo "Failed to start thin server at $(date)" >> /monadic/log/server.log
fi

# Keep the container running
tail -f /dev/null
