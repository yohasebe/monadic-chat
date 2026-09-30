#!/bin/bash
# Downloads the third-party files the web UI serves from /vendor, at the
# versions and hashes pinned in bin/assets_list.sh. The app payload already
# carries them, so an image build normally only confirms their hashes and
# needs no network.
set -e

source "/monadic/bin/assets_list.sh"
vendor_fetch "/monadic/public/vendor"

# Build maxGraph IIFE bundle (no CDN UMD build available)
echo "Building maxGraph bundle..."
if [ ! -f "/monadic/public/vendor/js/maxgraph.bundle.js" ]; then
  cd /tmp
  npm init -y --silent > /dev/null 2>&1
  npm install --silent @maxgraph/core@0.22.0 esbuild@0.25.0 > /dev/null 2>&1
  npx esbuild node_modules/@maxgraph/core/lib/esm/index.js \
    --bundle --format=iife --global-name=maxgraph \
    --outfile=/monadic/public/vendor/js/maxgraph.bundle.js \
    --minify 2>&1
  rm -rf /tmp/node_modules /tmp/package.json /tmp/package-lock.json
  echo "maxGraph bundle built successfully"
else
  echo "maxGraph bundle already exists, skipping"
fi

echo "All vendor files have been downloaded"