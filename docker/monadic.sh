#!/bin/bash

# add /usr/local/bin to the PATH
export PATH=$PATH:/usr/local/bin

export SELENIUM_IMAGE="selenium/standalone-chrome:123.0"
# export SELENIUM_IMAGE="seleniarm/standalone-chromium:123.0"

export MONADIC_VERSION=0.7.9

export HOST_OS=$(uname -s)

# Define the path to the root directory
ROOT_DIR=$(dirname "$0")

# Define the path to the home directory
HOME_DIR=$(eval echo ~${SUDO_USER})

# Define the full path to docker-compose
if [[ "$(uname -s)" == "Darwin"* ]]; then
  DOCKER=/usr/local/bin/docker
  if [[ $(uname -m) == "arm64" ]]; then
    export SELENIUM_IMAGE="seleniarm/standalone-chromium:123.0"
  fi
else
  DOCKER=docker
fi

# Define the paths to the support scripts
MAC_SCRIPT="${ROOT_DIR}/services/support_scripts/mac-start-docker.sh"
WSL2_SCRIPT="${ROOT_DIR}/services/support_scripts/wsl2-start-docker.sh"
LINUX_SCRIPT="${ROOT_DIR}/services/support_scripts/linux-start-docker.sh"

# Function to ensure data directory exists
ensure_data_dir() {
  if [ -f "/.dockerenv" ]; then
    mkdir -p "/monadic/data"
    touch "/monadic/data/.env"
  else
    mkdir -p "$HOME_DIR/monadic/data"
    touch "$HOME_DIR/monadic/data/.env"
  fi
}

# Function to start Docker based on OS
start_docker() {
  case "$(uname -s)" in
    Darwin)
      sh "$MAC_SCRIPT"
      ;;
    Linux)
      if grep -q microsoft /proc/version; then
        sh "$WSL2_SCRIPT"
      else
        sh "$LINUX_SCRIPT"
      fi
      ;;
    *)
      echo "Unsupported operating system: $(uname -s)" >&2  # Redirect error message to stderr
      exit 1
      ;;
  esac
}

# Function to build Docker Compose
build_docker_compose() {
  remove_containers

  $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" build --no-cache
  # $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" build
  echo [HTML]: "<p>Monadic Chat has been built successfully!</p>"

  $DOCKER  tag yohasebe/monadic-chat:$MONADIC_VERSION yohasebe/monadic-chat:latest
  echo [HTML]: "<p>Monadic Chat $MONADIC_VERSION is tagged 'latest'</p>"

  remove_project_dangling_images
}

# Function to start Docker Compose
start_docker_compose() {
  # get yohasebe/monadic-chat image tag
  MONADIC_CHAT_IMAGE_TAG=$($DOCKER images | grep "yohasebe/monadic-chat" | awk '{print $2}')
  MONADIC_CHAT_IMAGE_TAG=$(echo $MONADIC_CHAT_IMAGE_TAG | tr -d '\r')
  MONADIC_CHAT_IMAGE_TAG=$(echo $MONADIC_CHAT_IMAGE_TAG | sed 's/latest//g')

  if [ -z "$MONADIC_CHAT_IMAGE_TAG" ]; then
    MONADIC_CHAT_IMAGE_TAG="None"
  fi
  echo "[HTML]: <p>Monadic Chat version: $MONADIC_VERSION</p>"
  echo "[HTML]: <p>Current Monadic Chat Image: $MONADIC_CHAT_IMAGE_TAG</p>"

  # check if MONADIC_CHAT_IMAGE_TAG includes the same as MONADIC_VERSION
  if [[ "$MONADIC_CHAT_IMAGE_TAG" != *"$MONADIC_VERSION"* ]]; then

    remove_containers

    # if image tag is "None", build the image
    if [ "$MONADIC_CHAT_IMAGE_TAG" == "None" ]; then
      echo "[HTML]: <p>Monadic Chat image does not exist. Building Monadic Chat image . . .</p>"
    else
      echo "[HTML]: <p>Monadic Chat image is outdated. Building Monadic Chat image . . .</p>"
    fi
    $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" down

    build_docker_compose
  else
    echo "[HTML]: <p>Monadic Chat image is up-to-date.</p>"
  fi

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images

  images=("yohasebe/monadic-chat")
  containers=("monadic-chat-container" "python-container" "selenium-container" "pgvector-container")

  all_images_exist=true
  all_containers_exist=true

  for image in "${images[@]}"; do
    if ! $DOCKER images | grep -q "$image"; then
      all_images_exist=false
      break
    fi
  done

  for container in "${containers[@]}"; do
    if ! $DOCKER container ls --all | grep -q "$container"; then
      all_containers_exist=false
      break
    fi
  done

  if $all_images_exist; then
    if $all_containers_exist; then
      echo "[HTML]: <p>Monadic Chat image and container found.</p>"
      sleep 1
      echo "[HTML]: <p>Starting Monadic Chat container . . .</p>"
      start_container monadic-chat-pgvector-container
      start_container monadic-chat-selenium-container
      start_container monadic-chat-python-container
      start_container monadic-chat-ruby-container
    else
      echo "[HTML]: <p>Monadic Chat Docker image exists. Setting up Monadic Chat container. Please wait . . .</p>"
      $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" -p "monadic-chat-container" up -d
    fi
  else
    echo "[IMAGE NOT FOUND]"
    sleep 1
    echo "[HTML]: <p>Building Monadic Chat Docker image. This may take a while . . .</p>"
    build_docker_compose
    echo "[HTML]: <p>Starting Monadic Chat Docker image . . .</p>"
    $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" -p "monadic-chat-container" up -d

    # Periodically check if the image is ready
    while true; do
      if $DOCKER images | grep -q "monadic-chat"; then
        break
      fi
      sleep 1
    done
  fi

  echo "[SERVER STARTED]"
}

# Function to stop Docker Compose
down_docker_compose() {
  $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" down

  # Remove specific volumes used by the monadic-chat project
  $DOCKER volume rm monadic-chat-pgvector-data
}

# Define a function to stop Docker Compose
stop_docker_compose() {
  stop_container monadic-chat-ruby-container
  stop_container monadic-chat-pgvector-container
  stop_container monadic-chat-python-container
  stop_container monadic-chat-selenium-container
}

# Function to start a container
start_container() {
  $DOCKER container start "$1" >/dev/null
}

# Function to stop a container
stop_container() {
  $DOCKER container stop -t 0 "$1" >/dev/null
}

# Define a function to import the database contents from an external file
import_database() {
  sh "${ROOT_DIR}/services/support_scripts/import_vector_db.sh"
}

# Define a function to export the database contents to an external file
export_database() {
  sh "${ROOT_DIR}/services/support_scripts/export_vector_db.sh"
}

# Download the latest version of Monadic Chat and rebuild the Docker image
update_monadic() {
  # Stop the Docker Compose services
  $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" down

  # Move to `ROOT_DIR` and download the latest version of Monadic Chat 
  cd "$ROOT_DIR" && git pull origin main

  # Build and start the Docker Compose services
  $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" build --no-cache
}

# Remove the Docker image and container
remove_containers() {
  # Stop the Docker Compose services
  $DOCKER compose -f "$ROOT_DIR/services/docker-compose.yml" down

  # Remove the Docker images and containers of older versions
  remove_image yohasebe/monadic-chat
  remove_image yohasebe/python
  remove_image yohasebe/pgvector
  remove_image yohasebe/selenium

  remove_container monadic-chat-ruby-container
  remove_container monadic-chat-pgvector-container
  remove_container monadic-chat-python-container
  remove_container monadic-chat-selenium-container

  # ↓ remove legacy containers
  remove_container monadic-chat-web-container
  remove_container monadic-chat-container
  # ↑ remove legacy containers

  remove_project_dangling_images
  remove_volume monadic-chat-pgvector-data
}

# Function to remove images containing the string in $1
remove_image() {
  images=$($DOCKER images --format "{{.Repository}}:{{.Tag}}" | grep "$1")
  for image in $images; do
    $DOCKER rmi -f "$image" >/dev/null
  done
}

# Function to remove a container
remove_container() {
  if $DOCKER container ls --all | grep -q "$1"; then
    $DOCKER container rm -f "$1" >/dev/null
  fi
}

# Function to remove a volume
remove_volume() {
  if $DOCKER volume ls | grep -q "$1"; then
    $DOCKER volume rm "$1" >/dev/null
  fi
}

# Function to remove project-specific dangling images
remove_project_dangling_images() {
  $DOCKER images -f "dangling=true" -f "label=project=$project_label" --format "{{.ID}}" | xargs -r docker rmi -f
}

# Function to remove older images
remove_older_images() {
  local image_name="$1"
  local latest_image_id=$($DOCKER images --format "{{.ID}}" "$image_name:$MONADIC_VERSION")
  $DOCKER images --format "{{.ID}} {{.Repository}}:{{.Tag}}" "$image_name" | grep -v "$latest_image_id" | awk '{print $1}' | xargs -r $DOCKER rmi -f
}

# Parse the user command
case "$1" in
  build)
    ensure_data_dir
    start_docker
    build_docker_compose
    # check if the above command succeeds
    if $DOCKER images | grep -q "monadic-chat"; then
      echo "[HTML]: <p>Monadic Chat has been built successfully! Press <b>Start</b> button to initialize the server.</p>"
    else
      echo "[HTML]: <p>Monadic Chat has failed to build. Please try <b>Rebuild</b>.</p>"
    fi
    ;;
  start)
    ensure_data_dir
    start_docker
    start_docker_compose
    echo "[SERVER STARTED]"
    ;;
  stop)
    stop_docker_compose
    echo "[HTML]: <p>Monadic Chat has been stopped.</p>"
    ;;
  restart)
    stop_docker_compose
    start_docker_compose
    sleep 1
    echo "[SERVER STARTED]"
    ;;
  import)
    start_docker
    stop_docker_compose
    import_database
    ;;
  export)
    start_docker
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
    echo "[HTML]: <p>Containers and images have been removed successfully.</p><p>Now you can quit Monadic Chat and uninstall the app safely.</p>"
    ;;
  *)
    echo "Usage: $0 {build|start|stop|restart|update|remove}}" >&2  # Redirect usage message to stderr
    exit 1
    ;;
esac

exit 0
