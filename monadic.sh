#!/bin/bash

# Define the path to the root directory
ROOT_DIR=$(dirname "$0")

# Define the path to the home directory
HOME_DIR=$(eval echo ~${SUDO_USER})

# Define the full path to docker-compose
if [[ "$(uname -s)" == "Darwin"* ]]; then
  DOCKER=/usr/local/bin/docker
else
  DOCKER=docker
fi

# Define the paths to the support scripts
MAC_SCRIPT="${ROOT_DIR}/docker/support_scripts/mac-start-docker.sh"
WSL2_SCRIPT="${ROOT_DIR}/docker/support_scripts/wsl2-start-docker.sh"
LINUX_SCRIPT="${ROOT_DIR}/docker/support_scripts/linux-start-docker.sh"

# check if HOME_DIR/data/.env exists and create it if not
if [ ! -f "$HOME_DIR/monadic/.env" ]; then
  touch "$HOME_DIR/monadic/.env"
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
    *)
      echo "Unsupported operating system: $(uname -s)"
      exit 1
      ;;
  esac
}

function shutdown_docker {
  case "$(uname -s)" in
    Darwin)
      # macOS
      killall Docker
      ;;
    Linux)
      # Linux
      if grep -q microsoft /proc/version; then
        # WSL2
        powershell.exe -Command "Stop-Process -Name 'Docker Desktop' -Force"
      else
        # Native Linux
        sudo systemctl stop docker
      fi
      ;;
    *)
      echo "Unsupported operating system: $(uname -s)"
      exit 1
      ;;
  esac
}

function build_docker_compose {
  start_docker
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" build
  echo "Monadic Chat Docker image has been built successfully!"
}

function start_docker_compose {
  start_docker
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" up -d

  echo "Monadic Chat has been started"
  echo "Access http://localhost:4567 on your browser"
}

# Define a function to stop Docker Compose
function stop_docker_compose {
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" down
  echo "Monadic Chat has been stopped"
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
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" down

  # Move to `ROOT_DIR` and download the latest version of Monadic Chat 
  cd "$ROOT_DIR" && git pull

  # Build and start the Docker Compose services
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" build

  # Show message to the user
  echo "Monadic Chat has been updated successfully!"
}

# Parse the user command
case "$1" in
  build)
    stop_docker_compose
    build_docker_compose
    ;;
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
    stop_docker_compose
    import_database
    ;;
  export)
    start_docker
    stop_docker_compose
    export_database
    ;;
  update)
    start_docker
    update_monadic
    ;;
  shutdown)
    shutdown_docker
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|update}"
    exit 1
    ;;
esac

exit 0
