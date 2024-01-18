#!/bin/bash

# Start Docker Desktop
open -a Docker

sleep 5

# Wait for Docker to become available
until /usr/local/bin/docker info > /dev/null 2>&1; do
    echo "Waiting for Docker Desktop to start..."
    sleep 5
done
