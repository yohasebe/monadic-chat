#!/bin/bash
# Downloads the third-party files the web UI serves from /vendor, at the
# versions and hashes pinned in docker/services/ruby/bin/assets_list.sh.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../docker/services/ruby/bin/assets_list.sh"

VENDOR_PATH="${SCRIPT_DIR}/../docker/services/ruby/public/vendor"
vendor_fetch "${VENDOR_PATH}"

echo "All vendor files match their pinned hashes"
