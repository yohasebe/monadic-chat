#!/bin/sh

# Prepare log directory
mkdir -p /monadic/log

# Print server start message
echo "[SERVER STARTED]" >> /monadic/log/server.log
echo "Starting Falcon server at $(date)" >> /monadic/log/server.log

# Values in config/env written as 1Password references (op://...) are read
# on the host by the desktop app, which streams the results into the tmpfs at
# /run/monadic-secrets after this container starts: the container has no op
# CLI, and the results must not reach a file on disk. CONFIG is built once
# when the server loads, so wait for them, but only when there are
# references; otherwise start at once, as before. Without them, those keys
# stay unset and the rest of the app still works.
SECRETS_FILE=/run/monadic-secrets/env
if grep -Eq '^[A-Za-z_][A-Za-z0-9_]*=["'"'"']?op://' /monadic/config/env 2>/dev/null; then
  waited=0
  while [ ! -f "$SECRETS_FILE" ] && [ "$waited" -lt "${MONADIC_SECRETS_WAIT:-60}" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if [ -f "$SECRETS_FILE" ]; then
    echo "1Password references: values received after ${waited}s" >> /monadic/log/server.log
  else
    echo "1Password references: no values received after ${waited}s; those keys stay unset" >> /monadic/log/server.log
  fi
fi

# Run Falcon server in foreground with Async support
# -n 1 uses single worker (solves session sharing, optimal for personal use)
# -b binds to all interfaces on port 4567
# Runs in foreground to keep container alive
exec bundle exec falcon serve -n 1 -b http://0.0.0.0:4567 >> /monadic/log/server.log 2>&1
