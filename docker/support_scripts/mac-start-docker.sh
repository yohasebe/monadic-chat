#!/bin/bash

# Start Docker Desktop
open -a Docker

# Wait for Docker to become available
until /usr/local/bin/docker info > /dev/null 2>&1; do
    echo "Waiting for Docker Desktop to start..."
    sleep 5
done

echo "Docker Desktop has been loaded"
