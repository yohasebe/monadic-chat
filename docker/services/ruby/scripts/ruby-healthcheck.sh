#!/bin/sh
# Lightweight healthcheck for the Ruby (Falcon) container
# Returns 0 when the HTTP endpoint is reachable, non‑zero otherwise.

set -e

URL="http://localhost:4567/"

# Try a quick HTTP probe
if curl -fsS "$URL" >/dev/null 2>&1; then
  exit 0
fi

# As a fallback, give Falcon a very short grace period
sleep 1
if curl -fsS "$URL" >/dev/null 2>&1; then
  exit 0
fi

exit 1

