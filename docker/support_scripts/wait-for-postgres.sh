#!/bin/sh

set -e

host="$1"
shift
cmd="$@"

until psql -h "$host" -U "postgres" -c '\q' 2>/dev/null; do
  >&2 echo "[HTML]: <p>Postgres is unavailable - sleeping</p>"
  sleep 1.5
done

>&2 echo "[HTML]: <p>Postgres is up - executing command</p>"
exec $cmd
