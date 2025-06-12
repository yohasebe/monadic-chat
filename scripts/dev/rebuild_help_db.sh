#!/bin/bash

echo "Rebuilding help database..."

# Export OpenAI API key if needed
export OPENAI_API_KEY=$OPENAI_API_KEY

# Run the Ruby script directly with --recreate flag
# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
ruby docker/services/ruby/scripts/utilities/process_documentation.rb --recreate

echo "Done!"