#!/bin/bash

# Define the path to the root directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. >/dev/null 2>&1 && pwd)"

# Define the paths to the support scripts
MAC_SCRIPT="${ROOT_DIR}/docker/mac-start-docker.sh"
WINDOWS_SCRIPT="${ROOT_DIR}/docker/windows-start-docker.sh"
LINUX_SCRIPT="${ROOT_DIR}/docker/linux-start-docker.sh"

# Define a function to start Docker Compose
function start_docker_compose {
    # Determine the operating system
    case "$(uname -s)" in
        Darwin)
            # macOS
            sh "$MAC_SCRIPT"
            ;;
        Linux)
            # Linux
            sh "$LINUX_SCRIPT"
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

    # Build and start the Docker Compose services
    docker-compose -f "$ROOT_DIR/docker-compose.yml" build
    docker-compose -f "$ROOT_DIR/docker-compose.yml" up -d

    # Wait for the services to be up and running
    timeout=5 # 1 minute timeout

    while [[ $(docker-compose -f "$ROOT_DIR/docker-compose.yml" ps -q | xargs docker inspect --format '{{.State.Running}}') == "true" ]]; do
        sleep 1
        timeout=$((timeout-1))
        if [[ $timeout -eq 0 ]]; then
          break
        fi
    done

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
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
