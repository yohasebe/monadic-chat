#!/bin/bash

echo "Rebuilding help database..."

# Export OpenAI API key if needed
export OPENAI_API_KEY=$OPENAI_API_KEY

# Run the Ruby script directly with --recreate flag
cd /Users/yohasebe/code/monadic-chat
ruby docker/services/ruby/scripts/utilities/process_documentation.rb --recreate

echo "Done!"