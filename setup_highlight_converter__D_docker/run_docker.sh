#!/bin/bash

# Set the target directory
TARGET_DIR="/data/highlight_converter_187"

# Create directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Change to the directory
cd "$TARGET_DIR" || {
    echo "Failed to change to directory $TARGET_DIR"
    exit 1
}

# Create docker-compose.yml file
cat << "EOF" > docker-compose.yml
version: '3.8'
services:
  highlight-conversion-service:
    image: oklove/highlight-conversion-service:latest
    ports:
      - "187:187"
    volumes:
      - ./downloads:/app/downloads
    working_dir: /app
    restart: unless-stopped
EOF

# Start the Docker container
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose up -d
else
    echo "Neither docker-compose nor docker compose is available. Please install Docker and docker-compose."
    exit 1
fi

echo "Highlight converter setup complete and container started in $TARGET_DIR"
