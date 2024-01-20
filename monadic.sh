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

# check if ${ROOT_DIR}/data/.env exists and create it if not
if [ ! -f "${ROOT_DIR}/data/.env" ]; then
  touch "${ROOT_DIR}/data/.env"
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

function build_docker_compose {
  start_docker
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" build --no-cache
}

function start_docker_compose {
  start_docker

  # Check if the Docker image and container exist
  if $DOCKER images | grep -q "monadic-chat"; then
    if $DOCKER container ls --all | grep -q "monadic-chat"; then
      echo "[CONTAINERS FOUND]"
      sleep 1
      echo "[HTML]: <p>Starting Monadic Chat container . . .</p>"
      $DOCKER container start monadic-chat-web-container
      $DOCKER container start monadic-chat-pgvector-container
    else
      echo "[HTML]: <p>Monadic Chat Docker image exists. Building Monadic Chat container . . .</p>"
      $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" up -d
    fi
  else
    echo "[IMAGE NOT FOUND]"
    sleep 1
    echo "[HTML]: <p>Building Monadic Chat Docker image. This may take a while . . .</p>"
    build_docker_compose
    echo "[HTML]: <p>Starting Monadic Chat Docker image . . .</p>"
    $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" -p "monadic-chat-container" up -d

    # periodically check if the image is ready
    while true; do
      if $DOCKER images | grep -q "monadic-chat"; then
        break
      fi
      sleep 1
    done
  fi
}

function down_docker_compose {
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" down
  # remove unused docker volumes created by docker-compose
  $DOCKER volume prune -f
}

# Define a function to stop Docker Compose
function stop_docker_compose {
  $DOCKER container stop monadic-chat-web-container >/dev/null
  $DOCKER container stop monadic-chat-pgvector-container >/dev/null
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
  cd "$ROOT_DIR" && git pull origin main

  # Build and start the Docker Compose services
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" build --no-cache
}

# Remove the Docker image and container
function remove_containers {
  # Stop the Docker Compose services
  $DOCKER compose -f "$ROOT_DIR/docker-compose.yml" down

  # Remove the Docker images and volumes
  $DOCKER rmi yohasebe/monadic-chat
  $DOCKER rmi ankane/pgvector
  $DOCKER volume rm monadic-chat-pgvector-data
}

# Parse the user command
case "$1" in
  build)
    start_docker
    start_docker_compose
    build_docker_compose
    echo "[HTML]: <p>Monadic Chat Docker image has been built successfully.</p>"
    echo "[HTML]: <p>Press <b>Start</b> to initialize the server.</p>"
    ;;
  start)
    start_docker_compose
    echo "[HTML]: <p>Monadic Chat has been started. Press <b>Open Browser</b> button.</p>"
    ;;
  stop)
    stop_docker_compose
    echo "[HTML]: <p>Monadic Chat has been stopped.</p>"
    ;;
  restart)
    stop_docker_compose
    start_docker_compose
    echo "[HTML]: <p>Monadic Chat has been restarted.</p><p>Press <b>Open Browser</b> button.</p>"
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
    echo "[HTML]: <p>Monadic Chat has been updated successfully!</p>"
    ;;
  down)
    start_docker
    down_docker_compose
    echo "[HTML]: <p>Monadic Chat has been stopped and containers have been removed</p>"
    ;;
  remove)
    start_docker
    remove_containers
    echo "[HTML]: <p>Containers and images have been removed successfully!</p><p>Now you can quit Monadic Chat and unstall the app safely.</p>"
    ;;
  *)
    echo "Usage: $0 {build|start|stop|restart|update|remove}}"
    exit 1
    ;;
esac

exit 0
