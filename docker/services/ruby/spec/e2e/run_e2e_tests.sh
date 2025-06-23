#!/bin/bash

# E2E Test Runner Script
# This script ensures all prerequisites are met before running E2E tests

set -e

# Get the absolute path to the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# From docker/services/ruby/spec/e2e/ we need to go up 5 levels to reach project root
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../../../.." && pwd )"

# Debug info
if [ ! -f "$PROJECT_ROOT/docker/monadic.sh" ]; then
  echo "ERROR: monadic.sh not found at: $PROJECT_ROOT/docker/monadic.sh"
  echo "Script directory: $SCRIPT_DIR"
  echo "Calculated project root: $PROJECT_ROOT"
  echo "Looking for monadic.sh in parent directories..."
  ls -la "$SCRIPT_DIR/../../../../.."
  exit 1
fi

echo "E2E Test Setup"
echo "=============="

# Check if Docker containers are running
echo "1. Checking Docker containers..."
# For Code Interpreter tests, we only need Python container
# pgvector is optional (needed for PDF Navigator and Monadic Help)
CONTAINERS_NEEDED=("python")
MISSING_CONTAINERS=()

for container in "${CONTAINERS_NEEDED[@]}"; do
  if ! docker ps | grep -q "monadic-chat-${container}-container"; then
    MISSING_CONTAINERS+=($container)
  fi
done

if [ ${#MISSING_CONTAINERS[@]} -ne 0 ]; then
  echo "   ✗ Missing containers: ${MISSING_CONTAINERS[*]}"
  
  # Check if pgvector is having issues (exit code 137)
  if docker ps -a | grep "monadic-chat-pgvector-container" | grep -q "Exited (137)"; then
    echo "   ⚠ pgvector container exited with code 137 (likely OOM)"
    echo "   Note: PDF Navigator tests will be skipped"
  fi
  
  # Only start the specific containers we need
  echo "   Starting required containers..."
  for container in "${MISSING_CONTAINERS[@]}"; do
    case $container in
      "python")
        docker start monadic-chat-python-container 2>/dev/null || \
          docker run -d --name monadic-chat-python-container \
            --network monadic-chat-network \
            -v ~/monadic/data:/monadic/data \
            yohasebe/python
        ;;
    esac
  done
  
  # Wait for containers to be ready
  echo "   Waiting for containers to be ready..."
  sleep 5
  
  # Verify containers are now running
  echo "   Verifying container status..."
  for container in "${CONTAINERS_NEEDED[@]}"; do
    if docker ps | grep -q "monadic-chat-${container}-container"; then
      echo "   ✓ ${container} container is running"
    else
      echo "   ✗ ${container} container failed to start"
      # Don't exit if it's just pgvector having issues
      if [ "$container" != "pgvector" ]; then
        exit 1
      fi
    fi
  done
else
  echo "   ✓ All required containers are running"
fi

# Check if server is already running  
echo "2. Checking server status..."

# First check if it's the Ruby container on 4567
if lsof -i :4567 | grep -q "com.docke"; then
  echo "   ⚠ Port 4567 is used by Docker (Ruby container)"
  echo "   For E2E tests, we need to run the server locally"
  
  # Stop the Ruby container temporarily
  echo "   Stopping Ruby container..."
  docker stop monadic-chat-ruby-container > /dev/null 2>&1 || true
  sleep 2
  
  NEED_TO_RESTART_CONTAINER=true
else
  NEED_TO_RESTART_CONTAINER=false
fi

# Now check if local server is running
if curl -s http://localhost:4567/health > /dev/null 2>&1; then
  echo "   ✓ Local server is already running"
  SERVER_PID=""
else
  echo "   Starting local server..."
  
  # Start server in background (stay in docker/services/ruby)
  bundle exec rackup config.ru -p 4567 > /tmp/monadic_server.log 2>&1 &
  SERVER_PID=$!
  
  # Wait for server to start
  echo "   Waiting for server to be ready..."
  for i in {1..30}; do
    if curl -s http://localhost:4567/health > /dev/null 2>&1; then
      echo "   ✓ Server is ready!"
      break
    fi
    if [ $i -eq 30 ]; then
      echo "   ✗ Server failed to start after 30 seconds"
      echo "   Check /tmp/monadic_server.log for errors"
      tail -20 /tmp/monadic_server.log
      if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
      fi
      exit 1
    fi
    sleep 1
    echo -n "."
  done
  echo ""
fi

# Check API keys
echo "3. Checking API keys..."
if [ -f ~/monadic/config/env ]; then
  # Check all provider API keys
  PROVIDERS=(
    "OPENAI_API_KEY:OpenAI"
    "ANTHROPIC_API_KEY:Claude"
    "GEMINI_API_KEY:Gemini"
    "XAI_API_KEY:Grok"
    "MISTRAL_API_KEY:Mistral"
    "COHERE_API_KEY:Cohere"
    "DEEPSEEK_API_KEY:DeepSeek"
    "TAVILY_API_KEY:Tavily (Web Search)"
  )
  
  FOUND_KEYS=0
  for provider_info in "${PROVIDERS[@]}"; do
    KEY_NAME="${provider_info%%:*}"
    PROVIDER_NAME="${provider_info#*:}"
    if grep -q "^${KEY_NAME}=" ~/monadic/config/env; then
      echo "   ✓ ${PROVIDER_NAME} API key found"
      ((FOUND_KEYS++))
    else
      echo "   ○ ${PROVIDER_NAME} API key not found"
    fi
  done
  
  if [ $FOUND_KEYS -eq 0 ]; then
    echo "   ⚠ No API keys found - tests will be severely limited"
  else
    echo "   Found ${FOUND_KEYS} API key(s) configured"
  fi
else
  echo "   ✗ Config file not found: ~/monadic/config/env"
  echo "   E2E tests require API keys to be configured"
  exit 1
fi

# Run E2E tests
echo ""
echo "Running E2E tests..."
echo "===================="
bundle exec rspec spec/e2e --format documentation --no-fail-fast

# Cleanup
if [ ! -z "$SERVER_PID" ]; then
  echo ""
  echo "Stopping test server..."
  kill $SERVER_PID 2>/dev/null || true
  wait $SERVER_PID 2>/dev/null || true
  echo "Server stopped"
fi

# Restart Ruby container if we stopped it
if [ "$NEED_TO_RESTART_CONTAINER" = true ]; then
  echo "Restarting Ruby container..."
  docker start monadic-chat-ruby-container > /dev/null 2>&1 || true
  echo "Ruby container restarted"
fi

echo ""
echo "E2E tests completed!"