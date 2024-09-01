#!/bin/bash

# Start Docker
systemctl --user start docker-desktop

# Wait for Docker Desktop to start
timeout=60
while ! docker system info > /dev/null 2>&1; do
    sleep 1
    timeout=$((timeout-1))
    if [ $timeout -eq 0 ]; then
        echo "[HTML]: <p>Timed out waiting for Docker Desktop to start.</p>"
        exit 1
    fi
done
