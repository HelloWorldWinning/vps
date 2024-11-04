#!/bin/bash

# Define path
PATH_DIR="/root/7788_web_download_docker_d"

# Create directory if it doesn't exist
mkdir -p "$PATH_DIR"

# Create docker-compose.yml
cat > "$PATH_DIR/docker-compose.yml" << 'EOL'
version: '3.8'
services:
  host_7788_download:
    image: oklove/webpage_port_7788_download
    container_name: host_7788_download
    ports:
      - "7788:7788"
    volumes:
      - /:/Host
    restart: unless-stopped
    security_opt:
      - apparmor:unconfined
    cap_add:
      - SYS_ADMIN
EOL

# Change to the directory
cd "$PATH_DIR"

# Stop existing containers
echo "Stopping existing containers..."
docker-compose down

# Pull latest images
echo "Pulling latest images..."
docker-compose pull

# Start containers in detached mode
echo "Starting containers..."
docker-compose up -d
sleep 2
# Check container status
echo -e "\nChecking container status:"
docker ps | grep host_7788_download

# Check logs for any errors
echo -e "\nChecking container logs:"
docker-compose logs --tail=20 host_7788_download
