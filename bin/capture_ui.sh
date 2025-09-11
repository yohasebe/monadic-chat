#!/usr/bin/env bash
set -euo pipefail

# Simple helper to capture UI screenshots via the Python container's Selenium tools.
#
# Requirements:
#   - Monadic Chat containers are up (Ruby/Python/Selenium)
#   - Output directory is accessible on host; defaults to ~/monadic/data/screenshots
#
# Usage:
#   bin/capture_ui.sh --url http://localhost:4567 --element "#status-message" [--out ~/monadic/data/screenshots]
#   bin/capture_ui.sh --url http://localhost:4567 --fullpage true --out ~/monadic/data/screenshots

URL="http://localhost:4567"
ELEMENT=""
FULLPAGE="false"
OUT_DIR="${HOME}/monadic/data/screenshots"
TIMEOUT="30"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="$2"; shift 2;;
    --element)
      ELEMENT="$2"; shift 2;;
    --fullpage)
      FULLPAGE="$2"; shift 2;;
    --out)
      OUT_DIR="$2"; shift 2;;
    --timeout)
      TIMEOUT="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 --url <url> [--element <css>] [--fullpage true|false] [--out <dir>] [--timeout <sec>]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

PY_CONT="monadic-chat-python-container"
SEL_CONT="monadic-chat-selenium-container"

if ! docker ps --format '{{.Names}}' | grep -q "^${PY_CONT}$"; then
  echo "[ERROR] Python container not running (${PY_CONT}). Start Monadic Chat first." >&2
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -q "^${SEL_CONT}$"; then
  echo "[ERROR] Selenium container not running (${SEL_CONT}). Start Monadic Chat first." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

CMD=(python /monadic/scripts/cli_tools/webpage_fetcher.py --url "$URL" --mode png --filepath "/monadic/data/screenshots" --timeout-sec "$TIMEOUT")
if [[ -n "${ELEMENT}" ]]; then
  CMD+=(--element "$ELEMENT")
fi
CMD+=(--fullpage "$FULLPAGE")

echo "[INFO] Capturing: url=${URL} element='${ELEMENT}' fullpage=${FULLPAGE} -> ${OUT_DIR}"
docker exec -i "${PY_CONT}" "${CMD[@]}"

echo "[INFO] Host output dir: ${OUT_DIR}"

