#!/bin/bash

# Exit on error
set -e

# Define variables
FULL_PATH="/root/wg_docker_d"
DOCKER_COMPOSE_CONTENT=$(cat << 'EOF'
version: '3.8'
services:
  wireguard:
    image: lscr.io/linuxserver/wireguard:latest
    container_name: docker_wg
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - PEERS=2
      - SERVERPORT=65503
      - ALLOWEDIPS=0.0.0.0/0
      - INTERNAL_SUBNET=10.33.33.0
      - LOG_CONFS=true
    ports:
      - "65506:65503/udp"
    volumes:
      - ./wg_docker_config:/config/
      - /lib/modules:/lib/modules
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
EOF
)

# Create required directories
echo "Creating directories..."
mkdir -p "$FULL_PATH"
mkdir -p "$FULL_PATH/wg_docker_config"
mkdir -p "$FULL_PATH/wg_docker_config/wg_confs"

# Change to working directory
cd "$FULL_PATH"

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
echo "$DOCKER_COMPOSE_CONTENT" > docker-compose.yml


# Start Docker Compose
echo "Starting Docker Compose..."
docker compose up -d

# Wait for container to initialize
echo "Waiting for container to initialize..."
sleep 4

docker compose down


# Download WireGuard configuration
echo "Downloading WireGuard configuration..."
curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg_d/wg_docker_config.conf > "$FULL_PATH/wg_docker_config/wg_confs/wg0.conf"

docker compose up -d


# Check container status
echo "Container Status:"
docker ps --filter "name=docker_wg" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Show container logs
echo -e "\nContainer Logs:"

sleep 4

docker logs docker_wg --tail 40

echo -e "\nSetup completed! Check the logs above for any issues."

