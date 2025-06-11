#!/bin/bash
# Development script to build help database with port forwarding

echo "Setting up port forwarding for development..."

# Kill any existing port forward
pkill -f "docker exec.*socat" 2>/dev/null || true

# Start port forwarding in background
docker exec -d monadic-chat-pgvector-container sh -c "apt-get update && apt-get install -y socat && socat TCP-LISTEN:5432,fork TCP:localhost:5432" 2>/dev/null || true

# Alternative: Use docker run with port mapping
echo "Creating temporary port forward..."
docker run -d --rm \
  --name pgvector-port-forward \
  --network container:monadic-chat-pgvector-container \
  -p 5432:5432 \
  alpine/socat \
  TCP-LISTEN:5432,fork TCP-CONNECT:localhost:5432 2>/dev/null || true

# Give it a moment to start
sleep 2

# Now run the Ruby script with proper environment variables
echo "Running documentation processor..."
POSTGRES_HOST=localhost POSTGRES_PORT=5432 IN_CONTAINER=false ruby /Users/yohasebe/code/monadic-chat/docker/services/ruby/scripts/utilities/process_documentation.rb "$@"

# Stop the port forward
docker stop pgvector-port-forward 2>/dev/null || true

echo "Build complete."