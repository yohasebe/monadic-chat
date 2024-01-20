#!/bin/sh

set -e

error_output=$(mktemp)

(
  set -e
  docker cp ./data/monadic.gz $(docker-compose ps -q db):/monadic.gz 2>"$error_output"

  docker-compose exec -T db bash -c "dropdb -f -U postgres monadic && createdb -U postgres --locale=C --template=template0 monadic && gunzip -c monadic.gz | psql -U postgres monadic && rm monadic.gz" 2>"$error_output"
) > /dev/null

if [ $? -eq 0 ]; then
  echo "[HTML]: Everything went successfully.</p>"
else
  echo "[HTML]: An error occurred:</p>"
  cat "$error_output"
fi

rm "$error_output"
