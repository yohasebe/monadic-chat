#!/bin/bash

# Add /usr/local/bin to the PATH
export PATH=${PATH}:/usr/local/bin

# Read version from version.rb (reliable source in both dev and packaged app)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VERSION_FILE="${SCRIPT_DIR}/services/ruby/lib/monadic/version.rb"

if [ -f "$VERSION_FILE" ]; then
  # Extract version from Ruby file: VERSION = "1.0.0-beta.4"
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

# Compose profiles (see profiles: keys in docker/services/*/compose.yml).
#
# Two distinct sets, per the principle "feature flags gate startup, never
# teardown":
#
# ALL_PROFILES_UP — flag-gated set for start/build/pull. Opt-in services
# (privacy, extractor) are included only when their flag is on, so disabled
# features are never pulled or started.
ALL_PROFILES_UP="--profile python --profile selenium"
if [[ "${PRIVACY_FILTER:-true}" == "true" ]]; then
  ALL_PROFILES_UP="${ALL_PROFILES_UP} --profile privacy"
fi
# Extractor (Knowledge Base Quality Pack) is opt-in. Including its profile
# here makes the standard lifecycle cover it: started with `up -d`,
# stopped/removed with everything else, and pulled during the full build.
# Without this, nothing started the container after an app restart and the
# Library import quality path silently fell back to pdfplumber.
if [[ "${EXTRACTOR_SERVICE:-false}" == "true" ]]; then
  ALL_PROFILES_UP="${ALL_PROFILES_UP} --profile extractor"
fi
#
# ALL_PROFILES_DOWN — unconditional set for stop/down/remove. A container
# started while a flag was on must still be stopped after the flag is turned
# off, so teardown must never depend on current flag values (otherwise the
# container is orphaned and keeps running outside the managed lifecycle).
# Covered by spec/unit/compose_profile_completeness_spec.rb, which checks this
# line against the profiles: keys in docker/services/*/compose.yml.
ALL_PROFILES_DOWN="--profile python --profile selenium --profile privacy --profile extractor"

# Define the path to the root directory
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
HOME_DIR=$(eval echo ~${SUDO_USER})

# Exported for the compose.build.yml overlays (explicit local builds of the
# prebuilt services), whose build contexts are interpolated from this var.
export MONADIC_ROOT_DIR="${ROOT_DIR}"

# Runtime settings consumed by compose interpolation — NOT build args.
# PRIVACY_LANGS/EXTRACTOR_LANGS/EXTRACTOR_OCR select languages at runtime
# (all models are baked into the images); MONADIC_IMAGE_TAG selects the
# prebuilt image tag (default latest; :<version> for pinning, :dev for
# the dev-branch builds). Electron passes them via the process env; for
# CLI/dev invocations (e.g. `ensure-service` shelled out from a host
# Ruby process) fall back to ~/monadic/config/env so containers start
# with the user's selection instead of the defaults.
for _key in PRIVACY_LANGS EXTRACTOR_LANGS EXTRACTOR_OCR MONADIC_IMAGE_TAG; do
  if [ -z "$(eval echo "\$${_key}")" ] && [ -f "${HOME_DIR}/monadic/config/env" ]; then
    _line=$(grep -E "^${_key}=" "${HOME_DIR}/monadic/config/env" | tail -n1 | tr -d '\r' || true)
    if [ -n "$_line" ]; then
      _val=${_line#*=}; _val=${_val%\"}; _val=${_val#\"}
      export ${_key}="${_val}"
    fi
  fi
done
unset _key _line _val

# Path to the user's config env file (KEY=VALUE lines, quotes optional).
CONFIG_ENV_FILE="${HOME_DIR}/monadic/config/env"

# Single source of truth for the Python container build options.
# Adding a new PYOPT_*/INSTALL_*/IMGOPT_* requires:
#   1. Append to PY_OPTIONS below
#   2. Add the matching ARG declaration + RUN conditional in
#      docker/services/python/Dockerfile (and the compose.yml ARG
#      passthrough)
#   3. Add the matching entry in app/install_options.config.js
#   4. Add the HTML checkbox row in app/settings.html
# See docs_dev/install_options_ssot.md for the full checklist.
PY_OPTIONS=(INSTALL_LATEX PYOPT_NLTK PYOPT_SPACY PYOPT_GENSIM PYOPT_LIBROSA PYOPT_MEDIAPIPE PYOPT_TRANSFORMERS IMGOPT_IMAGEMAGICK)

# Read a boolean KEY (quotes trimmed, normalized to "true"/"false").
# Checks environment variables first (passed by Electron), then falls back
# to the config file. Falls back to $2 (default "false") when unset.
read_cfg_bool() {
  local key="$1"; local defval="${2:-false}"
  local val=""

  # Using eval for indirect variable reference for better compatibility
  val=$(eval echo "\$${key}")

  if [ -z "$val" ] && [ -f "$CONFIG_ENV_FILE" ]; then
    local line=$(grep -E "^${key}=" "$CONFIG_ENV_FILE" | tail -n1 || true)
    if [ -n "$line" ]; then
      val=${line#*=}
      val=${val%\"}; val=${val#\"}
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

# Record the build-options snapshots for python/privacy/extractor. Called
# after every successful build path (per-container builds and the full
# build) so the Settings UI option-diff always has a baseline. These files
# are an option-diff baseline ONLY — "built or not" is derived from the
# docker image store (see the image-status subcommand), never from their
# existence.
write_build_options_snapshots() {
  local log_dir="${HOME_DIR}/monadic/log"
  mkdir -p "${log_dir}"
  local key
  : > "${log_dir}/python_build_options.txt"
  for key in "${PY_OPTIONS[@]}"; do
    echo "${key}=$(read_cfg_bool "$key" false)" >> "${log_dir}/python_build_options.txt"
  done
  echo "PRIVACY_FILTER=$(read_cfg_bool "PRIVACY_FILTER" true)" > "${log_dir}/privacy_build_options.txt"
  echo "EXTRACTOR_SERVICE=$(read_cfg_bool "EXTRACTOR_SERVICE" false)" > "${log_dir}/extractor_build_options.txt"
}

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

set_docker_compose() {
  local home_paths=("${HOME_DIR}/monadic/data/services" "~/monadic/data/services")

  for i in "${!home_paths[@]}"; do
    home_paths[$i]=$(eval echo "${home_paths[$i]}")
    home_paths[$i]=$(normalize_path "${home_paths[$i]}")
  done

  # Add app-specific service directories (~/monadic/data/apps/*/services)
  local apps_dir=$(eval echo "~/monadic/data/apps")
  if [ -d "$apps_dir" ]; then
    for app_svc in "$apps_dir"/*/services; do
      [ -d "$app_svc" ] && home_paths+=("$(normalize_path "$app_svc")")
    done
  fi

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
  - "${ROOT_DIR}/services/qdrant/compose.yml"
  - "${ROOT_DIR}/services/embeddings/compose.yml"
  - "${ROOT_DIR}/services/python/compose.yml"
  - "${ROOT_DIR}/services/selenium/compose.yml"
  - "${ROOT_DIR}/services/privacy/compose.yml"
  - "${ROOT_DIR}/services/extractor/compose.yml"
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

  # Dev mode overlays: when Ruby runs on the host (rake server:debug), it
  # talks to the supporting containers over loopback, so we must expose
  # their ports. In production these stay internal to the Docker network.
  if [[ "${MONADIC_DEV:-false}" == "true" ]]; then
    COMPOSE_FILES="${COMPOSE_FILES} -f \"${ROOT_DIR}/services/qdrant/compose.dev.yml\""
    COMPOSE_FILES="${COMPOSE_FILES} -f \"${ROOT_DIR}/services/embeddings/compose.dev.yml\""
    if [[ "${PRIVACY_FILTER:-true}" == "true" ]]; then
      COMPOSE_FILES="${COMPOSE_FILES} -f \"${ROOT_DIR}/services/privacy/compose.dev.yml\""
    fi
    if [[ "${EXTRACTOR_SERVICE:-false}" == "true" ]]; then
      COMPOSE_FILES="${COMPOSE_FILES} -f \"${ROOT_DIR}/services/extractor/compose.dev.yml\""
    fi
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

  safe_rm "${log_dir}/command.log"
  safe_rm "${log_dir}/jupyter.log"

  # remove extra.log if it exists
  safe_rm "${log_dir}/extra.log"

  # clear rbsetup.sh and pysetup.sh in the root dir by overwriting default comments
  echo "# This file is overwritten by rbsetup.sh prepared by the user in the shared folder." > "${ROOT_DIR}/services/ruby/rbsetup.sh"
  echo "# This file is overwritten by pysetup.sh prepared by the user in the shared folder." > "${ROOT_DIR}/services/python/pysetup.sh"

  safe_touch "${config_dir}/env"

  # Only show Ruby setup message when building Ruby container or all containers
  if [[ -f "${config_dir}/rbsetup.sh" && -s "${config_dir}/rbsetup.sh" ]]; then
    cp -f "${config_dir}/rbsetup.sh" "${ROOT_DIR}/services/ruby/rbsetup.sh"
    if [[ "$container_type" == "ruby" || "$container_type" == "" ]]; then
      echo "[HTML]: <p><i class='fa-solid fa-gem' style='color:#CC342D;'></i> Custom Ruby setup script (rbsetup.sh) detected and will be used.</p>"
    fi
  fi

  # Only show Python setup message when building Python container or all containers
  if [[ -f "${config_dir}/pysetup.sh" && -s "${config_dir}/pysetup.sh" ]]; then
    cp -f "${config_dir}/pysetup.sh" "${ROOT_DIR}/services/python/pysetup.sh"
    if [[ "$container_type" == "python" || "$container_type" == "" ]]; then
      echo "[HTML]: <p><i class='fa-brands fa-python' style='color:#3776AB;'></i> Custom Python setup script (pysetup.sh) detected and will be used.</p>"
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
  # Pre-build JS bundle on host if node + esbuild are available (minified),
  # otherwise Dockerfile fallback will concatenate inside the container.
  local bundle_script="${ROOT_DIR}/../scripts/build_js_bundle.mjs"
  if command -v node >/dev/null 2>&1 && [ -f "${bundle_script}" ]; then
    node "${bundle_script}" 2>/dev/null || true
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

  # Save container version information to prevent unnecessary full rebuilds on next start
  save_container_versions "silent"

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

  # Resolve install options from user's env via the global read_cfg_bool;
  # the option list is the global PY_OPTIONS (SSOT, defined near the top
  # of this file).

  # Read current values into separate locals (kept as locals, not an
  # associative array, so they remain visible to the JSON/options-file
  # heredocs further down via "${!key}" style expansion).
  local key
  for key in "${PY_OPTIONS[@]}"; do
    local "${key}"="$(read_cfg_bool "$key" false)"
  done

  # Report option changes since the last build (informational — the cache
  # strategy below no longer depends on it: BuildKit keys conditional RUN
  # layers on their ARG values, and the prebuilt default image supplies
  # the heavy common layers via --cache-from).
  local prev_options_file="${logs_dir}/python_build_options.txt"
  local changed_options=""
  if [ -f "$prev_options_file" ]; then
    for key in "${PY_OPTIONS[@]}"; do
      local prev_val
      prev_val=$(grep "^${key}=" "$prev_options_file" 2>/dev/null | cut -d= -f2)
      if [ "${!key}" != "$prev_val" ]; then
        changed_options+="${key}(${prev_val}→${!key}) "
      fi
    done
    if [ -n "$changed_options" ]; then
      echo "[INFO] Install options changed: ${changed_options}" | tee -a "${build_log}"
    fi
  fi

  # All-defaults detection: with every option false, the CI-published
  # default image IS the desired image — pull it instead of building.
  local all_defaults=true
  for key in "${PY_OPTIONS[@]}"; do
    if [ "${!key}" = "true" ]; then all_defaults=false; break; fi
  done

  local build_args=
  for key in "${PY_OPTIONS[@]}"; do
    build_args+=" --build-arg ${key}=${!key}"
  done

  # Acquire the image into a temporary tag for atomic swap. Three paths:
  #   1. FORCE_REBUILD (menu manual build) → local --no-cache build, the
  #      documented clean-rebuild escape hatch.
  #   2. All options false → pull the prebuilt default image (seconds to
  #      minutes instead of a 15-30 min build). Falls back to a local
  #      build when the pull fails (offline).
  #   3. Any option true → local build with --cache-from the prebuilt
  #      default (pulled best-effort): its inline cache supplies the
  #      heavy apt + pip base layers, so the build only pays for the
  #      enabled option layers.
  local prebuilt_image="ghcr.io/yohasebe/monadic-python:${MONADIC_IMAGE_TAG:-latest}"
  local dockerfile="${ROOT_DIR}/services/python/Dockerfile"
  local ts=$(date +%Y%m%d_%H%M%S)
  local temp_tag="yohasebe/monadic-chat:python-build-${ts}"
  local image_ready=false
  local cache_flags=""

  if [ "${FORCE_REBUILD:-false}" = "true" ]; then
    echo "[INFO] Force rebuild requested by user, using --no-cache" | tee -a "${build_log}"
    cache_flags="--no-cache"
  elif [ "$all_defaults" = "true" ]; then
    echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> No install options selected — downloading the prebuilt Python image (~0.9 GB, one time) instead of building . . .</p>" | tee -a "${build_log}"
    if ${DOCKER} pull "${prebuilt_image}" 2>&1 | tee -a "${build_log}"; then
      ${DOCKER} tag "${prebuilt_image}" "${temp_tag}"
      image_ready=true
    else
      echo "[WARN] Prebuilt image pull failed; falling back to local build" | tee -a "${build_log}"
    fi
  else
    # Best-effort cache source; the build works without it.
    if ! ${DOCKER} images -q "${prebuilt_image}" | grep -q .; then
      echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> Downloading the default Python image (~0.9 GB, one time) to use as a build cache . . .</p>" | tee -a "${build_log}"
    fi
    ${DOCKER} pull "${prebuilt_image}" 2>&1 | tee -a "${build_log}" || true
    if ${DOCKER} images -q "${prebuilt_image}" | grep -q .; then
      cache_flags="--cache-from ${prebuilt_image}"
      echo "[INFO] Using prebuilt default image as build cache source" | tee -a "${build_log}"
    fi
  fi

  if [ "$image_ready" != "true" ]; then
    echo "[HTML]: <p>Starting Python image build (atomic) . . .</p>" | tee -a "${build_log}"
    # IMPORTANT: cache_flags must not be quoted so an empty value expands to nothing
    if ! ${DOCKER} build ${cache_flags} -f "${dockerfile}" ${build_args} -t "${temp_tag}" "${ROOT_DIR}/services/python" 2>&1 | tee -a "${build_log}"; then
      echo "[ERROR] Docker build failed" | tee -a "${build_log}"
      echo "[BUILD_COMPLETE] failed"
      release_build_lock
      return 1
    fi
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
         "\"options\": {\"INSTALL_LATEX\": ${INSTALL_LATEX}, \"IMGOPT_IMAGEMAGICK\": ${IMGOPT_IMAGEMAGICK}, \"PYOPT_NLTK\": ${PYOPT_NLTK}, \"PYOPT_SPACY\": ${PYOPT_SPACY}, \"PYOPT_GENSIM\": ${PYOPT_GENSIM}, \"PYOPT_LIBROSA\": ${PYOPT_LIBROSA}, \"PYOPT_MEDIAPIPE\": ${PYOPT_MEDIAPIPE}, \"PYOPT_TRANSFORMERS\": ${PYOPT_TRANSFORMERS}} ,"
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

  # Build the meta.json "build_args" block from the same PY_OPTIONS
  # array that drove `--build-arg` so the two cannot drift.
  local meta_build_args=""
  local i
  for ((i = 0; i < ${#PY_OPTIONS[@]}; i++)); do
    local mk="${PY_OPTIONS[i]}"
    if [ ${i} -eq 0 ]; then
      meta_build_args+="    \"${mk}\": ${!mk}"
    else
      meta_build_args+=$',\n    "'"${mk}"'": '"${!mk}"
    fi
  done

  # Write meta.json
  cat > "${meta_json}" <<META
{
  "timestamp": "${ts}",
  "monadic_version": "${MONADIC_VERSION}",
  "host_os": "${HOST_OS}",
  "image_temp_tag": "${temp_tag}",
  "build_args": {
${meta_build_args}
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

    # Save current install options for future comparison — driven by
    # the same PY_OPTIONS array so order and coverage stay in sync.
    : > "${prev_options_file}"
    for key in "${PY_OPTIONS[@]}"; do
      echo "${key}=${!key}" >> "${prev_options_file}"
    done
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
    echo "Please check the following log files under: ${logs_dir}"
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
  echo "Build logs are available under: ${logs_dir}"
  echo "[BUILD_COMPLETE] success"

  # Save container version information to prevent unnecessary full rebuilds on next start
  save_container_versions "silent"

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

# Function to build Selenium container.
# Production: the image is prebuilt and user-independent — pull (or
# refresh) it from ghcr.io instead of building. Development
# (MONADIC_DEV=true): build locally via the explicit build overlay.
build_selenium_container() {
  local _lock_acquired=false
  if acquire_build_lock; then _lock_acquired=true; fi
  if [ "${_lock_acquired}" != true ]; then
    return 1
  fi
  local log_file="${HOME_DIR}/monadic/log/docker_build.log"

  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${log_file}")"

  set_docker_compose
  if [[ "${MONADIC_DEV:-false}" == "true" ]]; then
    echo "Building Selenium container..." | tee -a "${log_file}"
    eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -f \"${ROOT_DIR}/services/selenium/compose.build.yml\" -p monadic-chat --profile selenium build selenium_service" 2>&1 | tee -a "${log_file}"
  else
    echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> Downloading the prebuilt browser automation image (~1.5 GB on first download) . . .</p>"
    eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p monadic-chat --profile selenium pull selenium_service" 2>&1 | tee -a "${log_file}"
  fi

  # Check if the image is now present
  if ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-selenium"; then
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
  local home_paths=("${HOME_DIR}/monadic/data/services" "~/monadic/data/services")
  for i in "${!home_paths[@]}"; do
    home_paths[$i]=$(eval echo "${home_paths[$i]}")
    home_paths[$i]=$(normalize_path "${home_paths[$i]}")
  done

  # Add app-specific service directories (~/monadic/data/apps/*/services)
  local apps_dir=$(eval echo "~/monadic/data/apps")
  if [ -d "$apps_dir" ]; then
    for app_svc in "$apps_dir"/*/services; do
      [ -d "$app_svc" ] && home_paths+=("$(normalize_path "$app_svc")")
    done
  fi

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

    # Note: We no longer warn based on reclaimable space, as it's not a reliable
    # indicator of available disk space. Docker will fail with clear error messages
    # if it actually runs out of space during builds.
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
  
  # Get help export ID for build-arg cache invalidation (Phase 4 build
  # script writes this when the prebuilt help DB JSON dump changes).
  local help_export_id="initial_empty_database"
  local help_export_file="${ROOT_DIR}/services/ruby/help_data/export_id.txt"
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

  # Read install options for Python container build args (global read_cfg_bool)
  local INSTALL_LATEX=$(read_cfg_bool "INSTALL_LATEX" false)
  local PYOPT_NLTK=$(read_cfg_bool "PYOPT_NLTK" false)
  local PYOPT_SPACY=$(read_cfg_bool "PYOPT_SPACY" false)
  local PYOPT_GENSIM=$(read_cfg_bool "PYOPT_GENSIM" false)
  local PYOPT_LIBROSA=$(read_cfg_bool "PYOPT_LIBROSA" false)
  local PYOPT_MEDIAPIPE=$(read_cfg_bool "PYOPT_MEDIAPIPE" false)
  local PYOPT_TRANSFORMERS=$(read_cfg_bool "PYOPT_TRANSFORMERS" false)
  local IMGOPT_IMAGEMAGICK=$(read_cfg_bool "IMGOPT_IMAGEMAGICK" false)

  # Export install options and gems fingerprint as environment variables for compose.yml to reference
  export INSTALL_LATEX PYOPT_NLTK PYOPT_SPACY PYOPT_GENSIM PYOPT_LIBROSA PYOPT_MEDIAPIPE PYOPT_TRANSFORMERS IMGOPT_IMAGEMAGICK

  # Debug: log the actual command being executed
  local build_start_time=$(date '+%Y-%m-%d %H:%M:%S')
  echo "======================================" >> "${log_file}"
  echo "[BUILD START] ${build_start_time}" >> "${log_file}"
  echo "======================================" >> "${log_file}"
  echo "[DEBUG] DOCKER='${DOCKER}'" >> "${log_file}"
  echo "[DEBUG] COMPOSE_FILES='${COMPOSE_FILES}'" >> "${log_file}"
  echo "[DEBUG] REPORTING='${REPORTING}'" >> "${log_file}"
  echo "[DEBUG] use_cache='${use_cache}'" >> "${log_file}"
  echo "[DEBUG] Install options: INSTALL_LATEX=${INSTALL_LATEX} PYOPT_NLTK=${PYOPT_NLTK} PYOPT_SPACY=${PYOPT_SPACY} PYOPT_GENSIM=${PYOPT_GENSIM} PYOPT_LIBROSA=${PYOPT_LIBROSA} PYOPT_MEDIAPIPE=${PYOPT_MEDIAPIPE} PYOPT_TRANSFORMERS=${PYOPT_TRANSFORMERS} IMGOPT_IMAGEMAGICK=${IMGOPT_IMAGEMAGICK}" >> "${log_file}"
  echo "" >> "${log_file}"
  echo "[DISK USAGE BEFORE BUILD]" >> "${log_file}"
  ${DOCKER} system df >> "${log_file}" 2>&1 || echo "Unable to get disk usage" >> "${log_file}"
  echo "" >> "${log_file}"
  echo "[DEBUG] GEMS_FINGERPRINT='${gems_fingerprint}'" >> "${log_file}"
  echo "[DEBUG] Executing: HELP_EXPORT_ID='${help_export_id}' GEMS_FINGERPRINT='${gems_fingerprint}' '${DOCKER}' compose ${REPORTING} ${COMPOSE_FILES} build ${use_cache}" >> "${log_file}"
  echo "======================================" >> "${log_file}"
  echo "" >> "${log_file}"

  # Pull the prebuilt service images BEFORE building. embeddings, qdrant,
  # selenium, privacy and extractor (when opted in) have no local build:
  # configuration (consumed directly); the python default image is pulled
  # best-effort as the --cache-from source for the compose-driven python
  # build (see cache_from in its compose.yml). The verification step after
  # the build fails when a required pull did not produce an image.
  local pull_services="embeddings_service qdrant_service selenium_service"
  local pull_note="text embeddings (~1.1 GB), vector database (~0.3 GB), browser automation (~1.5 GB)"
  if [[ "${PRIVACY_FILTER:-true}" == "true" ]]; then
    pull_services="${pull_services} privacy_service"
    pull_note="${pull_note}, privacy filter (~0.7 GB)"
  fi
  if [[ "${EXTRACTOR_SERVICE:-false}" == "true" ]]; then
    pull_services="${pull_services} extractor_service"
    pull_note="${pull_note}, knowledge base quality pack (~1.3 GB)"
  fi
  # Byte-level progress is not visible in this console (non-TTY pulls only
  # report per-layer milestones), so announce what is being downloaded and
  # its rough size up front to avoid a long silent wait.
  echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> Downloading prebuilt service images: ${pull_note}. This happens once; later updates only fetch changed layers.</p>"
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_UP} pull ${pull_services} 2>&1 | tee -a \"${log_file}\""
  echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> Downloading the default Python image (~0.9 GB) as a build cache source . . .</p>"
  ${DOCKER} pull "ghcr.io/yohasebe/monadic-python:${MONADIC_IMAGE_TAG:-latest}" 2>&1 | tee -a "${log_file}" || true

  # Execute docker compose build and redirect output to log file with or without cache
  # Include all profiles so profiled services (python, selenium) are also built
  local build_start_epoch=$(date +%s)
  eval "HELP_EXPORT_ID=\"${help_export_id}\" GEMS_FINGERPRINT=\"${gems_fingerprint}\" \"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_UP} build ${use_cache} 2>&1 | tee -a \"${log_file}\""
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
  for image in "yohasebe/monadic-chat" "yohasebe/python" "ghcr.io/yohasebe/monadic-embeddings" "ghcr.io/yohasebe/monadic-qdrant" "ghcr.io/yohasebe/monadic-selenium"; do
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

  # The full build covers python/privacy/extractor too, so record the same
  # option snapshots the per-container builds write. Without this, a fresh
  # install that went through the full build had no baseline and the
  # Settings option-diff started from nothing.
  write_build_options_snapshots

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
  
  # Calculate hash for embeddings container Dockerfile
  local embeddings_dockerfile="${ROOT_DIR}/services/embeddings/Dockerfile"
  local embeddings_hash=$(calculate_docker_hash "$embeddings_dockerfile")

  # Get help export ID if it exists (Phase 4 build script writes this)
  local help_export_id="initial_empty_database"
  local help_export_file="${ROOT_DIR}/services/ruby/help_data/export_id.txt"
  if [ -f "$help_export_file" ]; then
    help_export_id=$(cat "$help_export_file")
  fi

  # Create JSON file with version information and hashes
  cat <<EOF > "$json_file"
{
  "version": "${MONADIC_VERSION}",
  "python_hash": "${python_hash}",
  "selenium_hash": "${selenium_hash}",
  "embeddings_hash": "${embeddings_hash}",
  "help_export_id": "${help_export_id}"
}
EOF
  
  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Container version information saved to config directory.</p>"
  fi
}

# Extract the string value of KEY from a flat JSON file. Tolerates
# arbitrary whitespace and key order; prints nothing when the key is
# missing or the file is malformed — callers compare against a freshly
# computed value, so a parse failure can only register as "changed"
# (an extra rebuild), never as "unchanged" (a skipped one). No jq/node
# dependency: this script runs on end-user hosts where neither is
# guaranteed. The only writer is save_container_versions above; if it
# ever emits nested JSON, replace this with a real parser.
json_string_value() {
  local file="$1" key="$2"
  sed -nE 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$file" 2>/dev/null | head -n1
}

# Function to check if Dockerfiles have changed since last build
# Sets global variables for individual container changes:
#   PYTHON_DOCKERFILE_CHANGED, SELENIUM_DOCKERFILE_CHANGED, EMBEDDINGS_DOCKERFILE_CHANGED
# Returns 0 (true) if any changes detected, 1 (false) otherwise
check_dockerfiles_changed() {
  local config_dir="${HOME_DIR}/monadic/config"
  local json_file="${config_dir}/container_versions.json"

  # Initialize change flags (global variables for use in start_docker_compose)
  PYTHON_DOCKERFILE_CHANGED=false
  SELENIUM_DOCKERFILE_CHANGED=false
  EMBEDDINGS_DOCKERFILE_CHANGED=false

  # Calculate current hashes
  local python_dockerfile="${ROOT_DIR}/services/python/Dockerfile"
  local python_hash=$(calculate_docker_hash "$python_dockerfile")

  local selenium_dockerfile="${ROOT_DIR}/services/selenium/Dockerfile"
  local selenium_hash=$(calculate_docker_hash "$selenium_dockerfile")

  local embeddings_dockerfile="${ROOT_DIR}/services/embeddings/Dockerfile"
  local embeddings_hash=$(calculate_docker_hash "$embeddings_dockerfile")

  # Get current help export ID
  local help_export_id="initial_empty_database"
  local help_export_file="${ROOT_DIR}/services/ruby/help_data/export_id.txt"
  if [ -f "$help_export_file" ]; then
    help_export_id=$(cat "$help_export_file")
  fi

  # If the file doesn't exist, consider everything changed
  if [ ! -f "$json_file" ]; then
    PYTHON_DOCKERFILE_CHANGED=true
    SELENIUM_DOCKERFILE_CHANGED=true
    EMBEDDINGS_DOCKERFILE_CHANGED=true
    return 0 # true - changes detected
  fi

  # Read stored hashes from JSON file (see json_string_value: parse
  # failures yield "" which never equals a real hash, so a malformed or
  # reshaped file can only cause an extra rebuild, never a skipped one)
  local stored_python_hash=$(json_string_value "$json_file" "python_hash")
  local stored_selenium_hash=$(json_string_value "$json_file" "selenium_hash")
  local stored_embeddings_hash=$(json_string_value "$json_file" "embeddings_hash")
  local stored_help_export_id=$(json_string_value "$json_file" "help_export_id")

  # Check each container individually
  if [[ "$stored_python_hash" != "$python_hash" ]]; then
    PYTHON_DOCKERFILE_CHANGED=true
  fi
  if [[ "$stored_selenium_hash" != "$selenium_hash" ]]; then
    SELENIUM_DOCKERFILE_CHANGED=true
  fi
  # Embeddings refresh is needed only when its Dockerfile changed. The
  # help DB JSON dump lives in the RUBY image (help_data/, keyed by
  # HELP_EXPORT_ID there), NOT in the embeddings image — an earlier
  # design baked it into embeddings and this condition used to include
  # the export ID, causing pointless embeddings refreshes on every help
  # DB update.
  if [[ "$stored_embeddings_hash" != "$embeddings_hash" ]]; then
    EMBEDDINGS_DOCKERFILE_CHANGED=true
  fi

  # Return true if any changes detected
  if [[ "$PYTHON_DOCKERFILE_CHANGED" = true || "$SELENIUM_DOCKERFILE_CHANGED" = true || "$EMBEDDINGS_DOCKERFILE_CHANGED" = true ]]; then
    return 0 # true - changes detected
  fi

  # If we get here, no changes detected
  return 1 # false - no changes detected
}

# Function to start Docker Compose
# Migration cleanup: remove the pre-ghcr locally built service images
# (compose now references ghcr.io/yohasebe/monadic-*, so the old local
# tags are orphaned ~5GB of disk). `docker rmi` without -f fails
# harmlessly when a stopped container still references an image; the
# next start retries after `down` has removed those containers.
remove_legacy_prebuilt_images() {
  local img
  # yohasebe/selenium (locally built) and qdrant/qdrant (upstream pull)
  # joined this list when both moved to ghcr.io prebuilt images
  # (monadic-selenium / monadic-qdrant) in beta.21.
  for img in yohasebe/monadic-privacy yohasebe/monadic-embeddings yohasebe/monadic-extractor yohasebe/selenium qdrant/qdrant; do
    if ${DOCKER} images -q "${img}" 2>/dev/null | grep -q .; then
      echo "[INFO] Removing legacy local image ${img} (replaced by ghcr.io prebuilt)"
      ${DOCKER} rmi "${img}" >/dev/null 2>&1 || true
    fi
  done
}

start_docker_compose() {
  set_docker_compose
  remove_legacy_prebuilt_images

  # Load environment variables from env file
  local config_dir="${HOME_DIR}/monadic/config"
  local env_file="${config_dir}/env"
  local host_binding="127.0.0.1" # Default to localhost only for security
  local distributed_mode="off"

  if [ -f "${env_file}" ]; then
    # Read DISTRIBUTED_MODE from env file
    if grep -q "DISTRIBUTED_MODE=" "${env_file}"; then
      distributed_mode=$(grep "DISTRIBUTED_MODE=" "${env_file}" | cut -d'=' -f2)
    fi

    # Read HOST_BINDING from env file if explicitly set
    if grep -q "HOST_BINDING=" "${env_file}"; then
      host_binding=$(grep "HOST_BINDING=" "${env_file}" | cut -d'=' -f2)
    elif [ "${distributed_mode}" = "server" ]; then
      # Auto-enable network binding for server mode
      host_binding="0.0.0.0"
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

  # get yohasebe/monadic-chat image tag (prefer version-format tags like X.Y.Z)
  # Use --format to get clean output, then filter for version-like tags
  local all_tags=$(${DOCKER} images --filter "reference=yohasebe/monadic-chat" --format "{{.Tag}}" 2>/dev/null | tr -d '\r')

  # First try to find a tag that looks like a version number (X.Y.Z or X.Y.Z-suffix)
  MONADIC_CHAT_IMAGE_TAG=""
  while IFS= read -r tag; do
    # Skip empty lines and 'latest' tag
    [ -z "$tag" ] || [ "$tag" = "latest" ] && continue
    # Check if tag matches version pattern (e.g., 1.0.0, 1.0.0-beta.1)
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      MONADIC_CHAT_IMAGE_TAG="$tag"
      break
    fi
  done <<< "$all_tags"

  # If no version-format tag found, use the first non-latest tag
  if [ -z "${MONADIC_CHAT_IMAGE_TAG}" ]; then
    MONADIC_CHAT_IMAGE_TAG=$(echo "$all_tags" | grep -v "^latest$" | head -1)
  fi

  if [ -z "${MONADIC_CHAT_IMAGE_TAG}" ]; then
    MONADIC_CHAT_IMAGE_TAG="None"
  fi

  if [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Monadic Chat app v${MONADIC_VERSION} <i class='fa-solid fa-arrow-right-arrow-left'></i> Container image v${MONADIC_CHAT_IMAGE_TAG}</p>"
  fi

  # Check for all required containers and services
  local needs_full_rebuild=false
  local needs_selective_rebuild=false
  local needs_ruby_rebuild=false
  local needs_user_containers=false

  # Define the list of required containers - these names must match container_name in compose.yml files
  local required_containers=("monadic-chat-ruby-container" "monadic-chat-python-container" "monadic-chat-qdrant-container" "monadic-chat-embeddings-container" "monadic-chat-selenium-container")
  local missing_containers=()

  # Check if main image exists or needs update
  if ! ${DOCKER} images | grep -q "yohasebe/monadic-chat"; then
    echo "[IMAGE NOT FOUND]"
    echo "[HTML]: <p>Building all Monadic Chat containers. This may take a while...</p>"
    needs_full_rebuild=true
  elif [[ "${MONADIC_CHAT_IMAGE_TAG}" != *"${MONADIC_VERSION}"* ]]; then
    # When we have a version update, check if Dockerfiles for Python, Selenium, PGVector have changed
    if check_dockerfiles_changed; then
      # Selective rebuild: only rebuild containers with changed Dockerfiles
      local changed_list=""
      if [ "$PYTHON_DOCKERFILE_CHANGED" = true ]; then changed_list="${changed_list}Python "; fi
      if [ "$SELENIUM_DOCKERFILE_CHANGED" = true ]; then changed_list="${changed_list}Selenium "; fi
      if [ "$EMBEDDINGS_DOCKERFILE_CHANGED" = true ]; then changed_list="${changed_list}Embeddings "; fi
      echo "[HTML]: <p>App update detected (v${MONADIC_CHAT_IMAGE_TAG} → v${MONADIC_VERSION}). Rebuilding: Ruby ${changed_list}</p>"
      needs_selective_rebuild=true
    else
      echo "[HTML]: <p>App update detected (v${MONADIC_CHAT_IMAGE_TAG} → v${MONADIC_VERSION}). Only rebuilding Ruby container.</p>"
      needs_ruby_rebuild=true
    fi
  elif [[ "$1" != "silent" ]]; then
    echo "[HTML]: <p>Checking container integrity...</p>"
  fi
  
  # If we haven't decided on a full rebuild, check individual containers
  if [ "$needs_full_rebuild" = false ] && [ "$needs_selective_rebuild" = false ] && [ "$needs_ruby_rebuild" = false ]; then
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
    local home_paths=("${HOME_DIR}/monadic/data/services" "~/monadic/data/services")
    local user_compose_files=()

    for i in "${!home_paths[@]}"; do
      home_paths[$i]=$(eval echo "${home_paths[$i]}")
      home_paths[$i]=$(normalize_path "${home_paths[$i]}")
    done

    # Add app-specific service directories (~/monadic/data/apps/*/services)
    local apps_dir=$(eval echo "~/monadic/data/apps")
    if [ -d "$apps_dir" ]; then
      for app_svc in "$apps_dir"/*/services; do
        [ -d "$app_svc" ] && home_paths+=("$(normalize_path "$app_svc")")
      done
    fi

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
    if [[ "$1" != "silent" ]]; then
      echo "[HTML]: <p>Starting all Monadic Chat containers...</p>"
    fi
  elif [ "$needs_selective_rebuild" = true ]; then
    # Selective rebuild: only rebuild containers with changed Dockerfiles (--no-cache)
    # Ruby is always rebuilt on version update
    build_ruby_container

    # Rebuild only the containers whose Dockerfiles have changed
    if [ "$PYTHON_DOCKERFILE_CHANGED" = true ]; then
      # A Dockerfile change ships with an app update whose CI run already
      # published a matching default image — pull it as the cache source
      # so the rebuild only pays for the user's enabled option layers
      # (cache_from in the python compose.yml).
      echo "[HTML]: <p><i class='fa-brands fa-python'></i> Rebuilding Python container (Dockerfile changed)... Downloading the updated default image as a cache source first.</p>"
      ${DOCKER} pull "ghcr.io/yohasebe/monadic-python:${MONADIC_IMAGE_TAG:-latest}" 2>&1 | tee -a "${HOME_DIR}/monadic/log/docker_build.log" || true
      eval "\"${DOCKER}\" compose ${REPORTING} -f \"${ROOT_DIR}/services/python/compose.yml\" build python_service 2>&1" | tee -a "${HOME_DIR}/monadic/log/docker_build.log"
    fi
    if [ "$SELENIUM_DOCKERFILE_CHANGED" = true ]; then
      echo "[HTML]: <p><i class='fa-solid fa-globe'></i> Rebuilding Selenium container (Dockerfile changed)...</p>"
      eval "\"${DOCKER}\" compose ${REPORTING} -f \"${ROOT_DIR}/services/selenium/compose.yml\" build --no-cache selenium_service 2>&1" | tee -a "${HOME_DIR}/monadic/log/docker_build.log"
    fi
    if [ "$EMBEDDINGS_DOCKERFILE_CHANGED" = true ]; then
      # Embeddings is prebuilt: a Dockerfile change ships with an app update
      # whose CI run already published the matching image — pull it instead
      # of building locally.
      echo "[HTML]: <p><i class='fa-solid fa-database'></i> Refreshing Embeddings container image (Dockerfile changed)...</p>"
      eval "\"${DOCKER}\" compose ${REPORTING} -f \"${ROOT_DIR}/services/embeddings/compose.yml\" pull embeddings_service 2>&1" | tee -a "${HOME_DIR}/monadic/log/docker_build.log"
    fi

    # Save updated container versions after selective rebuild
    save_container_versions "silent"

    if [[ "$1" != "silent" ]]; then
      echo "[HTML]: <p>Starting containers with updated images...</p>"
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

  # Ensure Ruby gem dependencies are up to date (hash-based comparison only)
  # This check is skipped if we already did a full, selective, or Ruby rebuild above
  if command -v sha256sum >/dev/null 2>&1; then
    if [ "$needs_full_rebuild" != true ] && [ "$needs_selective_rebuild" != true ] && [ "$needs_ruby_rebuild" != true ]; then
      local gems_hash current_hash image_ref
      if [ -f "${ROOT_DIR}/services/ruby/Gemfile" ] && [ -f "${ROOT_DIR}/services/ruby/monadic.gemspec" ]; then
        gems_hash=$(cat "${ROOT_DIR}/services/ruby/Gemfile" "${ROOT_DIR}/services/ruby/monadic.gemspec" | sha256sum | awk '{print $1}')
        image_ref="yohasebe/monadic-chat:${MONADIC_VERSION}"
        if ! ${DOCKER} images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image_ref}$"; then
          image_ref="yohasebe/monadic-chat:latest"
        fi
        current_hash=$(${DOCKER} inspect --format '{{ index .Config.Labels "com.monadic.gems_hash" }}' "${image_ref}" 2>/dev/null || true)

        # Only rebuild if hash is missing or different - skip entirely if hashes match
        if [ -z "$current_hash" ]; then
          echo "[HTML]: <p><i class='fa-solid fa-gem'></i> Updating Ruby gems layer (hash not found in image) . . .</p>"
          build_ruby_container
        elif [ "$current_hash" != "$gems_hash" ]; then
          echo "[HTML]: <p><i class='fa-solid fa-gem'></i> Updating Ruby gems layer (Gemfile dependencies changed) . . .</p>"
          build_ruby_container
        fi
        # If hashes match, skip build entirely - no docker build command is executed
      fi
    fi
  fi

  remove_older_images yohasebe/monadic-chat
  remove_project_dangling_images

  # When start is reached without a build (images mostly present), a
  # missing opt-in extractor image would be pulled silently by `up -d`
  # (its progress goes to stderr, invisible in the app console) — announce
  # the one-time download first.
  if [[ "${EXTRACTOR_SERVICE:-false}" == "true" ]] && ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-extractor"; then
    echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> Downloading the prebuilt Knowledge Base Quality Pack image (~1.3 GB, one time) . . .</p>"
  fi

  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_UP} -p \"monadic-chat\" up -d"

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
      eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_UP} -p \"monadic-chat\" up -d"
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

  # Ensure Selenium container is running if the image exists
  if ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-selenium"; then
    if ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-selenium-container$"; then
      echo "[HTML]: <p>Starting Selenium container...</p>"
      eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile selenium up -d selenium_service"
      # Ruby detects Selenium dynamically via WebAutomation.available? (TTL cache)
      # No restart needed — availability is checked on each tool invocation and UI load
    fi
  else
    echo "[HTML]: <p><i class='fa-solid fa-triangle-exclamation' style='color: #ff9800;'></i> <strong>Selenium container image not found.</strong></p>"
    echo "[HTML]: <p>To download the Selenium image, first stop Monadic Chat, then run <strong>Actions → Build All</strong> from the menu (it is enabled only while stopped).</p>"
    echo "[HTML]: <p>The system will continue without Selenium. Web scraping features will use Tavily API as fallback.</p><hr />"
  fi

  # Brief wait for container list to stabilize, then enumerate
  local wait_end=$((SECONDS + 5))
  while [ $SECONDS -lt $wait_end ]; do
    # Check if any monadic-chat container is still in 'restarting' state
    if ! ${DOCKER} ps --filter "name=monadic-chat" --format "{{.Status}}" 2>/dev/null | grep -qi "restarting"; then
      break
    fi
    sleep 0.5
  done

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

# Function to stop Docker Compose (includes all profiled services)
down_docker_compose() {
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_DOWN} -p \"monadic-chat\" down --remove-orphans"
}

# Define a function to stop Docker Compose (includes all profiled services)
stop_docker_compose() {
  # Use docker compose with project name to properly stop all containers.
  # Docker compose v2 stops containers in parallel by default.
  #
  # --timeout 2 (was 5, default is 10) — Monadic Chat's containers release
  # quickly on SIGTERM (Falcon / PGVector / Jupyter all handle it cleanly in
  # well under a second). A 2s SIGTERM-to-SIGKILL grace window keeps the
  # total Restart-Now-to-relaunch duration predictable and inside the UX
  # threshold for "feels responsive". The value is not zero because we
  # still want databases to flush inflight writes gracefully before kill.
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_DOWN} -p \"monadic-chat\" stop --timeout 2"
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
  # Stop all Docker Compose services (including profiled services)
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_DOWN} down --remove-orphans"

  # Move to `ROOT_DIR` and download the latest version of Monadic Chat
  cd "${ROOT_DIR}" && git pull origin main

  # Build all Docker Compose services (including profiled services)
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_UP} build --no-cache"
}

# Remove the Docker image and container
remove_containers() {
  set_docker_compose
  # Stop all Docker Compose services with project name (including profiled services)
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_DOWN} -p \"monadic-chat\" down --remove-orphans"

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
  remove_volume monadic-chat-qdrant-data
  remove_volume monadic-chat-embeddings-models
  # Legacy: remove_volume calls are idempotent and ignore missing volumes,
  # so this still cleans up after users upgrading from older PGVector-based
  # installs.
  remove_volume monadic-chat-pgvector-data
}

# Uninstall-only deep clean of service images. Deliberately NOT part of
# remove_containers: that function is shared with the rebuild paths (full
# build calls it first), where deleting the prebuilt service images would
# force a multi-GB re-download on every rebuild. Uninstall, however,
# must leave no images behind — docs/getting-started/uninstallation.md
# enumerates exactly these. The substring match in remove_image covers
# both the ghcr.io/yohasebe/monadic-* prebuilt repos and the legacy
# locally built yohasebe/monadic-* names with one call each.
remove_service_images() {
  remove_image "yohasebe/monadic-embeddings"
  remove_image "yohasebe/monadic-privacy"
  remove_image "yohasebe/monadic-extractor"
  remove_image "yohasebe/monadic-python"
  remove_image "yohasebe/monadic-qdrant"
  remove_image "yohasebe/monadic-selenium"
  remove_image "yohasebe/python"
  # Legacy names from before the ghcr.io unification (locally built
  # selenium, upstream qdrant) — still present on upgraded installs.
  remove_image "yohasebe/selenium"
  remove_image "qdrant/qdrant"
  remove_image "yohasebe/pgvector"
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

# Export the Qdrant data volume to ~/monadic/data/monadic-qdrant.tar.gz.
# Stops the qdrant container temporarily so the on-disk state is consistent
# (Qdrant flushes WAL on shutdown), then restarts it.
export_db() {
  local container_name="monadic-chat-qdrant-container"
  local volume_name="monadic-chat-qdrant-data"

  if ! ${DOCKER} volume inspect "${volume_name}" >/dev/null 2>&1; then
    echo "[HTML]: <p>Qdrant volume '${volume_name}' not found. Please start Monadic Chat first.</p><hr />"
    return 1
  fi

  # Stop qdrant for a consistent volume snapshot.
  local was_running=false
  if ${DOCKER} ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    was_running=true
    ${DOCKER} stop "${container_name}" >/dev/null 2>&1
  fi

  # Use a one-shot alpine container to read from the qdrant volume and write
  # a gzip tarball into the host shared data directory.
  ${DOCKER} run --rm \
    -v "${volume_name}:/source:ro" \
    -v "${HOME_DIR}/monadic/data:/dest" \
    alpine:latest \
    sh -c "cd /source && tar czf /dest/monadic-qdrant.tar.gz ."
  local exit_code=$?

  if [ "$was_running" = true ]; then
    ${DOCKER} start "${container_name}" >/dev/null 2>&1
  fi

  if [ $exit_code -eq 0 ]; then
    echo "[HTML]: <p>Document DB has been exported to 'monadic-qdrant.tar.gz' successfully!</p><hr />"
  else
    echo "[HTML]: <p>Document DB export failed!</p><hr />"
  fi
}

# Import a previously exported Qdrant tarball, replacing the current volume.
# Stops the container, wipes the volume, untars, and restarts.
import_db() {
  local container_name="monadic-chat-qdrant-container"
  local volume_name="monadic-chat-qdrant-data"
  local tarball="${HOME_DIR}/monadic/data/monadic-qdrant.tar.gz"

  if [ ! -f "$tarball" ]; then
    echo "[HTML]: <p>Document DB file 'monadic-qdrant.tar.gz' does not exist. Please place the export file in the shared folder first.</p><hr />"
    return 1
  fi

  if ! ${DOCKER} volume inspect "${volume_name}" >/dev/null 2>&1; then
    echo "[HTML]: <p>Qdrant volume '${volume_name}' not found. Please start Monadic Chat once before importing.</p><hr />"
    return 1
  fi

  # Stop qdrant so the import sees a quiet filesystem.
  local was_running=false
  if ${DOCKER} ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
    was_running=true
    ${DOCKER} stop "${container_name}" >/dev/null 2>&1
  fi

  # Wipe the volume and untar the export into it.
  ${DOCKER} run --rm \
    -v "${volume_name}:/dest" \
    -v "${HOME_DIR}/monadic/data:/source:ro" \
    alpine:latest \
    sh -c "rm -rf /dest/* /dest/.* 2>/dev/null; cd /dest && tar xzf /source/monadic-qdrant.tar.gz"
  local exit_code=$?

  if [ "$was_running" = true ]; then
    ${DOCKER} start "${container_name}" >/dev/null 2>&1
  fi

  if [ $exit_code -eq 0 ]; then
    echo "[HTML]: <p>Document DB has been imported successfully!</p><hr />"
  else
    echo "[HTML]: <p>Document DB import failed! Please check the export file.</p><hr />"
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
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p>"
    echo "[HTML]: <p>Please check the following log files in the shared folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
# `build_python_container` is the explicit menu action (Electron passes
# FORCE_REBUILD=true → clean --no-cache rebuild). The `_update` alias is
# used by the start-time pending-build gate and option changes: Electron
# does NOT force a rebuild there, letting the smart path inside
# build_python_container pull the prebuilt default image or build with
# --cache-from.
build_python_container|build_python_container_update)
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
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p>"
    echo "[HTML]: <p>Please check the following log files in the shared folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
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
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p>"
    echo "[HTML]: <p>Please check the following log files in the shared folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li><li><code>server.log</code></li></ul>"
  fi
  ;;
build_selenium_container)
  ensure_data_dir "selenium" &&

  while ! "${DOCKER}" info > /dev/null 2>&1; do
    sleep ${DOCKER_CHECK_INTERVAL}
  done

  build_selenium_container

  if ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-selenium"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of Selenium container has finished: Check the console panel for details.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p>"
    echo "[HTML]: <p>Please check the following log files in the shared folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li></ul>"
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
  eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_DOWN} down"

  # Run build_docker_compose and check if it succeeded
  if build_docker_compose "no-cache"; then
    # Start all containers (including profiled services) after full build
    if eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} ${ALL_PROFILES_UP} -p \"monadic-chat\" up -d"; then
      # Wait a moment for containers to start
      sleep 3

      # Verify all containers exist (including profiled services started by full build)
      container_list=$(${DOCKER} container ls --all --format "{{.Names}}")
      if echo "$container_list" | grep -q "^monadic-chat-ruby-container$" && \
         echo "$container_list" | grep -q "^monadic-chat-python-container$" && \
         echo "$container_list" | grep -q "^monadic-chat-qdrant-container$" && \
         echo "$container_list" | grep -q "^monadic-chat-embeddings-container$" && \
         echo "$container_list" | grep -q "^monadic-chat-selenium-container$"; then
        echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Build of Monadic Chat has finished and containers are started. Check the console panel for details.</p><hr />"
        echo "[SERVER STARTED]"
        docker_start_log "silent"
      else
        echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p>"
        echo "[HTML]: <p>Please check the following log files in the shared folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li></ul>"
      fi
    else
      echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p>"
      echo "[HTML]: <p>Please check the following log files in the shared folder:</p><ul><li><code>docker_build.log</code></li><li><code>docker_start.log</code></li></ul>"
    fi
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Container failed to build.</p>"
    echo "[HTML]: <p>Please check the following log files in the shared folder:</p><ul><li><code>docker_build.log</code></li></ul>"
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
  # Start Selenium container (build if missing)
  if ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-selenium"; then
    echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color: #61b0ff;'></i>Selenium container image not found. Building automatically...</p>"

    ensure_data_dir "selenium"

    while ! "${DOCKER}" info > /dev/null 2>&1; do
      sleep ${DOCKER_CHECK_INTERVAL}
    done

    # Build Selenium container
    build_selenium_container
  fi

  # Verify image was built successfully before proceeding
  if ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-selenium"; then
    echo "[HTML]: <p>Starting Selenium container...</p>"
    eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile selenium up -d selenium_service"

    # Ruby detects Selenium dynamically via WebAutomation.available? (TTL cache)
    # No restart needed — availability is checked on each tool invocation and UI load

    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Selenium container started successfully.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-exclamation' style='color: red;'></i>Failed to build Selenium container. Please check the logs.</p><hr />"
  fi
  ;;
stop-selenium)
  # Stop Selenium container
  if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-selenium-container$"; then
    echo "[HTML]: <p>Stopping Selenium container...</p>"
    ${DOCKER} stop monadic-chat-selenium-container > /dev/null 2>&1

    echo "[HTML]: <p><i class='fa-solid fa-circle-check' style='color: #22ad50;'></i>Selenium container stopped successfully.</p><hr />"
  else
    echo "[HTML]: <p><i class='fa-solid fa-circle-info' style='color: #61b0ff;'></i>Selenium container is not running.</p><hr />"
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
  remove_service_images &&
  echo "[HTML]: <p>Containers and images have been removed successfully.</p><p>Now you can quit Monadic Chat and uninstall the app safely.</p>"
  ;;
export-db)
  export_db
  ;;
import-db)
  import_db
  ;;
image-status)
  # Machine-readable presence of the per-user-built / opt-in service images.
  # Consumed by the Electron start gate (computePendingContainerBuilds) to
  # decide "not yet built" from the actual docker image store rather than
  # snapshot files, which can drift from reality (full builds historically
  # wrote no snapshots; users prune images). Output contract:
  #   DOCKER_NOT_RUNNING        — daemon unreachable, caller must not infer
  #   <name>=present|absent     — one line per service below
  if ! ${DOCKER} info >/dev/null 2>&1; then
    echo "DOCKER_NOT_RUNNING"
  else
    for _pair in "python=yohasebe/python" "privacy=ghcr.io/yohasebe/monadic-privacy" "extractor=ghcr.io/yohasebe/monadic-extractor"; do
      _name="${_pair%%=*}"
      _image="${_pair#*=}"
      if ${DOCKER} images -q "${_image}" 2>/dev/null | grep -q .; then
        echo "${_name}=present"
      else
        echo "${_name}=absent"
      fi
    done
    unset _pair _name _image
  fi
  ;;
ensure-service)
  # On-demand container startup for profiled services.
  # Called by Ruby when an app requires extra services.
  # Usage: monadic.sh ensure-service python|selenium|privacy|qdrant|embeddings
  SERVICE_NAME="${2:-}"
  set_docker_compose
  case "$SERVICE_NAME" in
    python)
      if ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-python-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile python up -d python_service" 2>/dev/null
        echo "STARTED"
      else
        echo "ALREADY_RUNNING"
      fi
      ;;
    selenium)
      # Selenium requires Python; ensure both are running.
      # The image is prebuilt (ghcr.io); when missing, pull it instead of
      # reporting not-built.
      if ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-selenium"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile selenium pull selenium_service" 2>/dev/null
      fi
      if ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-python-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile python up -d python_service" 2>/dev/null
      fi
      if ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-selenium"; then
        echo "SELENIUM_NOT_BUILT"
      elif ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-selenium-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile selenium up -d selenium_service" 2>/dev/null
        echo "STARTED"
      else
        echo "ALREADY_RUNNING"
      fi
      ;;
    qdrant)
      # Vector storage for Help / PDF KB. Always available (no opt-in flag).
      # The image is prebuilt (ghcr.io); when missing, pull it instead of
      # reporting not-built.
      if ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-qdrant"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" pull qdrant_service" 2>/dev/null
      fi
      if ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-qdrant"; then
        echo "QDRANT_NOT_BUILT"
      elif ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-qdrant-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile qdrant up -d qdrant_service" 2>/dev/null
        echo "STARTED"
      else
        echo "ALREADY_RUNNING"
      fi
      ;;
    embeddings)
      # multilingual-e5-base inference. Required by Help / PDF KB.
      # The image is prebuilt (ghcr.io); when missing, pull it instead of
      # reporting not-built.
      if ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-embeddings"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" pull embeddings_service" 2>/dev/null
      fi
      if ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-embeddings"; then
        echo "EMBEDDINGS_NOT_BUILT"
      elif ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-embeddings-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile embeddings up -d embeddings_service" 2>/dev/null
        echo "STARTED"
      else
        echo "ALREADY_RUNNING"
      fi
      ;;
    privacy)
      # Privacy filter is part of the default service set. PRIVACY_FILTER=false
      # opts out at runtime. The image is prebuilt (ghcr.io); when missing,
      # pull it instead of reporting not-built.
      if [[ "${PRIVACY_FILTER:-true}" == "true" ]] && ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-privacy"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile privacy pull privacy_service" 2>/dev/null
      fi
      if [[ "${PRIVACY_FILTER:-true}" != "true" ]]; then
        echo "PRIVACY_DISABLED"
      elif ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-privacy"; then
        echo "PRIVACY_NOT_BUILT"
      elif ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-privacy-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile privacy up -d privacy_service" 2>/dev/null
        echo "STARTED"
      else
        echo "ALREADY_RUNNING"
      fi
      ;;
    extractor)
      # Extractor (Knowledge Base Quality Pack) is opt-in via EXTRACTOR_SERVICE=true.
      # The image is prebuilt (ghcr.io); when missing, pull it instead of
      # reporting not-built. Returns EXTRACTOR_DISABLED / EXTRACTOR_NOT_BUILT
      # so the caller can prompt the user via Settings → Install Options.
      if [[ "${EXTRACTOR_SERVICE:-false}" == "true" ]] && ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-extractor"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile extractor pull extractor_service" 2>/dev/null
      fi
      if [[ "${EXTRACTOR_SERVICE:-false}" != "true" ]]; then
        echo "EXTRACTOR_DISABLED"
      elif ! ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-extractor"; then
        echo "EXTRACTOR_NOT_BUILT"
      elif ! ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-extractor-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile extractor up -d extractor_service" 2>/dev/null
        echo "STARTED"
      else
        echo "ALREADY_RUNNING"
      fi
      ;;
    *)
      echo "Unknown service: ${SERVICE_NAME}" >&2
      ;;
  esac
  ;;
refresh-service)
  # Re-apply runtime env to a running profiled service. `compose up -d`
  # recreates the container only when its effective config changed (e.g.
  # PRIVACY_LANGS/EXTRACTOR_LANGS edited in Settings), so this is cheap to
  # call after a settings save. When the container is not running this is
  # a no-op — the next on-demand start picks up the new env anyway.
  # Usage: monadic.sh refresh-service privacy|extractor
  SERVICE_NAME="${2:-}"
  set_docker_compose
  case "$SERVICE_NAME" in
    privacy)
      if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-privacy-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile privacy up -d privacy_service" 2>/dev/null
        echo "REFRESHED"
      else
        echo "NOT_RUNNING"
      fi
      ;;
    extractor)
      if ${DOCKER} ps --format '{{.Names}}' | grep -q "^monadic-chat-extractor-container$"; then
        eval "\"${DOCKER}\" compose ${COMPOSE_FILES} -p \"monadic-chat\" --profile extractor up -d extractor_service" 2>/dev/null
        echo "REFRESHED"
      else
        echo "NOT_RUNNING"
      fi
      ;;
    *)
      echo "Unknown service: ${SERVICE_NAME}" >&2
      ;;
  esac
  ;;
build_privacy_container)
  # Build the privacy container (all languages are baked in; PRIVACY_LANGS
  # is a runtime setting applied via compose `environment:`).
  # Triggered from the Settings → Actions panel (Electron menu).
  if [[ "${PRIVACY_FILTER:-true}" != "true" ]]; then
    echo "[INFO] Privacy Filter is disabled (PRIVACY_FILTER=false). Skipping build."
    exit 0
  fi
  ensure_data_dir "privacy" 2>/dev/null || true
  set_docker_compose
  build_log="${HOME_DIR}/monadic/log/docker_build.log"
  if [[ "${MONADIC_DEV:-false}" == "true" ]]; then
    # Development: build locally from source via the explicit build overlay.
    echo "[INFO] Building privacy container..."
    eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -f \"${ROOT_DIR}/services/privacy/compose.build.yml\" -p monadic-chat --profile privacy build privacy_service" 2>&1 | tee -a "${build_log}"
  else
    # Production: the image is prebuilt and user-independent — pull (or
    # refresh) it from ghcr.io instead of building. Output markers below
    # ("Privacy container build succeeded/failed") are kept stable because
    # the Electron UI matches on them.
    echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> Downloading the prebuilt Privacy Filter image (~0.7 GB on first download) . . .</p>"
    eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p monadic-chat --profile privacy pull privacy_service" 2>&1 | tee -a "${build_log}"
  fi
  if ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-privacy"; then
    echo "[INFO] Privacy container build succeeded."
    # Snapshot marker: the Settings UI uses the existence of this file to
    # distinguish "not yet built" from "built". Language selection is no
    # longer build-relevant, so no language line is recorded.
    prev_options_file="${HOME_DIR}/monadic/log/privacy_build_options.txt"
    {
      echo "PRIVACY_FILTER=${PRIVACY_FILTER:-false}"
    } > "$prev_options_file"
    echo "[INFO] Saved build options to ${prev_options_file}"
  else
    echo "[ERROR] Privacy container build failed. See ${build_log}."
    exit 1
  fi
  ;;
build_extractor_container)
  # Build the extractor container (Knowledge Base Quality Pack: Docling + RapidOCR).
  # Triggered from the Settings → Actions panel after the user opts in via
  # Install Options. Image is large (~3GB) and download includes ML models.
  if [[ "${EXTRACTOR_SERVICE:-false}" != "true" ]]; then
    echo "[INFO] Extractor service is disabled (EXTRACTOR_SERVICE=false). Skipping build."
    exit 0
  fi
  ensure_data_dir "extractor" 2>/dev/null || true
  set_docker_compose
  build_log="${HOME_DIR}/monadic/log/docker_build.log"
  if [[ "${MONADIC_DEV:-false}" == "true" ]]; then
    # Development: build locally from source via the explicit build overlay.
    echo "[INFO] Building extractor container..."
    eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -f \"${ROOT_DIR}/services/extractor/compose.build.yml\" -p monadic-chat --profile extractor build extractor_service" 2>&1 | tee -a "${build_log}"
  else
    # Production: pull the prebuilt user-independent image from ghcr.io.
    echo "[HTML]: <p><i class='fa-solid fa-cloud-arrow-down' style='color:#61b0ff;'></i> Downloading the prebuilt Knowledge Base Quality Pack image (~1.3 GB on first download) . . .</p>"
    eval "\"${DOCKER}\" compose ${REPORTING} ${COMPOSE_FILES} -p monadic-chat --profile extractor pull extractor_service" 2>&1 | tee -a "${build_log}"
  fi
  if ${DOCKER} images | grep -q "ghcr.io/yohasebe/monadic-extractor"; then
    echo "[INFO] Extractor container build succeeded."
    # Snapshot marker: existence distinguishes "not yet built" from
    # "built". OCR languages/backend are runtime settings now, so no
    # language line is recorded.
    prev_options_file="${HOME_DIR}/monadic/log/extractor_build_options.txt"
    {
      echo "EXTRACTOR_SERVICE=${EXTRACTOR_SERVICE:-false}"
    } > "$prev_options_file"
    echo "[INFO] Saved build options to ${prev_options_file}"
  else
    echo "[ERROR] Extractor container build failed. See ${build_log}."
    exit 1
  fi
  ;;
*)
  echo "Usage: $0 {build|start|stop|restart|update|remove|check}" >&2
  # exit 1
  ;;
esac

exit 0
