#!/bin/bash

# Define variables
DOCKER_DIR="/data/docker-remote-desktop_d"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
HOST_DOWNLOAD_DIR="$DOCKER_DIR/download"
CURRENT_HOSTNAME=$(hostname)

# Create necessary directories
mkdir -p "$DOCKER_DIR"
mkdir -p "$HOST_DOWNLOAD_DIR"

# Create docker-compose.yml
cat > "$COMPOSE_FILE" << EOL
version: '3.8'
services:
  remote-desktop:
    image: scottyhardy/docker-remote-desktop:latest
    container_name: remote-desktop
    hostname: $CURRENT_HOSTNAME
    ports:
      - "33399:3389"
    volumes:
      - /data/docker-remote-desktop_d/download:/home/ubuntu/Downloads
    restart: always
EOL

# Set proper permissions
chmod 755 "$DOCKER_DIR"
chmod 755 "$HOST_DOWNLOAD_DIR"
chmod 644 "$COMPOSE_FILE"

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
echo "Using hostname: $CURRENT_HOSTNAME"

# Run checks
check_docker
check_docker_compose

# Change to the Docker directory
cd "$DOCKER_DIR"

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
else
    echo "Error: Container failed to start"
    docker-compose logs
    exit 1
fi
