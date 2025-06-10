#!/bin/bash

echo "=== Direct dvisvgm Test ==="

# Use the existing DVI file from the failed attempt
cd ~/monadic/data

# Find the most recent concept DVI file
DVI_FILE=$(ls -t concept_3d_math_plot_*.dvi 2>/dev/null | head -1)

if [ -z "$DVI_FILE" ]; then
    echo "No DVI file found"
    exit 1
fi

echo "Found DVI file: $DVI_FILE"
BASE_NAME="${DVI_FILE%.dvi}"

# Try to convert it directly
echo "Converting to SVG..."
docker exec monadic-chat-python-container bash -c "
cd /monadic/data
echo 'Running dvisvgm...'
dvisvgm --verbosity=3 --bbox=min --precision=3 --encoding=utf8 ${DVI_FILE} -o ${BASE_NAME}_test.svg 2>&1
echo 'Exit code:' \$?
ls -la ${BASE_NAME}_test.svg 2>/dev/null || echo 'SVG not created'
"

# Check result
if [ -f "${HOME}/monadic/data/${BASE_NAME}_test.svg" ]; then
    echo "✅ SUCCESS: SVG created"
    ls -la "${HOME}/monadic/data/${BASE_NAME}_test.svg"
else
    echo "❌ FAILED: SVG not created"
fi