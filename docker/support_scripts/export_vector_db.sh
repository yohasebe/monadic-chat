#!/bin/sh

set -e

error_output=$(mktemp)

(
  set -e
  docker-compose exec -T db pg_dump -U postgres monadic 2>"$error_output" | gzip > ./data/monadic.gz
) > /dev/null

if [ $? -eq 0 ]; then
  echo "[HTML]: <p>Everything went successfully.</p>"
else
  echo "[HTML]: An error occurred:</p>"
  cat "$error_output"
fi

rm "$error_output"
