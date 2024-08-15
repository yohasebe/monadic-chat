#!/bin/bash

# Add /usr/local/bin to the PATH
export PATH=$PATH:/usr/local/bin

export SELENIUM_IMAGE="selenium/standalone-chrome:latest"
export MONADIC_VERSION=0.8.4
export HOST_OS=$(uname -s)

# Define the path to the root directory
ROOT_DIR=$(dirname "$0")
HOME_DIR=$(eval echo ~${SUDO_USER})

# Define the full path to docker-compose
DOCKER=$(command -v docker)

if [[ "$HOST_OS" == "Darwin"* && "$(uname -m)" == "arm64" ]]; then
  export SELENIUM_IMAGE="seleniarm/standalone-chromium:latest"
fi

# Define the paths to the support scripts
SCRIPTS=("mac-start-docker.sh" "wsl2-start-docker.sh" "linux-start-docker.sh")

function set_docker_compose() {
  local home_paths=("$HOME_DIR/monadic/data/services" "~/monadic/data/services")
  for i in "${!home_paths[@]}"; do
    home_paths[$i]=$(eval echo "${home_paths[$i]}")
  done

  # Remove non-existent paths and empty strings
  home_paths=($(printf "%s\n" "${home_paths[@]}" | sort -u | grep -v '^$'))

  local compose_user=""
  for home_path in "${home_paths[@]}"; do
    compose_user+=$(find "$home_path" -name "compose.yml" 2>/dev/null | awk '{print "  - "$1}')
  done

  if [[ -z "$compose_user" ]]; then
    COMPOSE_MAIN="$ROOT_DIR/services/compose.yml"
  else
    cat <<EOF > "$HOME_DIR/monadic/data/compose.yml"
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
    COMPOSE_MAIN="$HOME_DIR/monadic/data/compose.yml"
  fi
}

# Function to ensure data directory exists
ensure_data_dir() {
  local data_dir
  if [[ -f "/.dockerenv" ]]; then
    data_dir="/monadic/data"
  else
    data_dir="$HOME_DIR/monadic/data"
  fi
  mkdir -p "$data_dir"
  touch "$data_dir/.env"
}

# Function to start Docker based on OS
start_docker() {
  case "$HOST_OS" in
    Darwin)
      sh "${ROOT_DIR}/services/support_scripts/${SCRIPTS[0]}"
      ;;
    Linux)
      if grep -q microsoft /proc/version; then
        sh "${ROOT_DIR}/services/support_scripts/${SCRIPTS[1]}"
      else
        sh "${ROOT_DIR}/services/support_scripts/${SCRIPTS[2]}"
      fi
      ;;
    *)
      echo "Unsupported operating system: $HOST_OS" >&2
      exit 1
      ;;
  esac
}

# Function to build Docker Compose
build_docker_compose() {
  set_docker_compose
  remove_containers
  $DOCKER compose -f "$COMPOSE_MAIN" build --no-cache
  $DOCKER tag yohasebe/monadic-chat:$MONADIC_VERSION yohasebe/monadic-chat:latest
  remove_project_dangling_images
}

# Function to start Docker Compose
start_docker_compose() {
  set_docker_compose

  # get yohasebe/monadic-chat image tag
  MONADIC_CHAT_IMAGE_TAG=$($DOCKER images | grep "yohasebe/monadic-chat" | awk '{print $2}')
  MONADIC_CHAT_IMAGE_TAG=$(echo $MONADIC_CHAT_IMAGE_TAG | tr -d '\r')
  MONADIC_CHAT_IMAGE_TAG=$(echo $MONADIC_CHAT_IMAGE_TAG | sed 's/latest//g')

  if [ -z "$MONADIC_CHAT_IMAGE_TAG" ]; then
    MONADIC_CHAT_IMAGE_TAG="None"
  fi

  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Monadic Chat app v.$MONADIC_VERSION <=> Monadic Chat image v.$MONADIC_CHAT_IMAGE_TAG</p>"
  fi

  # check if MONADIC_CHAT_IMAGE_TAG includes the same as MONADIC_VERSION
  if [[ "$MONADIC_CHAT_IMAGE_TAG" != *"$MONADIC_VERSION"* ]]; then
    remove_containers
    echo "[HTML]: <p>Building Monadic Chat image . . .</p>"
    $DOCKER compose -f "$COMPOSE_MAIN" down
    build_docker_compose
  elif [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Monadic Chat image is up-to-date.</p>"
  fi

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images

  local images=("yohasebe/monadic-chat")

  for image in "${images[@]}"; do
    if ! $DOCKER images | grep -q "$image"; then
      echo "[IMAGE NOT FOUND]"
      echo "[HTML]: <p>Building Monadic Chat Docker image. This may take a while . . .</p>"
      build_docker_compose
      if [[ "$1" != "silent" ]]; then
        echo "[HTML]: <p>Starting Monadic Chat Docker image . . .</p>"
      fi
      $DOCKER compose -f "$COMPOSE_MAIN" -p "monadic-chat-container" up -d
      break
    fi
  done

  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Setting up Monadic Chat container . . .</p>"
  fi

  $DOCKER compose -f "$COMPOSE_MAIN" -p "monadic-chat-container" up -d

  local containers=$($DOCKER ps --filter "label=project=monadic-chat" --format "{{.Names}}")

  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <hr /><p><b>Running Containers</b></p>"
    echo "[HTML]: <p>You can directly access the containers using the following commands:</p>"
    list_containers="<ul>"
    for container in $containers; do
      list_containers+="<li><i class='fa-solid fa-copy'></i> <code class='command'>docker exec -it $container bash</code></li>"
    done
    list_containers+="</ul>"
    echo "[HTML]: $list_containers<hr />"
  fi
}

# Function to stop Docker Compose
down_docker_compose() {
  $DOCKER compose -f "$COMPOSE_MAIN" down --remove-orphans
}

# Define a function to stop Docker Compose
stop_docker_compose() {
  containers=$($DOCKER ps --filter "label=project=monadic-chat" --format "{{.Names}}")
  for container in $containers; do
    stop_container "$container"
  done
}

# Function to start a container
# start_container() {
#   $DOCKER container start "$1" >/dev/null
# }

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
  $DOCKER compose -f "$COMPOSE_MAIN" down --remove-orphans

  # Move to `ROOT_DIR` and download the latest version of Monadic Chat 
  cd "$ROOT_DIR" && git pull origin main

  # Build and start the Docker Compose services
  $DOCKER compose -f "$COMPOSE_MAIN" build --no-cache
}

# Remove the Docker image and container
remove_containers() {
  set_docker_compose
  # Stop the Docker Compose services
  $DOCKER compose -f "$COMPOSE_MAIN" down --remove-orphans

  local images=$($DOCKER images --filter "label=project=monadic-chat" --format "{{.Repository}}:{{.Tag}}")
  local containers=$($DOCKER ps -a --filter "label=project=monadic-chat" --format "{{.Names}}")

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
  local images=$($DOCKER images --format "{{.Repository}}:{{.Tag}}" | grep "$1")
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

# function to export the pgvector database
export_db() {
  local container_name="monadic-chat-pgvector-container"
  if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    start_docker_compose silent
  else
    echo "[HTML]: <p>Container '${container_name}' does not exist. Please build the container first.</p><hr />"
    exit 1
  fi

  $DOCKER exec "${container_name}" sh -c "pg_dump -U postgres monadic | gzip > \"/monadic/data/monadic.gz\""
  
  # if the above command is successful, print the success message
  if [ $? -eq 0 ]; then
    stop_docker_compose
    echo "[HTML]: <p>Document DB has been exported to 'monadic.gz' successfully!</p><hr />"
  else
    echo "[HTML]: <p>Document DB export failed!</p><hr />"
  fi
}

# function to import the pgvector database
import_db() {
  local container_name="monadic-chat-pgvector-container"
  if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    start_docker_compose silent
  else
    echo "[HTML]: <p>Container '${container_name}' does not exist. Please build the container first.</p><hr />"
    exit 1
  fi

  if [ ! -f "$HOME_DIR/monadic/data/monadic.gz" ]; then
    echo "[HTML]: <p>Document DB file 'monadic.gz' does not exist. Please set the file in the shared folder first.</p><hr />"
    exit 1
  fi

  $DOCKER exec "${container_name}" sh -c "dropdb -f -U postgres monadic && createdb -U postgres --locale=C --template=template0 monadic && gunzip -t \"/monadic/data/monadic.gz\" && gunzip -c \"/monadic/data/monadic.gz\" | psql -v ON_ERROR_STOP=1 -U postgres monadic || exit 1"

  # if the above command is successful, print the success message
  if [ $? -eq 0 ]; then
    stop_docker_compose
    echo "[HTML]: <p>Document DB has been imported successfully!</p><hr />"
  else
    echo "[HTML]: <p>Document DB import failed! Please check the database file.</p><hr />"
  fi
}

# Parse the user command
case "$1" in
  build)
    ensure_data_dir
    start_docker
    build_docker_compose
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
  export-db)
    start_docker
    export_db
    ;;
  import-db)
    start_docker
    import_db
    ;;
  *)
    echo "Usage: $0 {build|start|stop|restart|update|remove}" >&2
    exit 1
    ;;
esac

exit 0
