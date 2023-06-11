#!/bin/sh

set -e

error_output=$(mktemp)

(
  set -e
  docker-compose exec -T db pg_dump -U postgres monadic 2>"$error_output" | gzip > ./data/monadic.gz
) > /dev/null

if [ $? -eq 0 ]; then
  echo "Everything went successfully."
else
  echo "An error occurred:"
  cat "$error_output"
fi

rm "$error_output"
