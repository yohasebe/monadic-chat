#!/bin/bash
# Script to fix Font Awesome webfont paths in CSS files

# Paths
FA_CSS_PATH="/monadic/public/vendor/css/all.min.css"

# Check if the file exists
if [ ! -f "$FA_CSS_PATH" ]; then
  echo "Font Awesome CSS file not found: $FA_CSS_PATH"
  exit 1
fi

# Fix font paths in the CSS file - replace URLs pointing to CDN paths with local webfonts
echo "Fixing Font Awesome webfont paths in CSS file..."
# Docker container will always be Linux, but this is for consistency
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS version
  sed -i '' 's|url("../webfonts/|url("/vendor/webfonts/|g' "$FA_CSS_PATH"
else
  # Linux version
  sed -i 's|url("../webfonts/|url("/vendor/webfonts/|g' "$FA_CSS_PATH"
fi

echo "Font Awesome paths fixed successfully"