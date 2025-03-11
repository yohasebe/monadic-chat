#!/bin/bash

# Add /usr/local/bin to the PATH
export PATH=${PATH}:/usr/local/bin

export MONADIC_VERSION=0.9.58
export HOST_OS=$(uname -s)

RETRY_INTERVAL=5
RETRY_COUNT=24
DOCKER_CHECK_INTERVAL=2

# REPORTING=--verbose
REPORTING=

# Define the path to the root directory
ROOT_DIR=$(dirname "$0")
HOME_DIR=$(eval echo ~${SUDO_USER})

# Define the full path to docker-compose
DOCKER=$(command -v docker)
# escape spaces in the path to docker
DOCKER=$(echo "${DOCKER}" | sed 's/ /\\ /g')

# Define the paths to the support scripts
SCRIPTS=("mac-start-docker.sh" "wsl2-start-docker.sh" "linux-start-docker.sh")

normalize_path() {
  local path="$1"
  echo "${path}" | sed 's|//|/|g'
}

check_if_docker_desktop_is_running() {
  if ${DOCKER} info >/dev/null 2>&1; then
    echo "1"
  else
    echo "0"
  fi
}

# Function to log Docker container startup status
docker_start_log() {
  local log_file="${HOME_DIR}/monadic/log/docker_startup.log"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local containers=$(${DOCKER} ps --filter "name=monadic-chat" --format "{{.Names}}")

  mkdir -p "$(dirname "${log_file}")"

  echo "=== Monadic Chat Container Startup Log ===" > "${log_file}"
  echo "Timestamp: ${timestamp}" >> "${log_file}"
  echo "Monadic Chat Version: ${MONADIC_VERSION}" >> "${log_file}"
  echo "----------------------------------------" >> "${log_file}"

  local all_containers_running=true
  for container in ${containers}; do
    local status=$(${DOCKER} inspect --format='{{.State.Status}}' "${container}")
    local health_status=$(${DOCKER} inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "${container}")
    local uptime=$(${DOCKER} inspect --format='{{.State.StartedAt}}' "${container}")

    echo "Container: ${container}" >> "${log_file}"
    echo "Status: ${status}" >> "${log_file}"
    echo "Health: ${health_status}" >> "${log_file}"
    echo "Started At: ${uptime}" >> "${log_file}"
    echo "----------------------------------------" >> "${log_file}"

    if [[ "${status}" != "running" ]]; then
      all_containers_running=false
    fi
  done

  if ${all_containers_running}; then
    echo "Summary: All containers started successfully" >> "${log_file}"
  else
    echo "Summary: Some containers failed to start" >> "${log_file}"
    echo "[HTML]: <p style='color: red;'><i class='fas fa-exclamation-circle'></i> Warning: Some containers failed to start. Check docker_startup.log for details.</p>"
    fi
}

set_docker_compose() {
  local home_paths=("${HOME_DIR}/monadic/data/services" "~/monadic/data/services" "~/monadic/data/plugins/")

  for i in "${!home_paths[@]}"; do
    home_paths[$i]=$(eval echo "${home_paths[$i]}")
    home_paths[$i]=$(normalize_path "${home_paths[$i]}")
  done

  # Remove non-existent paths and empty strings
  home_paths=($(printf "%s\n" "${home_paths[@]}" | sort -u | grep -v '^$'))

  local compose_user=""
  for home_path in "${home_paths[@]}"; do
    while IFS= read -r file; do
      if [ ! -z "$file" ]; then
        file=$(normalize_path "$file")
        compose_user+="  - ${file}"$'\n'
      fi
    done < <(find "${home_path}" -name "compose.yml" 2>/dev/null)
  done

  if [[ -z "${compose_user}" ]]; then
    COMPOSE_MAIN="${ROOT_DIR}/services/compose.yml"
  else
    cat <<EOF >"${HOME_DIR}/monadic/config/compose.yml"
include:
  - ${ROOT_DIR}/services/ruby/compose.yml
  - ${ROOT_DIR}/services/pgvector/compose.yml
  - ${ROOT_DIR}/services/python/compose.yml
  - ${ROOT_DIR}/services/selenium/compose.yml
${compose_user}

networks:
  monadic-chat-network:
    driver: bridge

volumes:
  data:
EOF
    COMPOSE_MAIN="${HOME_DIR}/monadic/config/compose.yml"
  fi
}

# Function to ensure data directory exists
ensure_data_dir() {
  local data_dir
  local log_dir
  local config_dir

  if [[ -f "/.dockerenv" ]]; then
    data_dir="/monadic/data"
    log_dir="/monadic/log"
    config_dir="/monadic/config"
  else
    data_dir="${HOME_DIR}/monadic/data"
    log_dir="${HOME_DIR}/monadic/log"
    config_dir="${HOME_DIR}/monadic/config"
  fi

  mkdir -p "${data_dir}"
  mkdir -p "${log_dir}"
  mkdir -p "${config_dir}"

  rm -f "${log_dir}/command.log"
  rm -f "${log_dir}/jupyter.log"

  # remove extra.log if it exists
  rm -f "${log_dir}/extra.log"

  # clear rbsetup.sh and pysetup.sh in the root dir by overwriting default comments
  echo "# This file is overwritten by rbsetup.sh prepared by the user in the shared folder." > "${ROOT_DIR}/services/ruby/rbsetup.sh"
  echo "# This file is overwritten by pysetup.sh prepared by the user in the shared folder." > "${ROOT_DIR}/services/python/pysetup.sh"

  touch "${config_dir}/env"

  if [[ -f "${config_dir}/rbsetup.sh" && -s "${config_dir}/rbsetup.sh" ]]; then
    cp -f "${config_dir}/rbsetup.sh" "${ROOT_DIR}/services/ruby/rbsetup.sh"
  fi

  if [[ -f "${config_dir}/pysetup.sh" && -s "${config_dir}/pysetup.sh" ]]; then
    cp -f "${config_dir}/pysetup.sh" "${ROOT_DIR}/services/python/pysetup.sh"
  fi
}

# Function to start Docker based on OS
start_docker() {
  case "${HOST_OS}" in
  Darwin)
    start_script="${ROOT_DIR}/services/support_scripts/${SCRIPTS[0]}"
    ;;
  Linux)
    if [[ $(uname -r) == *microsoft* ]]; then
      start_script="${ROOT_DIR}/services/support_scripts/${SCRIPTS[1]}"
    else
      start_script="${ROOT_DIR}/services/support_scripts/${SCRIPTS[2]}"
    fi
    ;;
  *)
    echo "Unsupported operating system: ${HOST_OS}" >&2
    # exit 1
    ;;
  esac

  if [[ -f "${start_script}" ]]; then
    # return this function after the script has been executed without any errors
    sh "${start_script}" && echo "[HTML]: <p>Starting Docker...</p>"
  else
    echo "Start script not found: ${start_script}" >&2
    # exit 1
  fi

}

# Function to build Ruby container only
build_ruby_container() {
  local log_file="${HOME_DIR}/monadic/log/docker_build.log"
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"

  # build Ruby image only
  local dockerfile="${ROOT_DIR}/services/ruby/Dockerfile"
  ${DOCKER} build --no-cache -f "${dockerfile}" -t yohasebe/monadic-chat:${MONADIC_VERSION} "${ROOT_DIR}/services/ruby" 2>&1 | tee "${log_file}"

  ${DOCKER} tag yohasebe/monadic-chat:${MONADIC_VERSION} yohasebe/monadic-chat:latest
  
  # Don't call build_docker_compose here to avoid rebuilding the same container again
  # build_docker_compose

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
}

# Function to build Python container only
build_python_container() {
  local log_file="${HOME_DIR}/monadic/log/docker_build.log"
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"

  # build Python image only
  local dockerfile="${ROOT_DIR}/services/python/Dockerfile"
  ${DOCKER} build --no-cache -f "${dockerfile}" -t yohasebe/monadic-chat:${MONADIC_VERSION} "${ROOT_DIR}/services/python" 2>&1 | tee "${log_file}"

  ${DOCKER} tag yohasebe/monadic-chat:${MONADIC_VERSION} yohasebe/monadic-chat:latest
  
  # Don't call build_docker_compose here to avoid rebuilding the same container again
  # build_docker_compose

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
}

# Function to build user containers
build_user_containers() {
  local home_paths=("${HOME_DIR}/monadic/data/services" "~/monadic/data/services" "~/monadic/data/plugins/")
  for i in "${!home_paths[@]}"; do
    home_paths[$i]=$(eval echo "${home_paths[$i]}")
    home_paths[$i]=$(normalize_path "${home_paths[$i]}")
  done

  # Remove non-existent paths and empty strings
  home_paths=($(printf "%s\n" "${home_paths[@]}" | sort -u | grep -v '^$'))

  local compose="${HOME_DIR}/monadic/data/compose_user.yml"
  local found_compose_files=false

  local compose_user=""
  for home_path in "${home_paths[@]}"; do
    while IFS= read -r file; do
      if [ ! -z "$file" ]; then
        file=$(normalize_path "$file")
        compose_user+="  - ${file}"$'\n'
        found_compose_files=true
      fi
    done < <(find "${home_path}" -name "compose.yml" 2>/dev/null)
  done

  if [ "$found_compose_files" = false ]; then
    return 2  # Special return code for "no user containers found"
  fi

  local log_file="${HOME_DIR}/monadic/log/docker_build.log"
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"

  cat <<EOF >"${compose}"
include:
${compose_user}

networks:
  monadic-chat-network:
    driver: bridge

volumes:
  data:
EOF

  # Execute docker compose build and redirect output to log file
  ${DOCKER} compose ${REPORTING} -f "${compose}" build --no-cache 2>&1 | tee "${log_file}"

  ${DOCKER} tag yohasebe/monadic-chat:${MONADIC_VERSION} yohasebe/monadic-chat:latest
  # remove compose_user.yml
  rm -f "${compose}"

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
}

# Function to build Docker Compose with the option whether to use cache or not
build_docker_compose() {
  # use or not use cache
  if [[ "$1" == "no-cache" ]]; then
    use_cache="--no-cache"
  else
    use_cache=""
  fi

  set_docker_compose
  remove_containers
  
  # Create timestamp for log file
  local log_file="${HOME_DIR}/monadic/log/docker_build.log"
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"
  
  # Execute docker compose build and redirect output to log file with or without cache
  ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" build ${use_cache} 2>&1 | tee "${log_file}"

  ${DOCKER} tag yohasebe/monadic-chat:${MONADIC_VERSION} yohasebe/monadic-chat:latest

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
}

# Function to start Docker Compose
start_docker_compose() {
  set_docker_compose

  # Wait until Docker is running
  local retries=0
  while ! ${DOCKER} info > /dev/null 2>&1; do
    if [ $retries -ge $RETRY_COUNT ]; then
      echo "Docker did not start. Please start Docker Desktop manually."
      # exit 1
    fi
    retries=$((retries + 1))
    echo "Waiting for Docker to start... (${retries}/${RETRY_COUNT})"
    sleep $RETRY_INTERVAL
  done

  # get yohasebe/monadic-chat image tag
  MONADIC_CHAT_IMAGE_TAG=$(${DOCKER} images | grep "yohasebe/monadic-chat" | awk '{print $2}')
  MONADIC_CHAT_IMAGE_TAG=$(echo ${MONADIC_CHAT_IMAGE_TAG} | tr -d '\r')
  MONADIC_CHAT_IMAGE_TAG=$(echo ${MONADIC_CHAT_IMAGE_TAG} | sed 's/latest//g')

  if [ -z "${MONADIC_CHAT_IMAGE_TAG}" ]; then
    MONADIC_CHAT_IMAGE_TAG="None"
  fi

  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Monadic Chat app v${MONADIC_VERSION} <i class='fa-solid fa-arrow-right-arrow-left'></i> Container image v${MONADIC_CHAT_IMAGE_TAG}</p>"
  fi

  # Check for all required containers and services
  local needs_full_rebuild=false
  local needs_user_containers=false
  
  # Define the list of required containers
  local required_containers=("monadic-chat-ruby-container" "monadic-chat-python-container" "monadic-chat-pgvector-container" "monadic-chat-selenium-container")
  local missing_containers=()
  
  # Check if main image exists or needs update
  if ! ${DOCKER} images | grep -q "yohasebe/monadic-chat"; then
    echo "[IMAGE NOT FOUND]"
    echo "[HTML]: <p>Building all Monadic Chat containers. This may take a while...</p>"
    needs_full_rebuild=true
  elif [[ "${MONADIC_CHAT_IMAGE_TAG}" != *"${MONADIC_VERSION}"* ]]; then
    remove_containers
    echo "[HTML]: <p>App update detected (v${MONADIC_CHAT_IMAGE_TAG} → v${MONADIC_VERSION}). Rebuilding containers...</p>"
    ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" down
    needs_full_rebuild=true
  elif [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Checking container integrity...</p>"
  fi
  
  # If we haven't decided on a full rebuild, check individual containers
  if [ "$needs_full_rebuild" = false ]; then
    for container in "${required_containers[@]}"; do
      if ! ${DOCKER} container ls --all | grep -q "$container"; then
        missing_containers+=("$container")
        echo "[HTML]: <p>Container '$container' not found.</p>"
      fi
    done
    
    # If any containers are missing, do a full rebuild
    if [ ${#missing_containers[@]} -gt 0 ]; then
      echo "[HTML]: <p>Missing containers detected. Rebuilding all containers...</p>"
      needs_full_rebuild=true
    fi
  fi
  
  # Check for user containers
  if [[ "$COMPOSE_MAIN" != "${ROOT_DIR}/services/compose.yml" ]]; then
    # We have user compose files, check if they need to be built
    local home_paths=("${HOME_DIR}/monadic/data/services" "~/monadic/data/services" "~/monadic/data/plugins/")
    local user_compose_files=()
    
    for i in "${!home_paths[@]}"; do
      home_paths[$i]=$(eval echo "${home_paths[$i]}")
      home_paths[$i]=$(normalize_path "${home_paths[$i]}")
    done
    
    # Find user compose files
    for home_path in "${home_paths[@]}"; do
      while IFS= read -r file; do
        if [ ! -z "$file" ]; then
          file=$(normalize_path "$file")
          user_compose_files+=("$file")
        fi
      done < <(find "${home_path}" -name "compose.yml" 2>/dev/null)
    done
    
    # If we have user compose files, check if their containers are built
    if [ ${#user_compose_files[@]} -gt 0 ]; then
      # Logic to check if user containers need rebuilding
      needs_user_containers=true
      echo "[HTML]: <p>User container configuration detected. Checking user containers...</p>"
      
      if [ "$needs_full_rebuild" = false ]; then
        # Only show this if we're not already doing a full rebuild
        echo "[HTML]: <p>Building user containers...</p>"
        build_user_containers
      fi
    fi
  fi
  
  # Build all containers if needed
  if [ "$needs_full_rebuild" = true ]; then
    build_docker_compose "no-cache"
    if [[ "$1" != "silent" ]]; then
      echo "[HTML]: <p>Starting all Monadic Chat containers...</p>"
    fi
  elif [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>All containers are available. Moving on...</p>"
  fi

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
  
  ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" -p "monadic-chat-container" up -d 

  local containers=$(${DOCKER} ps --filter "label=project=monadic-chat" --format "{{.Names}}")

  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <hr /><p><b>Running Containers</b></p>"
    echo "[HTML]: <p>You can directly access the containers using the following commands:</p>"
    list_containers="<ul>"
    for container in ${containers}; do
      list_containers+="<li><i class='fa-solid fa-copy'></i> <code class='command'>docker exec -it ${container} bash</code></li>"
    done
    list_containers+="</ul>"
    echo "[HTML]: ${list_containers}<hr />"
  fi
}

# Function to stop Docker Compose
down_docker_compose() {
  ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" down --remove-orphans
}

# Define a function to stop Docker Compose
stop_docker_compose() {
  containers=$(${DOCKER} ps --filter "label=project=monadic-chat" --format "{{.Names}}")
  for container in ${containers}; do
    stop_container "${container}"
  done
}

# Function to stop a container
stop_container() {
  ${DOCKER} container stop -t 0 "$1" >/dev/null
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
  ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" down --remove-orphans

  # Move to `ROOT_DIR` and download the latest version of Monadic Chat
  cd "${ROOT_DIR}" && git pull origin main

  # Build and start the Docker Compose services
  ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" build --no-cache
}

# Remove the Docker image and container
remove_containers() {
  set_docker_compose
  # Stop the Docker Compose services
  ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" down --remove-orphans

  local images=$(${DOCKER} images --filter "label=project=monadic-chat" --format "{{.Repository}}:{{.Tag}}")
  local containers=$(${DOCKER} ps -a --filter "label=project=monadic-chat" --format "{{.Names}}")

  # Remove the Docker images and containers of the monadic-chat project
  for image in ${images}; do
    remove_image "${image}"
  done

  for container in ${containers}; do
    remove_container "${container}"
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
  local images=$(${DOCKER} images --format "{{.Repository}}:{{.Tag}}" | grep "$1")
  for image in ${images}; do
    ${DOCKER} rmi -f "${image}" >/dev/null
  done
}

# Function to remove a container
remove_container() {
  if ${DOCKER} container ls --all | grep -q "$1"; then
    ${DOCKER} container rm -f "$1" >/dev/null
  fi
}

# Function to remove a volume
remove_volume() {
  if ${DOCKER} volume ls | grep -q "$1"; then
    ${DOCKER} volume rm "$1" >/dev/null
  fi
}

# Function to remove project-specific dangling images
remove_project_dangling_images() {
  local project_label="monadic-chat"
  ${DOCKER} images -f "dangling=true" -f "label=project=${project_label}" --format "{{.ID}}" | xargs -r docker rmi -f
}

# Function to remove older images
remove_older_images() {
  local image_name="$1"
  local latest_image_id=$(${DOCKER} images --format "{{.ID}}" "${image_name}:${MONADIC_VERSION}")
  ${DOCKER} images --format "{{.ID}} {{.Repository}}:{{.Tag}}" "${image_name}" | grep -v "${latest_image_id}" | awk '{print $1}' | xargs -r ${DOCKER} rmi -f
}

# function to start jupyter lab
run_jupyter() {
  local command="$1"
  local container_name="monadic-chat-python-container"
  if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    start_docker_compose silent
  else
    echo "[HTML]: <p>Container '${container_name}' does not exist. Please build the container first.</p><hr />"
  fi

  ${DOCKER} exec "${container_name}" sh -c "run_jupyter.sh ${command}" || exit 1

  if [ $? -eq 0 ]; then
    if [ "${command}" == "run" ]; then
      echo "[HTML]: <p>JupyterLab is running. <a href='http://localhost:8889/lab/tree/data' target='_blank'>Click here to open JupyterLab</a></p><hr />"
    else
      echo "[HTML]: <p>JupyterLab has been stopped.</p><hr />"
    fi
  else
    echo "[HTML]: <p>JupyterLab failed to start.</p><hr />"
  fi
}

# function to export the pgvector database
export_db() {
  local container_name="monadic-chat-pgvector-container"
  if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
    start_docker_compose silent
  else
    echo "[HTML]: <p>Container '${container_name}' does not exist. Please build the container first.</p><hr />"
    # exit 1
  fi

  ${DOCKER} exec "${container_name}" sh -c "pg_dump -U postgres monadic | gzip > \"/monadic/data/monadic.gz\""

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
    # exit 1
  fi

  if [ ! -f "${HOME_DIR}/monadic/data/monadic.gz" ]; then
    echo "[HTML]: <p>Document DB file 'monadic.gz' does not exist. Please set the file in the shared folder first.</p><hr />"
    # exit 1
  fi

  ${DOCKER} exec "${container_name}" sh -c "dropdb -f -U postgres monadic && createdb -U postgres --locale=C --template=template0 monadic && gunzip -t \"/monadic/data/monadic.gz\" && gunzip -c \"/monadic/data/monadic.gz\" | psql -v ON_ERROR_STOP=1 -U postgres monadic || exit 1"

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
build_ruby_container)
  ensure_data_dir &&

  while ! ${DOCKER} info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  build_ruby_container

  # rm -f "${ROOT_DIR}/services/ruby/rbsetup.sh"
  # rm -f "${ROOT_DIR}/services/python/pysetup.sh"

  if ${DOCKER} images | grep -q "monadic-chat"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: green;'></i> Build of Ruby container has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i> Container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
build_python_container)
  ensure_data_dir &&

  while ! ${DOCKER} info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  build_python_container

  if ${DOCKER} images | grep -q "monadic-chat"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: green;'></i> Build of Python container has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i> Container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
build_user_containers)
  ensure_data_dir &&

  while ! ${DOCKER} info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  # Call build_user_containers and store the return value
  build_user_containers
  BUILD_RESULT=$?

  if [ ${BUILD_RESULT} -eq 2 ]; then
    # No user containers found (special return code)
    echo "[HTML]: <p><i class='fa-solid fa-info-circle'></i> No user containers to build.</p><hr />"
  elif ${DOCKER} images | grep -q "monadic-chat"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: green;'></i> Build of user containers has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i> Container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
build)
  ensure_data_dir &&

  while ! ${DOCKER} info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  remove_containers
  echo "[HTML]: <p>Building Monadic Chat image...</p>"
  ${DOCKER} compose ${REPORTING} -f "${COMPOSE_MAIN}" down
  build_docker_compose "no-cache"

  if ${DOCKER} images | grep -q "monadic-chat"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: green;'></i> Build of Monadic Chat has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i> Container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
check)
  check_if_docker_desktop_is_running
  ;;
start)
  ensure_data_dir &&
  start_docker_compose &&
  echo "[SERVER STARTED]" &&
  docker_start_log "silent"
  ;;
stop)
  if ${DOCKER} info >/dev/null 2>&1; then
    stop_docker_compose &&
    echo "[SERVER STOPPED]" &&
    echo "[HTML]: <p><b>Monadic Chat has been stopped.</b></p>"
  else
    echo "[HTML]: <p>Docker Desktop is not running, skipping stop operation.</p>"
  fi
  ;;
restart)
  stop_docker_compose &&
  echo "[SERVER STOPPED]" &&
  start_docker_compose &&
  echo "[SERVER STARTED]" &&
  docker_start_log "silent"
  ;;
import)
  stop_docker_compose &&
  import_database
  ;;
start-jupyter)
  run_jupyter run
  ;;
stop-jupyter)
  run_jupyter stop
  ;;
export)
  export_database
  ;;
update)
  update_monadic &&
  echo "[HTML]: <p>Monadic Chat has been updated successfully!</p>"
  ;;
down)
  down_docker_compose &&
  echo "[HTML]: <p><b>Monadic Chat has been stopped and containers have been removed</b></p>"
  ;;
remove)
  remove_containers &&
  echo "[HTML]: <p>Containers and images have been removed successfully.</p><p>Now you can quit Monadic Chat and uninstall the app safely.</p>"
  ;;
export-db)
  export_db
  ;;
import-db)
  import_db
  ;;
*)
  echo "Usage: $0 {build|start|stop|restart|update|remove|check}" >&2
  # exit 1
  ;;
esac

exit 0
