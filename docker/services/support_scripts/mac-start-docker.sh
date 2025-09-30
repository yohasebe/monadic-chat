#!/bin/bash

# Docker socket path
DOCKER_SOCK="${HOME}/.docker/run/docker.sock"

# Function to check if Docker is actually running
check_docker_running() {
    if [ ! -S "${DOCKER_SOCK}" ]; then
        return 1
    fi

    # Use docker version with timeout to check if daemon is responsive
    timeout 3 docker version --format '{{.Server.Version}}' > /dev/null 2>&1
    return $?
}

# Check if Docker is already running
if check_docker_running; then
    exit 0
fi

# Start Docker Desktop
echo "Starting Docker Desktop..." >&2
open -a Docker

timeout=60
elapsed=0
while ! check_docker_running; do
    sleep 1
    elapsed=$((elapsed+1))
    timeout=$((timeout-1))

    if [ $((elapsed % 10)) -eq 0 ]; then
        echo "Waiting for Docker Desktop to start... (${elapsed}s)" >&2
    fi

    if [ $timeout -eq 0 ]; then
        echo "ERROR: Timed out waiting for Docker Desktop after 60 seconds" >&2
        exit 1
    fi
done

echo "Docker Desktop is ready (took ${elapsed}s)" >&2
exit 0
