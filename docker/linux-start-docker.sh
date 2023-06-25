#!/bin/bash

# Start Docker
systemctl start docker

# Wait for Docker to become available
until docker info > /dev/null 2>&1; do
    echo "Waiting for Docker to start..."
    sleep 5
done

echo "Docker is now available."
