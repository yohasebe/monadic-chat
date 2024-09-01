#!/bin/bash

# Start Docker Desktop
open -a Docker

timeout=60
while ! /usr/local/bin/docker info > /dev/null 2>&1; do
    sleep 1
    timeout=$((timeout-1))
    if [ $timeout -eq 0 ]; then
        echo "[HTML]: <p>Timed out waiting for Docker Desktop to start.</p>"
        exit 1
    fi
done
