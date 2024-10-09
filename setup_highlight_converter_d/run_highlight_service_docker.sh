#!/bin/bash

# Create the directory /data/highlight_converter_d if it doesn't exist
DIRECTORY="/data/highlight_converter_d"
if [ ! -d "$DIRECTORY" ]; then
  echo "Creating directory $DIRECTORY"
  mkdir -p $DIRECTORY
else
  echo "Directory $DIRECTORY already exists."
fi

# Create the docker-compose.yml file in /data/highlight_converter_d
COMPOSE_FILE="$DIRECTORY/docker-compose.yml"

echo "Creating docker-compose.yml in $DIRECTORY"
cat > "$COMPOSE_FILE" << "EOF"
version: '3'
services:
  highlight_conversion_service:
    image: oklove/highlight_conversion_service
    container_name: calib
    ports:
      - "187:187"
    volumes:
      - /data/highlight_converter_d:/app/data
    restart: unless-stopped
EOF

echo "docker-compose.yml file created successfully."

# Navigate to the directory
cd $DIRECTORY

# Run Docker Compose
echo "Starting the Docker container with Docker Compose..."
docker-compose up -d

# Check if the container is running
CONTAINER_NAME="highlight_conversion_service_container"
RUNNING=$(docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" -q)

sleep 3;
if [ -n "$RUNNING" ]; then
  echo "Container '$CONTAINER_NAME' is running successfully."
else
  echo "Failed to start the container '$CONTAINER_NAME'. Check logs for details."
fi

