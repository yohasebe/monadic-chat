#!/bin/bash

# Add /usr/local/bin to the PATH
export PATH=${PATH}:/usr/local/bin

# Read version from version.rb (reliable source in both dev and packaged app)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VERSION_FILE="${SCRIPT_DIR}/services/ruby/lib/monadic/version.rb"

if [ -f "$VERSION_FILE" ]; then
  # Extract version from Ruby file: VERSION = "1.0.0-beta.5"
  export MONADIC_VERSION=$(grep 'VERSION = ' "$VERSION_FILE" | sed -E 's/.*VERSION = "([^"]+)".*/\1/')
else
  # Fallback: try package.json (development environment)
  PACKAGE_JSON="${SCRIPT_DIR}/../package.json"
  if [ -f "$PACKAGE_JSON" ]; then
    if command -v jq >/dev/null 2>&1; then
      export MONADIC_VERSION=$(jq -r '.version' "$PACKAGE_JSON" 2>/dev/null)
    else
      export MONADIC_VERSION=$(grep '"version"' "$PACKAGE_JSON" | sed -E 's/.*"version": "([^"]+)".*/\1/')
    fi
  fi
fi

# Verify version was read successfully
if [ -z "$MONADIC_VERSION" ]; then
  echo "ERROR: Failed to read version from version.rb or package.json"
  exit 1
fi

export HOST_OS=$(uname -s)

RETRY_INTERVAL=4
RETRY_COUNT=20
DOCKER_CHECK_INTERVAL=1

# REPORTING=--verbose
REPORTING=

# Define the path to the root directory
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
HOME_DIR=$(eval echo ~${SUDO_USER})

# Define the full path to docker-compose
DOCKER=$(command -v docker)

# If docker not found and we're in an Electron app, try harder to find it
if [ -z "$DOCKER" ]; then
  # Check if we can find docker using 'which' command
  DOCKER=$(which docker 2>/dev/null)
fi

# If still not found, default to 'docker' and let the system handle it
if [ -z "$DOCKER" ]; then
  DOCKER="docker"
fi

# Don't escape spaces - we'll quote the variable when using it

# Define the paths to the support scripts
SCRIPTS=("mac-start-docker.sh" "wsl2-start-docker.sh" "linux-start-docker.sh")

normalize_path() {
  local path="$1"
  echo "${path}" | sed 's|//|/|g'
}

safe_rm() {
  local target="$1"
  rm -f "$target" 2>/dev/null || {
    if command -v sudo >/dev/null 2>&1; then
      sudo rm -f "$target" 2>/dev/null || echo "[WARN] Unable to remove $target"
    else
      echo "[WARN] Unable to remove $target (insufficient permissions)"
    fi
  }
}

safe_touch() {
  local target="$1"
  touch "$target" 2>/dev/null || {
    if command -v sudo >/dev/null 2>&1; then
      if sudo touch "$target"; then
        sudo chown "$(id -u)":"$(id -g)" "$target" 2>/dev/null || true
      else
        echo "[WARN] Unable to touch $target"
      fi
    else
      echo "[WARN] Unable to touch $target (insufficient permissions)"
    fi
  }
}

# ---------------- Build concurrency lock ----------------
LOCK_DIR="${HOME_DIR}/monadic/log/build.lock.d"
# Treat a lock older than this as stale (seconds). Default: 2 hours
: "${STALE_LOCK_MAX_SECS:=7200}"

acquire_build_lock() {
  # Try to acquire a simple directory lock; handle stale locks
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    echo $$ > "${LOCK_DIR}/pid" 2>/dev/null || true
    date +%s > "${LOCK_DIR}/timestamp" 2>/dev/null || true
    return 0
  else
    # If a lock exists, check staleness
    if [ -d "${LOCK_DIR}" ]; then
      # Determine the last modification time of the lock directory
      now=$(date +%s)
      if [ -f "${LOCK_DIR}/timestamp" ]; then
        ts=$(cat "${LOCK_DIR}/timestamp" 2>/dev/null || echo 0)
      else
        # Fallback to filesystem mtime
        if command -v stat >/dev/null 2>&1; then
          case "$(uname -s)" in
            Darwin) ts=$(stat -f %m "${LOCK_DIR}" 2>/dev/null || echo 0); ;;
            *)      ts=$(stat -c %Y "${LOCK_DIR}" 2>/dev/null || echo 0); ;;
          esac
        else
          ts=0
        fi
      fi
      age=$(( now - ts ))
      if [ "$age" -gt "$STALE_LOCK_MAX_SECS" ]; then
        # Consider it stale; remove and acquire
        rm -rf "${LOCK_DIR}" 2>/dev/null || true
        if mkdir "${LOCK_DIR}" 2>/dev/null; then
          echo $$ > "${LOCK_DIR}/pid" 2>/dev/null || true
          date +%s > "${LOCK_DIR}/timestamp" 2>/dev/null || true
          echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color:#61b0ff;'></i> Previous build lock was stale (age ${age}s). Continuing with a fresh build.</p>"
          return 0
        fi
      fi
    fi
    # Informational UI message (not a warning)
    echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color:#61b0ff;'></i> Another build is in progress. Please wait until it finishes.</p>"
    return 1
  fi
}

release_build_lock() {
  rm -rf "${LOCK_DIR}" 2>/dev/null || true
}

check_if_docker_desktop_is_running() {
  if "${DOCKER}" info >/dev/null 2>&1; then
    echo "1"
  else
    echo "0"
  fi
}

# Function to log Docker container startup status
docker_start_log() {
  local log_file="${HOME_DIR}/monadic/log/docker_startup.log"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local containers=$("${DOCKER}" ps --filter "name=monadic-chat" --format "{{.Names}}")

  mkdir -p "$(dirname "${log_file}")"

  echo "=== Monadic Chat Container Startup Log ===" > "${log_file}"
  echo "Timestamp: ${timestamp}" >> "${log_file}"
  echo "Monadic Chat Version: ${MONADIC_VERSION}" >> "${log_file}"
  echo "----------------------------------------" >> "${log_file}"

  # Compatibility marker no longer used. Rely on runtime health below.

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
    # Emit a styled message consistent with app UI (icon + normal text, no red inline text)
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color:#DC4C64;'></i> Some containers failed to start. Check docker_startup.log for details.</p>"
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
  - "${ROOT_DIR}/services/ruby/compose.yml"
  - "${ROOT_DIR}/services/pgvector/compose.yml"
  - "${ROOT_DIR}/services/python/compose.yml"
  - "${ROOT_DIR}/services/selenium/compose.yml"
  - "${ROOT_DIR}/services/ollama/compose.yml"
${compose_user}

networks:
  monadic-chat-network:
    driver: bridge

volumes:
  data:
EOF
    COMPOSE_MAIN="${HOME_DIR}/monadic/config/compose.yml"
  fi
  
  # Check for compose.override.yml
  COMPOSE_OVERRIDE="${ROOT_DIR}/services/compose.override.yml"
  if [[ -f "${COMPOSE_OVERRIDE}" ]]; then
    COMPOSE_FILES="-f \"${COMPOSE_MAIN}\" -f \"${COMPOSE_OVERRIDE}\""
  else
    COMPOSE_FILES="-f \"${COMPOSE_MAIN}\""
  fi
  
  # Debug: log the compose files being used
  echo "[DEBUG] COMPOSE_MAIN='${COMPOSE_MAIN}'" >&2
  echo "[DEBUG] COMPOSE_FILES='${COMPOSE_FILES}'" >&2
  
  # Ensure COMPOSE_FILES is not empty
  if [ -z "${COMPOSE_FILES}" ]; then
    echo "[ERROR] COMPOSE_FILES is empty!" >&2
    COMPOSE_FILES="-f \"${ROOT_DIR}/services/compose.yml\""
    echo "[DEBUG] Using fallback COMPOSE_FILES='${COMPOSE_FILES}'" >&2
  fi
}

# Function to ensure data directory exists
ensure_data_dir() {
  local container_type="$1"
  local data_dir
  local log_dir
  local config_dir
  local ollama_dir

  if [[ -f "/.dockerenv" ]]; then
    data_dir="/monadic/data"
    log_dir="/monadic/log"
    config_dir="/monadic/config"
    ollama_dir="/monadic/ollama"
  else
    data_dir="${HOME_DIR}/monadic/data"
    log_dir="${HOME_DIR}/monadic/log"
    config_dir="${HOME_DIR}/monadic/config"
    ollama_dir="${HOME_DIR}/monadic/ollama"
  fi

  mkdir -p "${data_dir}"
  mkdir -p "${log_dir}"
  mkdir -p "${config_dir}"
  mkdir -p "${ollama_dir}"

  safe_rm "${log_dir}/command.log"
  safe_rm "${log_dir}/jupyter.log"

  # remove extra.log if it exists
  safe_rm "${log_dir}/extra.log"

  # clear rbsetup.sh, pysetup.sh and olsetup.sh in the root dir by overwriting default comments
  echo "# This file is overwritten by rbsetup.sh prepared by the user in the shared folder." > "${ROOT_DIR}/services/ruby/rbsetup.sh"
  echo "# This file is overwritten by pysetup.sh prepared by the user in the shared folder." > "${ROOT_DIR}/services/python/pysetup.sh"
  echo "# This file is overwritten by olsetup.sh prepared by the user in the shared folder." > "${ROOT_DIR}/services/ollama/olsetup.sh"

  safe_touch "${config_dir}/env"

  # Only show Ruby setup message when building Ruby container or all containers
  if [[ -f "${config_dir}/rbsetup.sh" && -s "${config_dir}/rbsetup.sh" ]]; then
    cp -f "${config_dir}/rbsetup.sh" "${ROOT_DIR}/services/ruby/rbsetup.sh"
    if [[ "$container_type" == "ruby" || "$container_type" == "" ]]; then
      echo "[HTML]: <p><i class='fa-solid fa-gem'></i>Custom Ruby setup script (rbsetup.sh) detected and will be used.</p>"
    fi
  fi

  # Only show Python setup message when building Python container or all containers
  if [[ -f "${config_dir}/pysetup.sh" && -s "${config_dir}/pysetup.sh" ]]; then
    cp -f "${config_dir}/pysetup.sh" "${ROOT_DIR}/services/python/pysetup.sh"
    if [[ "$container_type" == "python" || "$container_type" == "" ]]; then
      echo "[HTML]: <p><i class='fa-brands fa-python'></i>Custom Python setup script (pysetup.sh) detected and will be used.</p>"
    fi
  fi

  # Only show Ollama setup message when building Ollama container
  if [[ -f "${config_dir}/olsetup.sh" && -s "${config_dir}/olsetup.sh" ]]; then
    cp -f "${config_dir}/olsetup.sh" "${ROOT_DIR}/services/ollama/olsetup.sh"
    if [[ "$container_type" == "ollama" || "$container_type" == "" ]]; then
      echo "[HTML]: <p><i class='fa-solid fa-robot'></i>Custom Ollama setup script (olsetup.sh) detected. To use it, please build the Ollama container from the menu.</p>"
    fi
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
  local _lock_acquired=false
  if acquire_build_lock; then _lock_acquired=true; fi
  if [ "${_lock_acquired}" != true ]; then
    return 1
  fi
  local log_file="${HOME_DIR}/monadic/log/docker_build.log"
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"

  # Reference assets_list.sh from the Ruby service directory
  mkdir -p "${ROOT_DIR}/services/ruby/bin/"
  
  # build Ruby image only (use cache by default)
  local dockerfile="${ROOT_DIR}/services/ruby/Dockerfile"
  # Compute gems fingerprint for labeling
  local gems_hash
  if [ -f "${ROOT_DIR}/services/ruby/Gemfile" ] && [ -f "${ROOT_DIR}/services/ruby/monadic.gemspec" ]; then
    gems_hash=$(cat "${ROOT_DIR}/services/ruby/Gemfile" "${ROOT_DIR}/services/ruby/monadic.gemspec" | sha256sum | awk '{print $1}')
  else
    gems_hash="unknown"
  fi
  # Optional no-cache for diagnostics or user-requested force rebuild
  local build_extra=""
  if [ "${FORCE_REBUILD:-false}" = "true" ] || [ "${FORCE_RUBY_REBUILD_NO_CACHE}" = "true" ]; then
    build_extra="--no-cache"
    echo "[INFO] Force rebuild requested, using --no-cache" | tee -a "${log_file}"
  fi
  ${DOCKER} build ${build_extra} \
    --build-arg GEMS_FINGERPRINT="${gems_hash}" \
    -f "${dockerfile}" \
    -t yohasebe/monadic-chat:${MONADIC_VERSION} \
    "${ROOT_DIR}/services/ruby" 2>&1 | tee "${log_file}"

  "${DOCKER}" tag yohasebe/monadic-chat:${MONADIC_VERSION} yohasebe/monadic-chat:latest
  
  # Don't call build_docker_compose here to avoid rebuilding the same container again
  # build_docker_compose

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
  release_build_lock
}

# Function to build Python container only
build_python_container() {
  local _lock_acquired=false
  if acquire_build_lock; then _lock_acquired=true; fi
  if [ "${_lock_acquired}" != true ]; then
    return 1
  fi
  # Overwrite logs on each run (no per-run directories)
  local logs_dir="${HOME_DIR}/monadic/log"
  mkdir -p "${logs_dir}"
  local build_log="${logs_dir}/docker_build_python.log"
  local post_log="${logs_dir}/post_install_python.log"
  local health_json="${logs_dir}/python_health.json"
  local meta_json="${logs_dir}/python_meta.json"

  # Echo discovery hints for Electron to pick up paths
  echo "[BUILD_RUN_DIR] ${logs_dir}"

  # Resolve install options from user's env (SSOT)
  local config_env="${HOME_DIR}/monadic/config/env"
  # Helper to read KEY=VALUE (quotes trimmed). Falls back to 'false' when unset.
  # Checks environment variables first (passed by Electron), then falls back to config file
  read_cfg_bool() {
    local key="$1"; local defval="${2:-false}"
    local val=""

    # First, check if the key exists as an environment variable (passed by Electron)
    # Using eval for indirect variable reference for better compatibility
    val=$(eval echo "\$${key}")

    # If not in environment, read from config file
    if [ -z "$val" ] && [ -f "$config_env" ]; then
      local line=$(grep -E "^${key}=" "$config_env" | tail -n1 || true)
      if [ -n "$line" ]; then
        val=${line#*=}
        val=${val%""}; val=${val#""}
      fi
    fi

    # Normalize and return the value
    if [ -n "$val" ]; then
      val=$(echo "$val" | tr '[:upper:]' '[:lower:]')
      case "$val" in
        true|1|yes|on) echo "true";;
        false|0|no|off|"") echo "false";;
        *) echo "$defval";;
      esac
      return
    fi
    echo "$defval"
  }

  local INSTALL_LATEX=$(read_cfg_bool "INSTALL_LATEX" false)
  local PYOPT_NLTK=$(read_cfg_bool "PYOPT_NLTK" false)
  local PYOPT_SPACY=$(read_cfg_bool "PYOPT_SPACY" false)
  local PYOPT_SCIKIT=$(read_cfg_bool "PYOPT_SCIKIT" false)
  local PYOPT_GENSIM=$(read_cfg_bool "PYOPT_GENSIM" false)
  local PYOPT_LIBROSA=$(read_cfg_bool "PYOPT_LIBROSA" false)
  local PYOPT_MEDIAPIPE=$(read_cfg_bool "PYOPT_MEDIAPIPE" false)
  local PYOPT_TRANSFORMERS=$(read_cfg_bool "PYOPT_TRANSFORMERS" false)
  local IMGOPT_IMAGEMAGICK=$(read_cfg_bool "IMGOPT_IMAGEMAGICK" false)

  # Detect if install options have changed since last build
  local prev_options_file="${logs_dir}/python_build_options.txt"
  local use_no_cache=false
  local changed_options=""

  # Check if user explicitly requested force rebuild
  if [ "${FORCE_REBUILD:-false}" = "true" ]; then
    use_no_cache=true
    echo "[INFO] Force rebuild requested by user, using --no-cache" | tee -a "${build_log}"
  elif [ -f "$prev_options_file" ]; then
    # Compare each option with previous build
    local prev_INSTALL_LATEX=$(grep "^INSTALL_LATEX=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_PYOPT_NLTK=$(grep "^PYOPT_NLTK=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_PYOPT_SPACY=$(grep "^PYOPT_SPACY=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_PYOPT_SCIKIT=$(grep "^PYOPT_SCIKIT=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_PYOPT_GENSIM=$(grep "^PYOPT_GENSIM=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_PYOPT_LIBROSA=$(grep "^PYOPT_LIBROSA=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_PYOPT_MEDIAPIPE=$(grep "^PYOPT_MEDIAPIPE=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_PYOPT_TRANSFORMERS=$(grep "^PYOPT_TRANSFORMERS=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
    local prev_IMGOPT_IMAGEMAGICK=$(grep "^IMGOPT_IMAGEMAGICK=" "$prev_options_file" 2>/dev/null | cut -d= -f2)

    # Check for changes
    [ "$INSTALL_LATEX" != "$prev_INSTALL_LATEX" ] && changed_options+="INSTALL_LATEX($prev_INSTALL_LATEX→$INSTALL_LATEX) "
    [ "$PYOPT_NLTK" != "$prev_PYOPT_NLTK" ] && changed_options+="PYOPT_NLTK($prev_PYOPT_NLTK→$PYOPT_NLTK) "
    [ "$PYOPT_SPACY" != "$prev_PYOPT_SPACY" ] && changed_options+="PYOPT_SPACY($prev_PYOPT_SPACY→$PYOPT_SPACY) "
    [ "$PYOPT_SCIKIT" != "$prev_PYOPT_SCIKIT" ] && changed_options+="PYOPT_SCIKIT($prev_PYOPT_SCIKIT→$PYOPT_SCIKIT) "
    [ "$PYOPT_GENSIM" != "$prev_PYOPT_GENSIM" ] && changed_options+="PYOPT_GENSIM($prev_PYOPT_GENSIM→$PYOPT_GENSIM) "
    [ "$PYOPT_LIBROSA" != "$prev_PYOPT_LIBROSA" ] && changed_options+="PYOPT_LIBROSA($prev_PYOPT_LIBROSA→$PYOPT_LIBROSA) "
    [ "$PYOPT_MEDIAPIPE" != "$prev_PYOPT_MEDIAPIPE" ] && changed_options+="PYOPT_MEDIAPIPE($prev_PYOPT_MEDIAPIPE→$PYOPT_MEDIAPIPE) "
    [ "$PYOPT_TRANSFORMERS" != "$prev_PYOPT_TRANSFORMERS" ] && changed_options+="PYOPT_TRANSFORMERS($prev_PYOPT_TRANSFORMERS→$PYOPT_TRANSFORMERS) "
    [ "$IMGOPT_IMAGEMAGICK" != "$prev_IMGOPT_IMAGEMAGICK" ] && changed_options+="IMGOPT_IMAGEMAGICK($prev_IMGOPT_IMAGEMAGICK→$IMGOPT_IMAGEMAGICK) "

    if [ -n "$changed_options" ]; then
      use_no_cache=true
      echo "[INFO] Install options changed: ${changed_options}" | tee -a "${build_log}"
      echo "[INFO] Using --no-cache to ensure changes are applied" | tee -a "${build_log}"
    else
      echo "[INFO] Install options unchanged, using build cache for faster build" | tee -a "${build_log}"
    fi
  else
    # First build or options file missing - use --no-cache to be safe
    use_no_cache=true
    echo "[INFO] First build or options file missing, using --no-cache" | tee -a "${build_log}"
  fi

  local build_args=
  build_args+=" --build-arg INSTALL_LATEX=${INSTALL_LATEX}"
  build_args+=" --build-arg PYOPT_NLTK=${PYOPT_NLTK}"
  build_args+=" --build-arg PYOPT_SPACY=${PYOPT_SPACY}"
  build_args+=" --build-arg PYOPT_SCIKIT=${PYOPT_SCIKIT}"
  build_args+=" --build-arg PYOPT_GENSIM=${PYOPT_GENSIM}"
  build_args+=" --build-arg PYOPT_LIBROSA=${PYOPT_LIBROSA}"
  build_args+=" --build-arg PYOPT_MEDIAPIPE=${PYOPT_MEDIAPIPE}"
  build_args+=" --build-arg PYOPT_TRANSFORMERS=${PYOPT_TRANSFORMERS}"
  build_args+=" --build-arg IMGOPT_IMAGEMAGICK=${IMGOPT_IMAGEMAGICK}"

  # Build Python image into a temporary tag for atomic swap
  local dockerfile="${ROOT_DIR}/services/python/Dockerfile"
  local ts=$(date +%Y%m%d_%H%M%S)
  local temp_tag="yohasebe/monadic-chat:python-build-${ts}"
  # Determine cache strategy based on option changes
  local cache_flag=""
  if [ "$use_no_cache" = true ]; then
    cache_flag="--no-cache"
  fi

  echo "[HTML]: <p>Starting Python image build (atomic) . . .</p>" | tee -a "${build_log}"

  # Build with appropriate cache strategy
  # IMPORTANT: cache_flag must not be quoted to allow empty string to work correctly
  if ! ${DOCKER} build ${cache_flag} -f "${dockerfile}" ${build_args} -t "${temp_tag}" "${ROOT_DIR}/services/python" 2>&1 | tee -a "${build_log}"; then
    echo "[ERROR] Docker build failed" | tee -a "${build_log}"
    echo "[BUILD_COMPLETE] failed"
    release_build_lock
    return 1
  fi

  # Optional post-setup: execute user's pysetup.sh if present (mounted config)
  echo "[HTML]: <p>Running post-setup (pysetup.sh) if available . . .</p>" | tee -a "${post_log}"
  if ! ${DOCKER} run --rm -v "${HOME_DIR}/monadic/config:/monadic/config" "${temp_tag}" sh -lc 'if [ -s /monadic/config/pysetup.sh ]; then bash /monadic/config/pysetup.sh; else echo "No pysetup.sh provided"; fi' 2>&1 | tee -a "${post_log}"; then
    echo "[WARN] Post-setup script encountered errors" | tee -a "${post_log}"
  fi

  # Health checks (feature-aware)
  echo "[HTML]: <p>Running health checks . . .</p>" | tee -a "${build_log}"
  {
    echo "{"
    echo "  \"timestamp\": \"${ts}\"," 
         "\"monadic_version\": \"${MONADIC_VERSION}\"," 
         "\"host_os\": \"${HOST_OS}\"," 
         "\"options\": {\"INSTALL_LATEX\": ${INSTALL_LATEX}, \"IMGOPT_IMAGEMAGICK\": ${IMGOPT_IMAGEMAGICK}, \"PYOPT_NLTK\": ${PYOPT_NLTK}, \"PYOPT_SPACY\": ${PYOPT_SPACY}, \"PYOPT_SCIKIT\": ${PYOPT_SCIKIT}, \"PYOPT_GENSIM\": ${PYOPT_GENSIM}, \"PYOPT_LIBROSA\": ${PYOPT_LIBROSA}, \"PYOPT_MEDIAPIPE\": ${PYOPT_MEDIAPIPE}, \"PYOPT_TRANSFORMERS\": ${PYOPT_TRANSFORMERS}} ,"
    # LaTeX
    if [ "${INSTALL_LATEX}" = "true" ]; then
      ${DOCKER} run --rm "${temp_tag}" sh -lc 'pdflatex -version >/dev/null 2>&1'; LATEX_OK=$?
      echo "  \"latex\": ${LATEX_OK:-1} == 0 ? true : false," | sed 's/ == 0 ? true : false/,/g' >/dev/null
    fi
  } >/dev/null
  # Build structured JSON using python inside container for accurate booleans
  ${DOCKER} run --rm "${temp_tag}" sh -lc "python - <<'PY'
import json, shutil, os, importlib
res = { 'checks': {} }
res['checks']['latex'] = shutil.which('pdflatex') is not None
res['checks']['imagemagick'] = shutil.which('convert') is not None
mods = ['nltk','spacy','sklearn','gensim','librosa','mediapipe','transformers']
res['checks']['python'] = { m: False for m in mods }
for m in mods:
  try:
    importlib.import_module(m)
    res['checks']['python'][m] = True
  except Exception:
    pass
print(json.dumps(res))
PY
" > "${health_json}" 2>/dev/null || echo '{"checks": {}}' > "${health_json}"

  # Write meta.json
  cat > "${meta_json}" <<META
{
  "timestamp": "${ts}",
  "monadic_version": "${MONADIC_VERSION}",
  "host_os": "${HOST_OS}",
  "image_temp_tag": "${temp_tag}",
  "build_args": {
    "INSTALL_LATEX": ${INSTALL_LATEX},
    "PYOPT_NLTK": ${PYOPT_NLTK},
    "PYOPT_SPACY": ${PYOPT_SPACY},
    "PYOPT_SCIKIT": ${PYOPT_SCIKIT},
    "PYOPT_GENSIM": ${PYOPT_GENSIM},
    "PYOPT_LIBROSA": ${PYOPT_LIBROSA},
    "PYOPT_MEDIAPIPE": ${PYOPT_MEDIAPIPE},
    "PYOPT_TRANSFORMERS": ${PYOPT_TRANSFORMERS},
    "IMGOPT_IMAGEMAGICK": ${IMGOPT_IMAGEMAGICK}
  }
}
META

  # If everything looks good, retag atomically to version and latest
  echo "[HTML]: <p>Verifying image . . .</p>" | tee -a "${build_log}"
  if ${DOCKER} run --rm "${temp_tag}" python -c "import sys; sys.exit(0)" >/dev/null 2>&1; then
    "${DOCKER}" tag "${temp_tag}" yohasebe/python:${MONADIC_VERSION}
    "${DOCKER}" tag yohasebe/python:${MONADIC_VERSION} yohasebe/python:latest
    "${DOCKER}" rmi "${temp_tag}" >/dev/null 2>&1 || true
    echo "[HTML]: <p>Python image updated successfully.</p>" | tee -a "${build_log}"

    # Save current install options for future comparison
    cat > "${prev_options_file}" <<OPTIONS
INSTALL_LATEX=${INSTALL_LATEX}
PYOPT_NLTK=${PYOPT_NLTK}
PYOPT_SPACY=${PYOPT_SPACY}
PYOPT_SCIKIT=${PYOPT_SCIKIT}
PYOPT_GENSIM=${PYOPT_GENSIM}
PYOPT_LIBROSA=${PYOPT_LIBROSA}
PYOPT_MEDIAPIPE=${PYOPT_MEDIAPIPE}
PYOPT_TRANSFORMERS=${PYOPT_TRANSFORMERS}
IMGOPT_IMAGEMAGICK=${IMGOPT_IMAGEMAGICK}
OPTIONS
    echo "[INFO] Saved build options to ${prev_options_file}" | tee -a "${build_log}"

    # Restart Python container if running to use the new image
    local python_container_name="monadic-chat-python-container"
    if ${DOCKER} ps --format '{{.Names}}' | grep -q "^${python_container_name}$"; then
      echo "[HTML]: <p>Restarting Python container to use new image...</p>" | tee -a "${build_log}"
      if ${DOCKER} compose -f "${COMPOSE_MAIN}" ${COMPOSE_OVERRIDE} restart python_service 2>&1 | tee -a "${build_log}"; then
        echo "[INFO] Python container restarted successfully" | tee -a "${build_log}"
      else
        echo "[WARNING] Failed to restart Python container. Please restart manually." | tee -a "${build_log}"
      fi
    else
      echo "[INFO] Python container not running. New image will be used on next start." | tee -a "${build_log}"
    fi
  else
    echo "[ERROR] Health verification failed; keeping current image" | tee -a "${build_log}"
    "${DOCKER}" rmi "${temp_tag}" >/dev/null 2>&1 || true
    echo "[BUILD_COMPLETE] failed"
    echo "Please check the following log files under: ${run_dir}"
    release_build_lock
    return 1
  fi

  # Cleanup older images but keep logs
  remove_older_images yohasebe/python
  remove_project_dangling_images

  echo "[BUILD_LOG] ${build_log}"
  echo "[POST_SETUP_LOG] ${post_log}"
  echo "[HEALTH_JSON] ${health_json}"
  echo "[META_JSON] ${meta_json}"
  echo "Build logs are available under: ${run_dir}"
  echo "[BUILD_COMPLETE] success"
  release_build_lock
}

# Ensure Ruby control-plane matches Python data-plane compatibility
ensure_ruby_compat_with_python() {
  local ruby_container_name="monadic-chat-ruby-container"
  local ruby_cp_ver=$(${DOCKER} inspect --format='{{range .Config.Env}}{{println .}}{{end}}' ${ruby_container_name} 2>/dev/null | grep '^MONADIC_COMPAT_VERSION=' | cut -d= -f2)
  ruby_cp_ver=${ruby_cp_ver:-none}

  # Desired (target) version is taken from the Python Dockerfile in the working copy
  local python_dockerfile="${ROOT_DIR}/services/python/Dockerfile"
  local target_ver=$(grep -E '^ENV[[:space:]]+MONADIC_COMPAT_VERSION=' "$python_dockerfile" | sed -E 's/.*MONADIC_COMPAT_VERSION="?([^"\n]+)"?.*/\1/' | tail -n1)
  target_ver=${target_ver:-unknown}

  if [ -z "$target_ver" ] || [ "$target_ver" = "unknown" ]; then
    return 0
  fi

  if [ "$ruby_cp_ver" != "$target_ver" ]; then
    echo "[HTML]: <p><i class='fa-solid fa-gem'></i> Rebuilding Ruby container for compatibility (expected=${target_ver}, actual=${ruby_cp_ver}).</p>"
    build_ruby_container
  fi
}

# Function to build Selenium container
build_selenium_container() {
  local _lock_acquired=false
  if acquire_build_lock; then _lock_acquired=true; fi
  if [ "${_lock_acquired}" != true ]; then
    return 1
  fi
  local log_file="${HOME_DIR}/monadic/log/docker_build.log"

  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"

  # Build Selenium container
  echo "Building Selenium container..." | tee -a "${log_file}"

  # Use docker compose to build only the Selenium container
  ${DOCKER} compose -f "${ROOT_DIR}/services/compose.yml" -p "monadic-chat" build selenium_service 2>&1 | tee -a "${log_file}"

  # Check if the build was successful
  if ${DOCKER} images | grep -q "yohasebe/selenium"; then
    echo "Selenium container built successfully" | tee -a "${log_file}"

    # Restart Ruby container if it's running to update SELENIUM_AVAILABLE environment variable
    if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-ruby-container$"; then
      echo "Restarting Ruby container to detect Selenium..." | tee -a "${log_file}"
      ${DOCKER} restart monadic-chat-ruby-container 2>&1 | tee -a "${log_file}"
      echo "Ruby container restarted." | tee -a "${log_file}"
    fi

    echo "Selenium container setup completed." | tee -a "${log_file}"
  else
    echo "Failed to build Selenium container" | tee -a "${log_file}"
    release_build_lock
    return 1
  fi

  remove_older_images yohasebe/selenium
  remove_project_dangling_images
  release_build_lock
}

# Function to build Ollama container
build_ollama_container() {
  local _lock_acquired=false
  if acquire_build_lock; then _lock_acquired=true; fi
  if [ "${_lock_acquired}" != true ]; then
    return 1
  fi
  local log_file="${HOME_DIR}/monadic/log/docker_build.log"

  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"

  # Build Ollama container with the ollama profile
  echo "Building Ollama container..." | tee -a "${log_file}"

  # Use docker compose with the ollama profile to build only the Ollama container
  # Use the main compose file which includes all service definitions
  ${DOCKER} compose -f "${ROOT_DIR}/services/compose.yml" -p "monadic-chat" --profile ollama build ollama_service 2>&1 | tee -a "${log_file}"

  # Check if the build was successful
  if ${DOCKER} images | grep -q "yohasebe/ollama"; then
    echo "Ollama container built successfully" | tee -a "${log_file}"

    # Start the container temporarily to download models
    echo "Starting Ollama container to download models..." | tee -a "${log_file}"
    ${DOCKER} compose -f "${ROOT_DIR}/services/compose.yml" -p "monadic-chat" --profile ollama up -d ollama_service 2>&1 | tee -a "${log_file}"

    # Wait for Ollama service to be ready
    echo "Waiting for Ollama service to be ready..." | tee -a "${log_file}"
    OLLAMA_READY=false
    for i in {1..30}; do
      # Use ollama's built-in command to check if service is ready
      if ${DOCKER} exec monadic-chat-ollama-container ollama list >/dev/null 2>&1; then
        OLLAMA_READY=true
        echo "Ollama service is ready." | tee -a "${log_file}"
        break
      fi
      echo "Waiting for Ollama service... ($i/30)" | tee -a "${log_file}"
      sleep 2
    done

    if [ "$OLLAMA_READY" = false ]; then
      echo "ERROR: Ollama service failed to start" | tee -a "${log_file}"
      return 1
    fi

    # Check if olsetup.sh exists in the container and run it
    if ${DOCKER} exec monadic-chat-ollama-container test -f /monadic/olsetup.sh 2>/dev/null; then
      echo "Running custom model setup..." | tee -a "${log_file}"
      # Make sure the script is executable
      ${DOCKER} exec monadic-chat-ollama-container chmod +x /monadic/olsetup.sh 2>&1 | tee -a "${log_file}"
      ${DOCKER} exec monadic-chat-ollama-container /monadic/olsetup.sh 2>&1 | tee -a "${log_file}"
      echo "Custom model setup completed." | tee -a "${log_file}"
    else
      echo "No custom setup script found. Downloading default model..." | tee -a "${log_file}"
      # Get default model from environment variable or use llama3.2 as fallback
      DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3.2}"
      echo "Default model: ${DEFAULT_MODEL}" | tee -a "${log_file}"
      ${DOCKER} exec monadic-chat-ollama-container ollama pull "${DEFAULT_MODEL}" 2>&1 | tee -a "${log_file}"
      echo "Default model downloaded." | tee -a "${log_file}"
    fi

    # Stop the container after model download
    echo "Stopping Ollama container..." | tee -a "${log_file}"
    ${DOCKER} compose -f "${ROOT_DIR}/services/compose.yml" -p "monadic-chat" --profile ollama stop ollama_service 2>&1 | tee -a "${log_file}"

    # Restart Ruby container if it's running to update OLLAMA_AVAILABLE environment variable
    if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-ruby-container$"; then
      echo "Restarting Ruby container to detect Ollama..." | tee -a "${log_file}"
      ${DOCKER} restart monadic-chat-ruby-container 2>&1 | tee -a "${log_file}"
      echo "Ruby container restarted." | tee -a "${log_file}"
    fi

    echo "Ollama container setup completed. Models are now available." | tee -a "${log_file}"
  else
    echo "Failed to build Ollama container" | tee -a "${log_file}"
    release_build_lock
    return 1
  fi

  remove_older_images yohasebe/ollama
  remove_project_dangling_images
  release_build_lock
}

# Function to build user containers
build_user_containers() {
  local _lock_acquired=false
  if acquire_build_lock; then _lock_acquired=true; fi
  if [ "${_lock_acquired}" != true ]; then
    return 1
  fi
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
    release_build_lock
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

  # remove compose_user.yml
  rm -f "${compose}"

  # User containers have their own image names, so we only clean up dangling images
  remove_project_dangling_images

  # Informational message only; orchestration will self-check on next Start
  echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color:#61b0ff;'></i> User containers updated. On the next Start, the system will check orchestration health and refresh Ruby automatically if needed.</p>"
  release_build_lock
}

# Function to check Docker disk space and warn if insufficient
check_docker_disk_space() {
  echo "[HTML]: <p>Checking Docker disk usage...</p>"

  # Get Docker system info and format as HTML table
  local disk_data=$(${DOCKER} system df 2>/dev/null)

  if [ -n "$disk_data" ]; then
    # Build HTML table as a single string
    local html_table="<table style='font-size: 0.9em; border-collapse: collapse; margin: 10px 0;'>"
    html_table="${html_table}<tr style='background: #f0f0f0; font-weight: bold;'>"
    html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd;'>TYPE</td>"
    html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>TOTAL</td>"
    html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>ACTIVE</td>"
    html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>SIZE</td>"
    html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>RECLAIMABLE</td>"
    html_table="${html_table}</tr>"

    # Parse each line (skip header)
    while IFS= read -r line; do
      local type=$(echo "$line" | awk '{print $1}')
      local total=$(echo "$line" | awk '{print $2}')
      local active=$(echo "$line" | awk '{print $3}')
      local size=$(echo "$line" | awk '{print $4}')
      local reclaimable=$(echo "$line" | awk '{print $5, $6}')

      html_table="${html_table}<tr>"
      html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd;'>${type}</td>"
      html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>${total}</td>"
      html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>${active}</td>"
      html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>${size}</td>"
      html_table="${html_table}<td style='padding: 8px; border: 1px solid #ddd; text-align: right;'>${reclaimable}</td>"
      html_table="${html_table}</tr>"
    done <<< "$(echo "$disk_data" | tail -n +2)"

    html_table="${html_table}</table>"

    # Output the complete table as one HTML message
    echo "[HTML]: ${html_table}"

    # Extract total reclaimable space (sum of all types)
    local total_reclaimable=$(${DOCKER} system df --format "{{.Size}}\t{{.Reclaimable}}" 2>/dev/null | awk '{
      # Parse size (e.g., "10.5GB" or "500MB")
      if ($2 ~ /GB/) {
        gsub(/GB/, "", $2)
        print $2
      } else if ($2 ~ /MB/) {
        gsub(/MB/, "", $2)
        print $2 / 1024
      }
    }' | awk '{s+=$1} END {print s}')

    # Check if we have enough space (need at least 15GB for safe build with LaTeX)
    if [ -n "$total_reclaimable" ]; then
      local reclaimable_int=$(echo "$total_reclaimable" | awk '{printf "%.0f", $1}')

      if [ "$reclaimable_int" -lt 15 ]; then
        echo "[HTML]: <p><i class='fa-solid fa-triangle-exclamation' style='color: #FFA500;'></i><b>Warning:</b> Docker may be running low on disk space.</p>"
        echo "[HTML]: <p>Building containers with LaTeX requires approximately 15-20GB of free space.</p>"
        echo "[HTML]: <p>Consider running: <code>docker system prune -a</code> to free up space, or increase Docker Desktop's disk limit in Settings → Resources → Disk image size.</p>"
      fi
    fi
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color:#61b0ff;'></i>Unable to check Docker disk usage. Proceeding with build...</p>"
  fi
}

# Function to build Docker Compose with the option whether to use cache or not
build_docker_compose() {
  local _lock_acquired=false
  if acquire_build_lock; then _lock_acquired=true; fi
  if [ "${_lock_acquired}" != true ]; then
    return 1
  fi

  # Set trap to release lock on interrupt
  # Note: We don't exit here, just release lock and let the signal propagate
  trap 'release_build_lock' INT TERM

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
  
  # Get help export ID for build arg
  local help_export_id="initial_empty_database"
  local help_export_file="${ROOT_DIR}/services/pgvector/help_data/export_id.txt"
  if [ -f "$help_export_file" ]; then
    help_export_id=$(cat "$help_export_file")
  fi

  # Calculate gems fingerprint for Ruby container labeling
  local gems_fingerprint
  if [ -f "${ROOT_DIR}/services/ruby/Gemfile" ] && [ -f "${ROOT_DIR}/services/ruby/monadic.gemspec" ]; then
    gems_fingerprint=$(cat "${ROOT_DIR}/services/ruby/Gemfile" "${ROOT_DIR}/services/ruby/monadic.gemspec" | sha256sum | awk '{print $1}')
  else
    gems_fingerprint="unknown"
  fi
  export GEMS_FINGERPRINT="$gems_fingerprint"

  # Read install options for Python container build args
  local config_env="${HOME_DIR}/monadic/config/env"
  read_cfg_bool() {
    local key="$1"; local defval="${2:-false}"
    local val=""
    val=$(eval echo "\$${key}")
    if [ -z "$val" ] && [ -f "$config_env" ]; then
      local line=$(grep -E "^${key}=" "$config_env" | tail -n1 || true)
      if [ -n "$line" ]; then
        val=${line#*=}
        val=${val%""}; val=${val#""}
      fi
    fi
    if [ -n "$val" ]; then
      val=$(echo "$val" | tr '[:upper:]' '[:lower:]')
      case "$val" in
        true|1|yes|on) echo "true";;
        false|0|no|off|"") echo "false";;
        *) echo "$defval";;
      esac
      return
    fi
    echo "$defval"
  }

  local INSTALL_LATEX=$(read_cfg_bool "INSTALL_LATEX" false)
  local PYOPT_NLTK=$(read_cfg_bool "PYOPT_NLTK" false)
  local PYOPT_SPACY=$(read_cfg_bool "PYOPT_SPACY" false)
  local PYOPT_SCIKIT=$(read_cfg_bool "PYOPT_SCIKIT" false)
  local PYOPT_GENSIM=$(read_cfg_bool "PYOPT_GENSIM" false)
  local PYOPT_LIBROSA=$(read_cfg_bool "PYOPT_LIBROSA" false)
  local PYOPT_MEDIAPIPE=$(read_cfg_bool "PYOPT_MEDIAPIPE" false)
  local PYOPT_TRANSFORMERS=$(read_cfg_bool "PYOPT_TRANSFORMERS" false)
  local IMGOPT_IMAGEMAGICK=$(read_cfg_bool "IMGOPT_IMAGEMAGICK" false)

  # Export install options and gems fingerprint as environment variables for compose.yml to reference
  export INSTALL_LATEX PYOPT_NLTK PYOPT_SPACY PYOPT_SCIKIT PYOPT_GENSIM PYOPT_LIBROSA PYOPT_MEDIAPIPE PYOPT_TRANSFORMERS IMGOPT_IMAGEMAGICK

  # Debug: log the actual command being executed
  local build_start_time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "======================================" >> "${log_file}"
  echo "[BUILD START] ${build_start_time}" >> "${log_file}"
  echo "======================================" >> "${log_file}"
  echo "[DEBUG] DOCKER='${DOCKER}'" >> "${log_file}"
  echo "[DEBUG] COMPOSE_FILES='${COMPOSE_FILES}'" >> "${log_file}"
  echo "[DEBUG] REPORTING='${REPORTING}'" >> "${log_file}"
  echo "[DEBUG] use_cache='${use_cache}'" >> "${log_file}"
  echo "[DEBUG] Install options: INSTALL_LATEX=${INSTALL_LATEX} PYOPT_NLTK=${PYOPT_NLTK} PYOPT_SPACY=${PYOPT_SPACY} PYOPT_SCIKIT=${PYOPT_SCIKIT} PYOPT_GENSIM=${PYOPT_GENSIM} PYOPT_LIBROSA=${PYOPT_LIBROSA} PYOPT_MEDIAPIPE=${PYOPT_MEDIAPIPE} PYOPT_TRANSFORMERS=${PYOPT_TRANSFORMERS} IMGOPT_IMAGEMAGICK=${IMGOPT_IMAGEMAGICK}" >> "${log_file}"
  echo "" >> "${log_file}"
  echo "[DISK USAGE BEFORE BUILD]" >> "${log_file}"
  ${DOCKER} system df >> "${log_file}" 2>&1 || echo "Unable to get disk usage" >> "${log_file}"
  echo "" >> "${log_file}"
  echo "[DEBUG] Executing: HELP_EXPORT_ID='${help_export_id}' '${DOCKER}' compose ${REPORTING} ${COMPOSE_FILES} build ${use_cache}" >> "${log_file}"
  echo "======================================" >> "${log_file}"
  echo "" >> "${log_file}"

  # Execute docker compose build and redirect output to log file with or without cache
  local build_start_epoch=$(date +%s)
  eval "HELP_EXPORT_ID=\"${help_export_id}\" \"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} build ${use_cache} 2>&1 | tee -a \"${log_file}\""
  local build_status=${PIPESTATUS[0]}
  local build_end_epoch=$(date +%s)
  local build_duration=$((build_end_epoch - build_start_epoch))

  # Log build completion status
  local build_end_time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "" >> "${log_file}"
  echo "======================================" >> "${log_file}"
  echo "[BUILD END] ${build_end_time}" >> "${log_file}"
  echo "[BUILD DURATION] ${build_duration} seconds" >> "${log_file}"
  echo "[BUILD STATUS] Exit code: ${build_status}" >> "${log_file}"
  echo "======================================" >> "${log_file}"

  # Check if build succeeded
  if [ $build_status -ne 0 ]; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Docker compose build failed with exit code ${build_status}.</p>"
    echo "[BUILD FAILED] Exit code: ${build_status}" >> "${log_file}"
    release_build_lock
    trap - INT TERM
    return 1
  fi

  # Verify all required images were created
  echo "" >> "${log_file}"
  echo "[IMAGE VERIFICATION]" >> "${log_file}"
  local all_images_exist=true
  for image in "yohasebe/monadic-chat" "yohasebe/python" "yohasebe/pgvector"; do
    if ! ${DOCKER} images | grep -q "${image}"; then
      all_images_exist=false
      echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Required image '${image}' was not created during build.</p>"
      echo "  ✗ ${image} - NOT FOUND" >> "${log_file}"
    else
      local image_info=$(${DOCKER} images "${image}" --format "{{.Repository}}:{{.Tag}} ({{.Size}})" | head -1)
      echo "  ✓ ${image_info}" >> "${log_file}"
    fi
  done

  if [ "$all_images_exist" = false ]; then
    echo "[RESULT] Image verification FAILED - some required images are missing" >> "${log_file}"
    release_build_lock
    trap - INT TERM
    return 1
  else
    echo "[RESULT] Image verification PASSED - all required images present" >> "${log_file}"
  fi

  "${DOCKER}" tag yohasebe/monadic-chat:${MONADIC_VERSION} yohasebe/monadic-chat:latest

  # Save container version information after building
  save_container_versions "silent"

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
  release_build_lock

  # Clear trap before returning
  trap - INT TERM
  return 0
}

# Function to calculate hash for Dockerfile
calculate_docker_hash() {
  local dockerfile_path="$1"
  # Handle both packaged app and development paths
  local alt_path="$(echo "$dockerfile_path" | sed 's/app\.asar/app/')"
  
  if [ -f "$dockerfile_path" ]; then
    shasum -a 256 "$dockerfile_path" | awk '{print $1}'
  elif [ -f "$alt_path" ]; then
    shasum -a 256 "$alt_path" | awk '{print $1}'
  else
    echo "file_not_found"
  fi
}

# Function to save container versions to JSON file in user's config directory
save_container_versions() {
  local config_dir="${HOME_DIR}/monadic/config"
  mkdir -p "$config_dir"
  
  local json_file="${config_dir}/container_versions.json"
  
  # Calculate hash for Python container Dockerfile
  local python_dockerfile="${ROOT_DIR}/services/python/Dockerfile"
  local python_hash=$(calculate_docker_hash "$python_dockerfile")
  
  # Calculate hash for Selenium container Dockerfile
  local selenium_dockerfile="${ROOT_DIR}/services/selenium/Dockerfile"
  local selenium_hash=$(calculate_docker_hash "$selenium_dockerfile")
  
  # Calculate hash for PGVector container Dockerfile
  local pgvector_dockerfile="${ROOT_DIR}/services/pgvector/Dockerfile"
  local pgvector_hash=$(calculate_docker_hash "$pgvector_dockerfile")
  
  # Get help export ID if it exists
  local help_export_id="initial_empty_database"
  local help_export_file="${ROOT_DIR}/services/pgvector/help_data/export_id.txt"
  if [ -f "$help_export_file" ]; then
    help_export_id=$(cat "$help_export_file")
  fi
  
  # Create JSON file with version information and hashes
  cat <<EOF > "$json_file"
{
  "version": "${MONADIC_VERSION}",
  "python_hash": "${python_hash}",
  "selenium_hash": "${selenium_hash}",
  "pgvector_hash": "${pgvector_hash}",
  "help_export_id": "${help_export_id}"
}
EOF
  
  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Container version information saved to config directory.</p>"
  fi
}

# Function to check if Dockerfiles have changed since last build
check_dockerfiles_changed() {
  local config_dir="${HOME_DIR}/monadic/config"
  local json_file="${config_dir}/container_versions.json"
  
  # If the file doesn't exist, consider everything changed
  if [ ! -f "$json_file" ]; then
    return 0 # true - changes detected
  fi
  
  # Read stored hashes from JSON file
  local stored_version=$(grep -o '"version": *"[^"]*"' "$json_file" | cut -d'"' -f4)
  local stored_python_hash=$(grep -o '"python_hash": *"[^"]*"' "$json_file" | cut -d'"' -f4)
  local stored_selenium_hash=$(grep -o '"selenium_hash": *"[^"]*"' "$json_file" | cut -d'"' -f4)
  local stored_pgvector_hash=$(grep -o '"pgvector_hash": *"[^"]*"' "$json_file" | cut -d'"' -f4)
  local stored_help_export_id=$(grep -o '"help_export_id": *"[^"]*"' "$json_file" | cut -d'"' -f4)
  
  # Calculate current hashes
  local python_dockerfile="${ROOT_DIR}/services/python/Dockerfile"
  local python_hash=$(calculate_docker_hash "$python_dockerfile")
  
  local selenium_dockerfile="${ROOT_DIR}/services/selenium/Dockerfile"
  local selenium_hash=$(calculate_docker_hash "$selenium_dockerfile")
  
  local pgvector_dockerfile="${ROOT_DIR}/services/pgvector/Dockerfile"
  local pgvector_hash=$(calculate_docker_hash "$pgvector_dockerfile")
  
  # Get current help export ID
  local help_export_id="initial_empty_database"
  local help_export_file="${ROOT_DIR}/services/pgvector/help_data/export_id.txt"
  if [ -f "$help_export_file" ]; then
    help_export_id=$(cat "$help_export_file")
  fi
  
  # If any hash is different, return true (changes detected)
  if [[ "$stored_python_hash" != "$python_hash" || "$stored_selenium_hash" != "$selenium_hash" || "$stored_pgvector_hash" != "$pgvector_hash" || "$stored_help_export_id" != "$help_export_id" ]]; then
    return 0 # true - changes detected
  fi
  
  # If we get here, no changes detected
  return 1 # false - no changes detected
}

# Function to start Docker Compose
start_docker_compose() {
  set_docker_compose

  # Load environment variables from env file
  local config_dir="${HOME_DIR}/monadic/config"
  local env_file="${config_dir}/env"
  local host_binding="0.0.0.0" # Default to all interfaces
  
  if [ -f "${env_file}" ]; then
    # Read HOST_BINDING from env file if it exists
    if grep -q "HOST_BINDING=" "${env_file}"; then
      host_binding=$(grep "HOST_BINDING=" "${env_file}" | cut -d'=' -f2)
    fi
  fi
  
  # Export for docker-compose
  export HOST_BINDING="${host_binding}"

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
  local needs_ruby_rebuild=false
  local needs_user_containers=false

  # Define the list of required containers - these names must match container_name in compose.yml files
  # Note: Selenium is optional and controlled by SELENIUM_ENABLED
  local required_containers=("monadic-chat-ruby-container" "monadic-chat-python-container" "monadic-chat-pgvector-container")
  local missing_containers=()
  
  # Check if main image exists or needs update
  if ! ${DOCKER} images | grep -q "yohasebe/monadic-chat"; then
    echo "[IMAGE NOT FOUND]"
    echo "[HTML]: <p>Building all Monadic Chat containers. This may take a while...</p>"
    needs_full_rebuild=true
  elif [[ "${MONADIC_CHAT_IMAGE_TAG}" != *"${MONADIC_VERSION}"* ]]; then
    # When we have a version update, check if Dockerfiles for Python, Selenium, PGVector have changed
    if check_dockerfiles_changed; then
      remove_containers
      echo "[HTML]: <p>App update detected (v${MONADIC_CHAT_IMAGE_TAG} → v${MONADIC_VERSION}) with Dockerfile changes. Full rebuild required.</p>"
      eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} down"
      needs_full_rebuild=true
    else
      echo "[HTML]: <p>App update detected (v${MONADIC_CHAT_IMAGE_TAG} → v${MONADIC_VERSION}). Only rebuilding Ruby container.</p>"
      needs_ruby_rebuild=true
    fi
  elif [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Checking container integrity...</p>"
  fi
  
  # If we haven't decided on a full rebuild, check individual containers
  if [ "$needs_full_rebuild" = false ] && [ "$needs_ruby_rebuild" = false ]; then
    for container in "${required_containers[@]}"; do
      # Use more reliable method to check for container existence
      if ! ${DOCKER} container ls --all --format "{{.Names}}" | grep -q "^${container}$"; then
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
    
    # If we have user compose files, inform but don't build automatically
    if [ ${#user_compose_files[@]} -gt 0 ]; then
      echo "[HTML]: <p>User container configuration detected. Use 'Rebuild User Containers' from the menu to build them.</p>"
    fi
  fi
  
  # Build containers based on what we need
  if [ "$needs_full_rebuild" = true ]; then
    build_docker_compose "no-cache"
    # Record timestamp of successful full build to skip gem hash check
    date +%s > "${HOME_DIR}/monadic/log/last_full_build.txt"
    if [[ "$1" != "silent" ]]; then
      echo "[HTML]: <p>Starting all Monadic Chat containers...</p>"
    fi
  elif [ "$needs_ruby_rebuild" = true ]; then
    # Only rebuild Ruby container
    build_ruby_container
    if [[ "$1" != "silent" ]]; then
      echo "[HTML]: <p>Starting containers with updated Ruby container...</p>"
    fi
  elif [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>All containers are available. Moving on...</p>"
  fi

  # Ensure Ruby gem dependencies are up to date (fingerprint-based)
  if command -v sha256sum >/dev/null 2>&1; then
    if [ "$needs_full_rebuild" != true ] && [ "$needs_ruby_rebuild" != true ]; then
      # Skip check if we just did a full build (within last 5 minutes)
      local last_build_file="${HOME_DIR}/monadic/log/last_full_build.txt"
      local skip_gems_check=false
      if [ -f "$last_build_file" ]; then
        local last_build_time=$(cat "$last_build_file" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_build_time))
        if [ "$time_diff" -lt 300 ]; then
          skip_gems_check=true
        fi
      fi

      if [ "$skip_gems_check" != true ]; then
        # Only check when we didn't just rebuild everything
        local gems_hash current_hash image_ref
        if [ -f "${ROOT_DIR}/services/ruby/Gemfile" ] && [ -f "${ROOT_DIR}/services/ruby/monadic.gemspec" ]; then
          gems_hash=$(cat "${ROOT_DIR}/services/ruby/Gemfile" "${ROOT_DIR}/services/ruby/monadic.gemspec" | sha256sum | awk '{print $1}')
          image_ref="yohasebe/monadic-chat:${MONADIC_VERSION}"
          if ! ${DOCKER} images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image_ref}$"; then
            image_ref="yohasebe/monadic-chat:latest"
          fi
          current_hash=$(${DOCKER} inspect --format '{{ index .Config.Labels "com.monadic.gems_hash" }}' "${image_ref}" 2>/dev/null || true)
          if [ -z "$current_hash" ]; then
            echo "[HTML]: <p><i class='fa-solid fa-gem'></i> Updating Ruby gems layer (hash not found in image) . . .</p>"
            build_ruby_container
          elif [ "$current_hash" != "$gems_hash" ]; then
            echo "[HTML]: <p><i class='fa-solid fa-gem'></i> Updating Ruby gems layer (Gemfile dependencies changed) . . .</p>"
            build_ruby_container
          fi
        fi
      fi
    fi
  fi

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images
  
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p \"monadic-chat\" up -d"

  # Informational flow for smoother UX
  # Keep health check noise out of user-facing messages; log to output only
  echo "Checking orchestration health . . ."

  # Tuning knob (can be set in ~/monadic/config/env)
  AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=${AUTO_REFRESH_RUBY_ON_HEALTH_FAIL:-true}

  # Single health probe controlled by START_HEALTH_TRIES/START_HEALTH_INTERVAL
  if ! wait_for_ruby_ready; then
    # Inspect current health status (fallback to HTTP probe)
    health_status=$(${DOCKER} inspect --format='{{.State.Health.Status}}' monadic-chat-ruby-container 2>/dev/null)
    if [ -z "${health_status}" ]; then
      if curl -fsS http://localhost:4567/ >/dev/null 2>&1; then
        health_status="healthy"
      else
        health_status="unknown"
      fi
    fi

    # Only rebuild when explicitly unhealthy and auto-refresh is enabled
    if [ "${health_status}" = "unhealthy" ] && [ "${AUTO_REFRESH_RUBY_ON_HEALTH_FAIL}" = "true" ]; then
      echo "[HTML]: <p><i class='fa-solid fa-gem' style='color:#61b0ff;'></i> Refreshing Ruby control-plane for consistency. This typically takes less than a minute.</p>"
      echo "Auto-rebuilt Ruby due to failed health probe" >> "${HOME_DIR}/monadic/log/docker_startup.log"
      build_ruby_container
      eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p \"monadic-chat\" up -d"
      if wait_for_ruby_ready; then
        echo "Orchestration refreshed. Continuing startup . . ."
      fi
    fi
  fi

  # Final health summary to docker_startup.log
  {
    local startup_log="${HOME_DIR}/monadic/log/docker_startup.log"
    mkdir -p "$(dirname "${startup_log}")"
    local env_file="${HOME_DIR}/monadic/config/env"
    local tries=15
    local interval=2
    if [ -f "$env_file" ]; then
      local t=$(grep -E '^START_HEALTH_TRIES=' "$env_file" | cut -d= -f2 | tr -d '\r')
      local s=$(grep -E '^START_HEALTH_INTERVAL=' "$env_file" | cut -d= -f2 | tr -d '\r')
    fi
    if echo "$t" | grep -Eq '^[0-9]+$'; then tries="$t"; fi
    if echo "$s" | grep -Eq '^[0-9]+$'; then interval="$s"; fi
    # Probe one last time
    local state=$(${DOCKER} inspect --format='{{.State.Health.Status}}' monadic-chat-ruby-container 2>/dev/null)
    if [ "$state" != "healthy" ]; then
      if curl -fsS http://localhost:4567/ >/dev/null 2>&1; then
        state="healthy"
      else
        state="unhealthy"
      fi
    fi
    echo "Final Health Summary: ${state} (tries=${tries}, interval=${interval}s)" >> "${startup_log}"
  }

  # Helper function to read boolean config values
  read_config_bool() {
    local key="$1"
    local default_val="${2:-false}"
    if [ -f "${env_file}" ]; then
      local val=$(grep "^${key}=" "${env_file}" 2>/dev/null | cut -d= -f2 | tr -d '\r' | tr '[:upper:]' '[:lower:]')
      case "$val" in
        true|1|yes|on) echo "true";;
        false|0|no|off|"") echo "false";;
        *) echo "$default_val";;
      esac
    else
      echo "$default_val"
    fi
  }

  # Check SELENIUM_ENABLED and manage Selenium container accordingly
  local selenium_enabled=$(read_config_bool "SELENIUM_ENABLED" "true")
  if [ "$selenium_enabled" = "true" ]; then
    # Start Selenium container if enabled, image exists, and container is not already running
    if ${DOCKER} images | grep -q "yohasebe/selenium"; then
      # Check if Selenium container is already running
      if ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-selenium-container$"; then
        echo "[HTML]: <p>Starting Selenium container...</p>"
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" up -d selenium_service"

        # Restart Ruby container to update SELENIUM_AVAILABLE environment variable
        # Wait a moment for Selenium to start
        sleep 2
        echo "[HTML]: <p>Updating Ruby container to detect Selenium...</p>"
        ${DOCKER} restart monadic-chat-ruby-container > /dev/null 2>&1
      fi
    else
      echo "[HTML]: <p><i class='fa-solid fa-triangle-exclamation' style='color: #ff9800;'></i> <strong>Selenium is enabled but container image not found.</strong></p>"
      echo "[HTML]: <p>Please build the Selenium container from the menu: <strong>Actions → Build Selenium Container</strong></p>"
      echo "[HTML]: <p>The system will continue without Selenium. Web scraping features will use Tavily API as fallback.</p><hr />"
    fi
  fi
  # Note: If SELENIUM_ENABLED=false, we simply don't start it. No need to stop/remove existing containers.

  # Start Ollama container if the image exists and container is not already running (it uses a profile so needs explicit start)
  if ${DOCKER} images | grep -q "yohasebe/ollama"; then
    # Check if Ollama container is already running
    if ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-ollama-container$"; then
      echo "[HTML]: <p>Starting Ollama container...</p>"
      eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile ollama up -d ollama_service"

      # Restart Ruby container to update OLLAMA_AVAILABLE environment variable
      # Wait a moment for Ollama to start
      sleep 2
      echo "[HTML]: <p>Updating Ruby container to detect Ollama...</p>"
      ${DOCKER} restart monadic-chat-ruby-container > /dev/null 2>&1
    fi
  fi

  # Wait for all containers to be fully running before listing
  # This prevents race conditions where containers are in 'restarting' state
  sleep 3

  local containers=$("${DOCKER}" ps --filter "name=monadic-chat" --format "{{.Names}}")

  if [[ "$1" != "silent" ]] && [[ -n "${containers}" ]]; then
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
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p \"monadic-chat\" down --remove-orphans"
}

# Define a function to stop Docker Compose
stop_docker_compose() {
  # Use docker compose with project name to properly stop all containers
  # Add --timeout 5 to speed up shutdown (default is 10 seconds)
  # Docker compose v2 stops containers in parallel by default
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p \"monadic-chat\" stop --timeout 5"
}

# Function to stop a container
stop_container() {
  ${DOCKER} container stop -t 0 "$1" >/dev/null
}

# Define a function to import the database contents from an external file
import_database() {
  bash "${ROOT_DIR}/services/support_scripts/import_vector_db.sh"
}

# Define a function to export the database contents to an external file
export_database() {
  bash "${ROOT_DIR}/services/support_scripts/export_vector_db.sh"
}

# Download the latest version of Monadic Chat and rebuild the Docker image
update_monadic() {
  # Stop the Docker Compose services
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} down --remove-orphans"

  # Move to `ROOT_DIR` and download the latest version of Monadic Chat
  cd "${ROOT_DIR}" && git pull origin main

  # Build and start the Docker Compose services
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} build --no-cache"
}

# Remove the Docker image and container
remove_containers() {
  set_docker_compose
  # Stop the Docker Compose services with project name
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p \"monadic-chat\" down --remove-orphans"

  local images=$(${DOCKER} images --filter "reference=yohasebe/monadic-chat" --format "{{.Repository}}:{{.Tag}}")
  local containers=$(${DOCKER} ps -a --filter "name=monadic-chat-" --format "{{.Names}}")

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
  if ${DOCKER} container ls --all --format "{{.Names}}" | grep -q "^$1$"; then
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
  ensure_data_dir "ruby" &&

  while ! "${DOCKER}" info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  # Check disk space before building
  check_docker_disk_space

  build_ruby_container

  # rm -f "${ROOT_DIR}/services/ruby/rbsetup.sh"
  # rm -f "${ROOT_DIR}/services/python/pysetup.sh"

  if ${DOCKER} images | grep -q "monadic-chat"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of Ruby container has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
build_python_container)
  ensure_data_dir "python" &&

  while ! "${DOCKER}" info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  # Check disk space before building
  check_docker_disk_space

  build_python_container

  if ${DOCKER} images | grep -q "monadic-chat"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of Python container has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
build_user_containers)
  ensure_data_dir "" &&

  while ! "${DOCKER}" info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  # Check disk space before building
  check_docker_disk_space

  # Call build_user_containers and store the return value
  build_user_containers
  BUILD_RESULT=$?

  if [ ${BUILD_RESULT} -eq 2 ]; then
    # No user containers found (special return code)
    echo "[HTML]: <p><i class='fa-solid fa-info-circle'></i>No user containers to build.</p><hr />"
  elif ${DOCKER} images | grep -q "monadic-chat"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of user containers has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
build_selenium_container)
  ensure_data_dir "selenium" &&

  while ! "${DOCKER}" info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  build_selenium_container

  if ${DOCKER} images | grep -q "yohasebe/selenium"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of Selenium container has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Selenium container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li></ul>"
  fi
  ;;
build_ollama_container)
  ensure_data_dir "ollama" &&

  while ! "${DOCKER}" info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  build_ollama_container

  if ${DOCKER} images | grep -q "yohasebe/ollama"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of Ollama container has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Ollama container failed to build.</p><p>Please check the following log files in the share folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li></ul>"
  fi
  ;;
build)
  ensure_data_dir "" &&

  while ! "${DOCKER}" info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  # Check disk space before building
  check_docker_disk_space

  set_docker_compose
  remove_containers
  echo "[HTML]: <p>Building Monadic Chat image...</p>"
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} down"

  # Run build_docker_compose and check if it succeeded
  if build_docker_compose "no-cache"; then
    # Record timestamp of successful full build
    date +%s > "${HOME_DIR}/monadic/log/last_full_build.txt"

    # Start the containers after building
    if eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p \"monadic-chat\" up -d"; then
      # Wait a moment for containers to start
      sleep 3

      # Verify all required containers exist (get list once and check all)
      container_list=$(${DOCKER} container ls --all --format "{{.Names}}")
      if echo "$container_list" | grep -q "^monadic-chat-ruby-container$" && \
         echo "$container_list" | grep -q "^monadic-chat-python-container$" && \
         echo "$container_list" | grep -q "^monadic-chat-pgvector-container$"; then
        echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of Monadic Chat has finished and containers are started. Check the console panel for details.</p><hr />"
      else
        echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Build completed but some containers were not created.</p><p>Please check the following log files:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li></ul>"
      fi
    else
      echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Failed to start containers. Please run 'docker system df' to check disk space.</p><p>Please check the following log files:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li></ul>"
    fi
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container build failed. Please run 'docker system df' to check disk space.</p><p>Please check the following log files:</p><ul><li><code>docker_build.log</code></li></ul>"
  fi
  ;;
check)
  check_if_docker_desktop_is_running
  ;;
start)
  ensure_data_dir "" &&
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
start-selenium)
  # Start Selenium container and set SELENIUM_ENABLED=true
  # If image doesn't exist, build it first
  if ! ${DOCKER} images | grep -q "yohasebe/selenium"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color: #61b0ff;'></i>Selenium container image not found. Building automatically...</p>"

    ensure_data_dir "selenium"

    while ! "${DOCKER}" info > /dev/null 2>&1; do
      sleep ${DOCKER_CHECK_INTERVAL}
    done

    # Build Selenium container
    build_selenium_container
  fi

  # Verify image was built successfully before proceeding
  if ${DOCKER} images | grep -q "yohasebe/selenium"; then
    echo "[HTML]: <p>Starting Selenium container...</p>"
    eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" up -d selenium_service"

    # Update config
    config_env="${HOME_DIR}/monadic/config/env"
    if [ -f "$config_env" ]; then
      if grep -q "^SELENIUM_ENABLED=" "$config_env"; then
        sed -i.bak 's/^SELENIUM_ENABLED=.*/SELENIUM_ENABLED=true/' "$config_env"
      else
        echo "SELENIUM_ENABLED=true" >> "$config_env"
      fi
    else
      mkdir -p "$(dirname "$config_env")"
      echo "SELENIUM_ENABLED=true" > "$config_env"
    fi

    # Restart Ruby container to update SELENIUM_AVAILABLE
    if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-ruby-container$"; then
      sleep 2
      echo "[HTML]: <p>Updating Ruby container to detect Selenium...</p>"
      ${DOCKER} restart monadic-chat-ruby-container > /dev/null 2>&1
    fi

    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Selenium container started successfully.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Failed to build Selenium container. Please check the logs.</p><hr />"
  fi
  ;;
stop-selenium)
  # Stop Selenium container and set SELENIUM_ENABLED=false
  if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-selenium-container$"; then
    echo "[HTML]: <p>Stopping Selenium container...</p>"
    ${DOCKER} stop monadic-chat-selenium-container > /dev/null 2>&1

    # Update config
    config_env="${HOME_DIR}/monadic/config/env"
    if [ -f "$config_env" ]; then
      if grep -q "^SELENIUM_ENABLED=" "$config_env"; then
        sed -i.bak 's/^SELENIUM_ENABLED=.*/SELENIUM_ENABLED=false/' "$config_env"
      else
        echo "SELENIUM_ENABLED=false" >> "$config_env"
      fi
    else
      mkdir -p "$(dirname "$config_env")"
      echo "SELENIUM_ENABLED=false" > "$config_env"
    fi

    # Restart Ruby container to update SELENIUM_AVAILABLE
    if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-ruby-container$"; then
      echo "[HTML]: <p>Updating Ruby container after Selenium stop...</p>"
      ${DOCKER} restart monadic-chat-ruby-container > /dev/null 2>&1
    fi

    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Selenium container stopped successfully.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color: #61b0ff;'></i>Selenium container is not running.</p><hr />"

    # Still update config
    config_env="${HOME_DIR}/monadic/config/env"
    if [ -f "$config_env" ]; then
      if grep -q "^SELENIUM_ENABLED=" "$config_env"; then
        sed -i.bak 's/^SELENIUM_ENABLED=.*/SELENIUM_ENABLED=false/' "$config_env"
      else
        echo "SELENIUM_ENABLED=false" >> "$config_env"
      fi
    fi
  fi
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

# Wait for Ruby container to be healthy/ready
wait_for_ruby_ready() {
  local max_tries=${1:-20}
  local sleep_sec=${2:-2}
  # Allow overrides via ~/monadic/config/env
  local env_file="${HOME_DIR}/monadic/config/env"
  if [ -f "$env_file" ]; then
    local t=$(grep -E '^START_HEALTH_TRIES=' "$env_file" | cut -d= -f2 | tr -d '\r')
    local s=$(grep -E '^START_HEALTH_INTERVAL=' "$env_file" | cut -d= -f2 | tr -d '\r')
    if echo "$t" | grep -Eq '^[0-9]+$'; then max_tries="$t"; fi
    if echo "$s" | grep -Eq '^[0-9]+$'; then sleep_sec="$s"; fi
  fi
  local tries=0
  while [ $tries -lt $max_tries ]; do
    local state=$(${DOCKER} inspect --format='{{.State.Health.Status}}' monadic-chat-ruby-container 2>/dev/null)
    if [ "$state" = "healthy" ]; then
      return 0
    fi
    # As a fallback, try an HTTP probe if running locally
    if curl -fsS http://localhost:4567/ >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries+1))
    sleep "$sleep_sec"
  done
  return 1
}
