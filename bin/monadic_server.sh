#!/bin/bash

# Navigate to the ruby directory
cd ./docker/services/ruby

# Function to stop Ruby container if running (prevents Docker Desktop crashes)
stop_ruby_container_if_running() {
  local container_name="monadic-chat-ruby-container"

  echo "🔍 Checking Ruby container status..."

  # Check if docker command exists
  if ! command -v docker &> /dev/null; then
    echo "⚠️  Docker command not found - skipping container check"
    return 0
  fi

  # Check if container exists and is running (with timeout)
  local status
  status=$(timeout 5 docker container inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null)

  if [ "$status" == "running" ]; then
    echo "⚠️  Ruby container is running - stopping it to prevent conflicts..."
    timeout 30 docker container stop "$container_name" > /dev/null 2>&1

    # Wait and verify
    sleep 2
    local new_status
    new_status=$(timeout 5 docker container inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null)

    if [ "$new_status" != "running" ]; then
      echo "✅ Ruby container stopped successfully"
    else
      echo "⚠️  Ruby container may still be stopping - waiting..."
      sleep 3
    fi
  else
    echo "✅ Ruby container is not running (status: ${status:-not found})"
  fi
}

# Function to start Docker Desktop if not running (macOS only)
ensure_docker_desktop() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    return 0
  fi

  # Check if Docker is responsive
  if timeout 3 docker version --format '{{.Server.Version}}' > /dev/null 2>&1; then
    echo "✅ Docker Desktop is running"
    return 0
  fi

  echo "🐳 Starting Docker Desktop..."
  open -a Docker

  # Wait for Docker to be ready (max 60 seconds)
  local elapsed=0
  while ! timeout 3 docker version --format '{{.Server.Version}}' > /dev/null 2>&1; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ $((elapsed % 10)) -eq 0 ]; then
      echo "  Waiting for Docker Desktop... (${elapsed}s)"
    fi
    if [ $elapsed -ge 60 ]; then
      echo "❌ Timed out waiting for Docker Desktop"
      return 1
    fi
  done

  echo "✅ Docker Desktop is ready (took ${elapsed}s)"
}

# parse command line argument "start", "debug", "stop", or "restart";

if [ "$1" == "start" ]; then
  stop_ruby_container_if_running
  ./bin/monadic_dev start --daemonize
  echo "Monadic script executed with 'start' argument 🚀"
  echo "Run 'monadic_server.sh stop' to stop the server"
elif [ "$1" == "debug" ]; then
  echo "Starting Monadic server in debug mode 🛑"
  # CRITICAL: Stop Ruby container BEFORE any Ruby/Docker interaction
  stop_ruby_container_if_running
  # Then ensure Docker Desktop is running
  ensure_docker_desktop
  # Now safe to run monadic_dev
  ./bin/monadic_dev start
elif [ "$1" == "stop" ]; then
  ./bin/monadic_dev stop
  echo "Monadic script executed with 'stop' argument 🛑"
elif [ "$1" == "restart" ]; then
  stop_ruby_container_if_running
  ./bin/monadic_dev restart --daemonize
  echo "Monadic script executed with 'restart' argument 🔄"
elif [ "$1" == "export" ]; then
  ./bin/monadic_dev export
elif [ "$1" == "import" ]; then
  ./bin/monadic_dev import
elif [ "$1" == "status" ]; then
  ./bin/monadic_dev status
else
  echo "Usage: monadic_server.sh [start|stop|restart|debug|status|export|import]"
  ./bin/monadic_dev status
fi

