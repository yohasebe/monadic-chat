#!/bin/bash

# Define the path to the root directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. >/dev/null 2>&1 && pwd)"

# Define the paths to the support scripts
MAC_SCRIPT="${ROOT_DIR}/docker/support_scripts/mac-start-docker.sh"
WINDOWS_SCRIPT="${ROOT_DIR}/docker/support_scripts/windows-start-docker.sh"
WSL2_SCRIPT="${ROOT_DIR}/docker/support_scripts/wsl2-start-docker.sh"
LINUX_SCRIPT="${ROOT_DIR}/docker/support_scripts/linux-start-docker.sh"

if [ ! -f "${ROOT_DIR}/.env" ]; then
  touch "${ROOT_DIR}/.env"
fi

function start_docker {
  # Determine the operating system
  case "$(uname -s)" in
    Darwin)
      # macOS
      sh "$MAC_SCRIPT"
      ;;
    Linux)
      # Linux
      if grep -q microsoft /proc/version; then
        # WSL2
        sh "$WSL2_SCRIPT"
      else
        # Native Linux
        sh "$LINUX_SCRIPT"
      fi
      ;;
    CYGWIN*|MINGW32*|MSYS*|MINGW*)
      # Windows
      sh "$WINDOWS_SCRIPT"
      ;;
    *)
      echo "Unsupported operating system: $(uname -s)"
      exit 1
      ;;
  esac
}

# Define a function to start Docker Compose
function start_docker_compose {
  start_docker

  # Build and start the Docker Compose services
  docker-compose -f "$ROOT_DIR/docker-compose.yml" build
  docker-compose -f "$ROOT_DIR/docker-compose.yml" up -d

  # Wait for the services to be up and running
  timeout=15

  while [[ $(docker-compose -f "$ROOT_DIR/docker-compose.yml" ps -q | xargs docker inspect --format '{{.State.Running}}') == "true" ]]; do
    sleep 1
    timeout=$((timeout-1))
    if [[ $timeout -eq 0 ]]; then
      break
    fi
  done

  sleep 6

  # Open the default browser and access "http://localhost:4567"
  if which xdg-open > /dev/null 2>&1; then
    xdg-open "http://localhost:4567" > /dev/null 2>&1
  elif which gnome-open > /dev/null 2>&1; then
    gnome-open "http://localhost:4567" > /dev/null 2>&1
  elif which open > /dev/null 2>&1; then
    open "http://localhost:4567" > /dev/null 2>&1
  elif which start > /dev/null 2>&1; then
    start "http://localhost:4567" > /dev/null
  else
    echo "Please open your browser and access http://localhost:4567"
  fi
}

# Define a function to stop Docker Compose
function stop_docker_compose {
  # Stop the Docker Compose services
  docker-compose -f "$ROOT_DIR/docker-compose.yml" down
}

# Define a function to restart Docker Compose
function restart_docker_compose {
  stop_docker_compose
  start_docker_compose
}

# Define a function to import the database contents from an external file
function import_database {
  sh "${ROOT_DIR}/docker/support_scripts/import_vector_db.sh"
}

# Define a function to export the database contents to an external file
function export_database {
  sh "${ROOT_DIR}/docker/support_scripts/export_vector_db.sh"
}

# Download the latest version of Monadic Chat and rebuild the Docker image
function update_monadic {
  # Stop the Docker Compose services
  docker-compose -f "$ROOT_DIR/docker-compose.yml" down

    # Move to `ROOT_DIR` and download the latest version of Monadic Chat 
    cd "$ROOT_DIR" && git pull

    # Build and start the Docker Compose services
    docker-compose -f "$ROOT_DIR/docker-compose.yml" build

    # Show message to the user
    echo "Monadic Chat has been updated successfully!"
  }

# Parse the user command
case "$1" in
  start)
    start_docker_compose
    ;;
  stop)
    stop_docker_compose
    ;;
  restart)
    restart_docker_compose
    ;;
  import)
    start_docker
    import_database
    ;;
  export)
    start_docker
    export_database
    ;;
  update)
    start_docker
    update_monadic
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|update|import|export}"
    exit 1
    ;;
esac

exit 0
