#!/bin/bash

# E2E Test Runner Script
# This script ensures all prerequisites are met before running E2E tests

set -e

# Track which containers we started
STARTED_CONTAINERS=()
# Initialize variables
NEED_TO_RESTART_CONTAINER=false
SERVER_PID=""

# Cleanup function
cleanup() {
  local exit_code=$?
  
  # Cleanup server if we started it
  if [ ! -z "$SERVER_PID" ]; then
    echo ""
    echo "Stopping test server..."
    kill $SERVER_PID 2>/dev/null || true
    sleep 2
    kill -9 $SERVER_PID 2>/dev/null || true
    echo "Server stopped"
  fi
  
  # Restart Ruby container if we stopped it
  if [ "$NEED_TO_RESTART_CONTAINER" = true ]; then
    echo "Restarting Ruby container..."
    docker start monadic-chat-ruby-container > /dev/null 2>&1 || true
    echo "Ruby container restarted"
  fi
  
  # Optional: Stop containers we started
  if [ "${STOP_CONTAINERS_AFTER_TESTS}" = "true" ] && [ ${#STARTED_CONTAINERS[@]} -gt 0 ]; then
    echo ""
    echo "Stopping containers that were started for tests..."
    for container in "${STARTED_CONTAINERS[@]}"; do
      case $container in
        "python")
          docker stop monadic-chat-python-container > /dev/null 2>&1 || true
          ;;
        "pgvector")
          docker stop monadic-chat-pgvector-container > /dev/null 2>&1 || true
          ;;
        "selenium")
          docker stop monadic-chat-selenium-container > /dev/null 2>&1 || true
          ;;
      esac
    done
    echo "Containers stopped"
  fi
  
  exit $exit_code
}

# Set up trap for cleanup on exit
trap cleanup EXIT INT TERM

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
# E2E tests need all containers except Ruby (which runs locally)
CONTAINERS_NEEDED=("python" "pgvector" "selenium")
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
  
  # Get compose file paths
  COMPOSE_FILE="$PROJECT_ROOT/docker/services/compose.yml"
  PROJECT_DIR="$PROJECT_ROOT/docker"
  
  for container in "${MISSING_CONTAINERS[@]}"; do
    case $container in
      "python")
        echo "   Starting python container..."
        # Try to start existing container first
        if docker start monadic-chat-python-container 2>/dev/null; then
          echo "   ✓ Started existing python container"
          STARTED_CONTAINERS+=("python")
        else
          # If container doesn't exist, create it using docker compose
          echo "   Creating new python container..."
          if docker compose --project-directory "$PROJECT_DIR" -f "$COMPOSE_FILE" -p 'monadic-chat' up -d python_service; then
            echo "   ✓ Created and started python container"
            STARTED_CONTAINERS+=("python")
          else
            echo "   ✗ Failed to start python container"
            exit 1
          fi
        fi
        ;;
      "pgvector")
        echo "   Starting pgvector container..."
        # Try to start existing container first
        if docker start monadic-chat-pgvector-container 2>/dev/null; then
          echo "   ✓ Started existing pgvector container"
          STARTED_CONTAINERS+=("pgvector")
        else
          # If container doesn't exist, create it using docker compose
          echo "   Creating new pgvector container..."
          if docker compose --project-directory "$PROJECT_DIR" -f "$COMPOSE_FILE" -p 'monadic-chat' up -d pgvector_service; then
            echo "   ✓ Created and started pgvector container"
            STARTED_CONTAINERS+=("pgvector")
          else
            echo "   ✗ Failed to start pgvector container"
            exit 1
          fi
        fi
        ;;
      "selenium")
        echo "   Starting selenium container..."
        # Try to start existing container first
        if docker start monadic-chat-selenium-container 2>/dev/null; then
          echo "   ✓ Started existing selenium container"
          STARTED_CONTAINERS+=("selenium")
        else
          # If container doesn't exist, create it using docker compose
          echo "   Creating new selenium container..."
          if docker compose --project-directory "$PROJECT_DIR" -f "$COMPOSE_FILE" -p 'monadic-chat' up -d selenium_service; then
            echo "   ✓ Created and started selenium container"
            STARTED_CONTAINERS+=("selenium")
          else
            echo "   ✗ Failed to start selenium container"
            exit 1
          fi
        fi
        ;;
    esac
  done
  
  # Wait for containers to be ready
  echo "   Waiting for containers to be ready..."
  
  # Wait for pgvector PostgreSQL to be ready if it was started
  if [[ " ${MISSING_CONTAINERS[@]} " =~ " pgvector " ]]; then
    echo "   Waiting for PostgreSQL to be ready..."
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if docker exec monadic-chat-pgvector-container pg_isready -U postgres > /dev/null 2>&1; then
        echo "   ✓ PostgreSQL is ready!"
        break
      fi
      attempt=$((attempt + 1))
      if [ $attempt -eq $max_attempts ]; then
        echo "   ✗ PostgreSQL did not become ready in time"
        echo "   Note: PDF Navigator and Monadic Help tests may fail"
      else
        echo -n "."
        sleep 1
      fi
    done
    echo ""
  fi
  
  # Wait for selenium to be ready if it was started
  if [[ " ${MISSING_CONTAINERS[@]} " =~ " selenium " ]]; then
    echo "   Waiting for Selenium to be ready..."
    max_attempts=20
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if curl -s http://localhost:4444/wd/hub/status > /dev/null 2>&1; then
        echo "   ✓ Selenium is ready!"
        break
      fi
      attempt=$((attempt + 1))
      if [ $attempt -eq $max_attempts ]; then
        echo "   ✗ Selenium did not become ready in time"
        echo "   Note: Visual Web Explorer and Mermaid Grapher tests may fail"
      else
        echo -n "."
        sleep 1
      fi
    done
    echo ""
  fi
  
  # General wait for other containers
  sleep 2
  
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
  
  # Load environment variables from config file if it exists
  CONFIG_FILE="$HOME/monadic/config/env"
  if [ -f "$CONFIG_FILE" ]; then
    echo "   Loading configuration from $CONFIG_FILE..."
    set -a  # automatically export all variables
    source "$CONFIG_FILE"
    set +a
  fi
  
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
    "PERPLEXITY_API_KEY:Perplexity"
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

# Determine which tests to run based on arguments
TEST_TARGET=$1
TEST_PROVIDER=$2

echo ""
echo "Running E2E tests..."
echo "===================="

SUM_FMT="--format documentation"
if [ "$SUMMARY_ONLY" = "1" ]; then
  SUM_FMT="--format progress"
fi
SUM_ARGS="$SUM_FMT"

case "$TEST_TARGET" in
  "jupyter_notebook"|"jupyter_grok")
    echo "Running Jupyter (local ops) E2E..."
    bundle exec rspec spec/e2e/jupyter_notebook_grok_spec.rb $SUM_ARGS --no-fail-fast
    ;;
  "monadic_context")
    echo "Running Monadic context display E2E..."
    bundle exec rspec spec/e2e/monadic_context_display_spec.rb $SUM_ARGS --no-fail-fast
    ;;
  ""|"all")
    echo "Running E2E wiring tests (no real APIs)..."
    bundle exec rspec spec/e2e/jupyter_notebook_grok_spec.rb spec/e2e/monadic_context_display_spec.rb $SUM_ARGS --no-fail-fast
    ;;
  *)
    echo "No E2E tests for target '$TEST_TARGET'."
    echo "Real API scenarios moved to spec_api (see Rake tasks: spec_api:*)."
    ;;
esac

echo ""
echo "E2E tests completed!"
# Cleanup will be handled by the trap function
