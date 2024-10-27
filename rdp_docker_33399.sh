#!/bin/bash

# Define variables
DOCKER_DIR="/data/docker-remote-desktop_d"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
HOST_DOWNLOAD_DIR="$DOCKER_DIR/download"

# Create necessary directories
mkdir -p "$DOCKER_DIR"
mkdir -p "$HOST_DOWNLOAD_DIR"
chmod 777 "$HOST_DOWNLOAD_DIR"  # Ensure proper permissions

# Create docker-compose.yml
cat > $COMPOSE_FILE << EOL
version: '3.8'
services:
  remote-desktop:
    image: scottyhardy/docker-remote-desktop:latest
    container_name: remote-desktop
    hostname: ${HOSTNAME}
    ports:
      - "33399:3389"
    volumes:
      - /data/docker-remote-desktop_d/download:/downloads  # Changed mount point
    environment:
      - DOWNLOAD_DIR=/downloads  # Tell the container about the new downloads location
    restart: always
EOL

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker is not running or you don't have proper permissions"
        exit 1
    fi
}

# Function to check if Docker Compose is installed
check_docker_compose() {
    if ! command -v docker-compose >/dev/null 2>&1; then
        echo "Error: Docker Compose is not installed"
        exit 1
    fi
}

# Main execution
echo "Starting Docker Remote Desktop setup..."

# Run checks
check_docker
check_docker_compose

# Change to the Docker directory
cd "$DOCKER_DIR"

# Stop and remove existing container if it exists
docker-compose down

# Pull the latest image
echo "Pulling the latest image..."
docker-compose pull

# Start the container
echo "Starting the container..."
docker-compose up -d

# Check if container is running
if docker-compose ps | grep -q "remote-desktop"; then
    echo "Container is running successfully"
    echo "You can connect to the remote desktop using:"
    echo "Host: $(hostname -I | awk '{print $1}')"
    echo "Port: 33399"
    echo "Downloads will be available in /downloads inside the container"
else
    echo "Error: Container failed to start"
    docker-compose logs
    exit 1
fi
