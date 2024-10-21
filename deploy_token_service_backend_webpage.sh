#!/bin/bash

# Define the deployment directory
DEPLOY_DIR="/data/token_service_backend_webpage_d"

# Remove the existing directory if it exists
if [ -d "$DEPLOY_DIR" ]; then
    echo "Removing existing directory $DEPLOY_DIR"
    rm -rf "$DEPLOY_DIR"
fi

# Create a new deployment directory
echo "Creating new directory $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# Navigate to the deployment directory
cd "$DEPLOY_DIR"

# Write the updated docker-compose.yml into the directory
echo "Writing updated docker-compose.yml"
cat <<"EOF" > docker-compose.yml
version: '3.8'

services:
  web:
    image: oklove/token_service_backend_webpage:latest
    container_name:  token_service_backend_webpage_web_instance
    network_mode: "host"
    command: python token_counter.py
    environment:
      BACKEND_HOST: "127.0.0.1"

  backend:
    image: oklove/token_service_backend_webpage:latest
    container_name:  token_service_backend_webpage_backend_instance
    network_mode: "host"
    command: python tokenizer_service.py
EOF

# Pull the latest images (if needed)
echo "Pulling Docker images"
docker-compose pull

# Start the services in detached mode
echo "Starting services"
docker-compose up -d

# Wait for 4 seconds to allow services to initialize
echo "Waiting for services to initialize"
sleep 4

# Check if the services are running
echo "Checking running services"
RUNNING_SERVICES=$(docker-compose ps --services --filter "status=running")

if [ -n "$RUNNING_SERVICES" ]; then
    echo "Services are running:"
    docker-compose ps
else
    echo "No services are running. Check logs for details."
    docker-compose logs
fi

