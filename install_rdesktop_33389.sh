#!/bin/bash

# Define variables
FOLDER_PATH="/data/rdp_33389_D"
COMPOSE_FILE="$FOLDER_PATH/docker-compose.yml"

# Create directory if it doesn't exist
mkdir -p "$FOLDER_PATH"

# Navigate to the folder
cd "$FOLDER_PATH"

# Create docker-compose.yml file
cat > "$COMPOSE_FILE" << 'EOF'
---
services:
  rdesktop:
    image: lscr.io/linuxserver/rdesktop:latest
#   container_name: rdesktop
    security_opt:
      - seccomp:unconfined #optional
    environment:
      - PUID=1000
      - PGID=1000
##    - TZ=Etc/UTC
      - TZ=Asia/Shanghai
      - DOCKER_MODS=linuxserver/mods:universal-package-install
#     - INSTALL_PACKAGES=font-noto-cjk
      - INSTALL_PACKAGES=font-wqy-zenhei
      - LC_ALL=zh_CN.UTF-8
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock #optional
      - ./data:/config #optional
    ports:
      - 33389:3389
    devices:
      - /dev/dri:/dev/dri #optional
    shm_size: "1gb" #optional
    restart: unless-stopped
EOF

# Create data directory
mkdir -p "$FOLDER_PATH/data"

# Stop any existing container
echo "Stopping any existing rdesktop container..."
cd "$FOLDER_PATH" && docker compose stop

# Pull the latest image
echo "Pulling the latest rdesktop image..."
cd "$FOLDER_PATH" && docker compose pull

# Start the container
echo "Starting the rdesktop container..."
cd "$FOLDER_PATH" && docker compose up -d

# Wait for container to initialize
echo "Waiting for container to initialize..."
sleep 4

# Check container status
echo "Checking container status:"
cd "$FOLDER_PATH" && docker compose ps

# Get IP address and port information
echo "Container accessible at:"
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo "IP: $IP_ADDRESS"
echo "Port: 33389"
echo "Connect using RDP client to $IP_ADDRESS:33389"

echo "Installation complete!"
