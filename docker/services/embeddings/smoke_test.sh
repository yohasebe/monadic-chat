#!/usr/bin/env bash
# Smoke test for the embeddings service. Assumes the container is already
# running and that the embeddings port is exposed on the host (compose.dev.yml
# overlay). Run from the repository root:
#
#   docker compose -f docker/services/compose.yml \
#     -f docker/services/embeddings/compose.dev.yml \
#     --profile embeddings up -d embeddings_service
#   ./docker/services/embeddings/smoke_test.sh

set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8002}"
BASE="http://${HOST}:${PORT}"

echo "[1/3] /v1/health"
curl -sf "${BASE}/v1/health" | python3 -m json.tool

echo
echo "[2/3] /v1/info"
curl -sf "${BASE}/v1/info" | python3 -m json.tool

echo
echo "[3/3] /v1/embed (passage task)"
curl -sf -X POST "${BASE}/v1/embed" \
  -H "Content-Type: application/json" \
  -d '{"texts":["The quick brown fox","素早い茶色の狐"],"task":"passage"}' \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('model:    ', data['model'])
print('dimension:', data['dimension'])
print('vectors:  ', len(data['vectors']), 'returned')
print('first vec preview:', data['vectors'][0][:5], '...')
"

echo
echo "Smoke test passed."
