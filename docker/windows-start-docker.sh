#!/bin/bash

# Start Docker Desktop for Windows
echo "Starting Docker Desktop for Windows..."
powershell.exe -Command "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -Verb RunAs"

# Wait for Docker Desktop to start
echo "Waiting for Docker Desktop to start..."
timeout=30 # 30 seconds timeout
while ! docker system info > /dev/null 2>&1; do
    sleep 1
    timeout=$((timeout-1))
    if [[ $timeout -eq 0 ]]; then
        echo "Timed out waiting for Docker Desktop to start"
        exit 1
    fi
done

# Set the Docker Compose file path
export COMPOSE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. >/dev/null 2>&1 && pwd)/docker-compose.yml"

# Start Docker Compose
echo "Starting Docker Compose..."
docker-compose up -d

exit 0
