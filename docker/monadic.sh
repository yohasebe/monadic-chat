#!/bin/bash

# add /usr/local/bin to the PATH
export PATH=$PATH:/usr/local/bin

export SELENIUM_IMAGE="selenium/standalone-chrome:latest"
# export SELENIUM_IMAGE="seleniarm/standalone-chromium:123.0"

export MONADIC_VERSION=0.8.3

export HOST_OS=$(uname -s)

# Define the path to the root directory
ROOT_DIR=$(dirname "$0")

# Define the path to the home directory
HOME_DIR=$(eval echo ~${SUDO_USER})

# Define the full path to docker-compose
if [[ "$(uname -s)" == "Darwin"* ]]; then
  DOCKER=/usr/local/bin/docker
  if [[ $(uname -m) == "arm64" ]]; then
    export SELENIUM_IMAGE="seleniarm/standalone-chromium:latest"
    # export SELENIUM_IMAGE="seleniarm/standalone-chromium:123.0"
  fi
else
  DOCKER=docker
fi

# Define the paths to the support scripts
MAC_SCRIPT="${ROOT_DIR}/services/support_scripts/mac-start-docker.sh"
WSL2_SCRIPT="${ROOT_DIR}/services/support_scripts/wsl2-start-docker.sh"
LINUX_SCRIPT="${ROOT_DIR}/services/support_scripts/linux-start-docker.sh"

function set_docker_compose() {
  # Check if there are user compose files
  local home_paths=("$HOME_DIR/monadic/data/services" "~/monadic/data/services")

  # expand each path
  for i in "${!home_paths[@]}"; do
    home_paths[$i]=$(eval echo "${home_paths[$i]}")
  done

  # if $HOME_DIR and ~ are the same, remove ~
  if [ "${home_paths[0]}" == "${home_paths[1]}" ]; then
    unset home_paths[1]
  fi
  # also, remove non-existent paths and empty string
  home_paths=($(echo "${home_paths[@]}" | tr ' ' '\n' | sort -u | grep -v '^$' | xargs))

  # check home_paths and remove redundant paths
  local compose_user=""
  CONTAINERS=()
  for home_path in "${home_paths[@]}"; do
    compose_user+=$(find "$home_path" -name "compose.yml" 2>/dev/null | awk '{print "  - "$1}')
    COMPOSE_USER_LIST+=($(find "$home_path" -name "compose.yml" 2>/dev/null | awk -F/ '{print $NF}' | awk -F- '{print $1}'))
  done

  # If COMPOSE_USER is empty, use default compose file
  if [ -z "$compose_user" ]; then
    COMPOSE_MAIN="$ROOT_DIR/services/compose.yml"
  else
    local compose_file_contents=$(cat <<EOF
include:
  - $ROOT_DIR/services/ruby/compose.yml
  - $ROOT_DIR/services/pgvector/compose.yml
  - $ROOT_DIR/services/python/compose.yml
  - $ROOT_DIR/services/selenium/compose.yml
$compose_user

networks:
  monadic-chat-network:
    driver: bridge

volumes:
  data:
EOF
)
    echo "$compose_file_contents" > "$HOME_DIR/monadic/data/compose.yml"
    # wait for the file to be created
    sleep 1
    COMPOSE_MAIN="$HOME_DIR/monadic/data/compose.yml"
  fi
}

set_docker_compose

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

build_docker_compose() {
  remove_containers
  set_docker_compose

  # docker compose -f "$COMPOSE_MAIN" build --no-cache
  docker compose -f "$COMPOSE_MAIN" build --no-cache

  docker tag yohasebe/monadic-chat:$MONADIC_VERSION yohasebe/monadic-chat:latest
  # echo [HTML]: "<p>Monadic Chat $MONADIC_VERSION is tagged 'latest'</p>"

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
  echo "[HTML]: <p>Monadic Chat $MONADIC_VERSION <=> Monadic Chat Image $MONADIC_CHAT_IMAGE_TAG</p>"

  # check if MONADIC_CHAT_IMAGE_TAG includes the same as MONADIC_VERSION
  if [[ "$MONADIC_CHAT_IMAGE_TAG" != *"$MONADIC_VERSION"* ]]; then

    remove_containers

    # if image tag is "None", build the image
    if [ "$MONADIC_CHAT_IMAGE_TAG" == "None" ]; then
      echo "[HTML]: <p>Monadic Chat image does not exist. Building Monadic Chat image . . .</p>"
    else
      echo "[HTML]: <p>Monadic Chat image is outdated. Building Monadic Chat image . . .</p>"
    fi
    $DOCKER compose -f "$COMPOSE_MAIN" down

    build_docker_compose
  else
    echo "[HTML]: <p>Monadic Chat image is up-to-date.</p>"
  fi

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images

  images=("yohasebe/monadic-chat")

  all_images_exist=true
  all_containers_exist=true

  for image in "${images[@]}"; do
    if ! $DOCKER images | grep -q "$image"; then
      # echo "[HTML]: <p>Image not found: $image</p>"
      all_images_exist=false
      break
    fi
  done

  for CONTAINERS in "${containers[@]}"; do
    if ! $DOCKER container ls --all | grep -q "$container"; then
      # echo "[HTML]: <p>Container not found: $container</p>"
      all_containers_exist=false
      break
    fi
  done

  if $all_images_exist; then
    if $all_containers_exist; then
      echo "[HTML]: <p>Monadic Chat image and container found.</p>"
      sleep 1
      echo "[HTML]: <p>Starting Monadic Chat container . . .</p>"
      for container in "${CONTAINERS[@]}"; do
        start_container "$container"
      done
    else
      echo "[HTML]: <p>Setting up Monadic Chat container. Please wait . . .</p>"
      $DOCKER compose -f "$COMPOSE_MAIN" -p "monadic-chat-container" up -d
    fi
  else
    echo "[IMAGE NOT FOUND]"
    sleep 1
    echo "[HTML]: <p>Building Monadic Chat Docker image. This may take a while . . .</p>"
    build_docker_compose
    echo "[HTML]: <p>Starting Monadic Chat Docker image . . .</p>"
    $DOCKER compose -f "$COMPOSE_MAIN" -p "monadic-chat-container" up -d

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
  $DOCKER compose -f "$COMPOSE_MAIN" down

  # Remove specific volumes used by the monadic-chat project
  $DOCKER volume rm monadic-chat-pgvector-data
}

# Define a function to stop Docker Compose
stop_docker_compose() {
  containers=$($DOCKER ps --filter "label=project=monadic-chat" --format "{{.Names}}")
  for container in $containers; do
    stop_container "$container"
  done
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
  $DOCKER compose -f "$COMPOSE_MAIN" down

  # Move to `ROOT_DIR` and download the latest version of Monadic Chat 
  cd "$ROOT_DIR" && git pull origin main

  # Build and start the Docker Compose services
  $DOCKER compose -f "$COMPOSE_MAIN" build --no-cache
}

# Remove the Docker image and container
remove_containers() {
  # Stop the Docker Compose services
  $DOCKER compose -f "$COMPOSE_MAIN" down

  local images=$($DOCKER images --filter "label=project=monadic-chat" --format "{{.Repository}}:{{.Tag}}")
  local containers=$($DOCKER ps --filter "label=project=monadic-chat" --format "{{.Names}}")

  # Remove the Docker images and containers of the monadic-chat project
  for image in $images; do
    remove_image "$image"
  done

  for container in $containers; do
    remove_container "$container"
  done

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
  local project_label="monadic-chat"
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
