#!/bin/bash

# Set instance name and directories
INSTANCE_NAME="ss-rust-server-tcp"
DOCKER_COMPOSE_DIR="/root/shadowsocks-rust_d"
CONFIG_DIR="/etc/shadowsocks-rust"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_DIR}/docker-compose.yml"

# Ensure necessary directories exist
mkdir -p ${CONFIG_DIR}
mkdir -p ${DOCKER_COMPOSE_DIR}

# Stop and remove existing instance if running
if docker ps -a --format '{{.Names}}' | grep -q "^${INSTANCE_NAME}$"; then
    echo "Found existing instance ${INSTANCE_NAME}, stopping and removing..."
    docker-compose -p ${INSTANCE_NAME} -f ${DOCKER_COMPOSE_FILE} down
    sleep 2
fi

# Create Shadowsocks configuration file with TCP-only mode
echo "Creating Shadowsocks configuration with TCP-only mode..."
cat > ${CONFIG_FILE} << 'EOL'
{
    "server":"0.0.0.0",
    "server_port":65504,
    "password":"passwd",
    "timeout":300,
    "method":"aes-128-gcm",
    "nameserver":"1.1.1.1,8.8.8.8",
    "mode":"tcp_only",
    "no_delay":true,
    "fast_open":true
}
EOL

# Create docker-compose configuration file for shadowsocks-rust
echo "Creating Docker Compose configuration..."
cat > ${DOCKER_COMPOSE_FILE} << EOL
version: '3'
services:
  ssserver-rust:
    container_name: ${INSTANCE_NAME}
    image: ghcr.io/shadowsocks/ssserver-rust:latest
    restart: always
    ports:
      - "65504:65504/tcp"
    volumes:
      - ${CONFIG_FILE}:${CONFIG_FILE}:ro
EOL

# Pull the latest image
echo "Pulling latest shadowsocks-rust image..."
docker pull ghcr.io/shadowsocks/ssserver-rust:latest

# Start the new instance
echo "Starting new instance ${INSTANCE_NAME}..."
docker-compose -p ${INSTANCE_NAME} -f ${DOCKER_COMPOSE_FILE} up -d

# Check if the container started successfully
sleep 2
if docker ps --format '{{.Names}}' | grep -q "^${INSTANCE_NAME}$"; then
    echo -e "\nContainer ${INSTANCE_NAME} started successfully!"
else
    echo -e "\nError: Failed to start ${INSTANCE_NAME}."
    exit 1
fi

# Display container status, logs, and port
echo -e "\nContainer Status:"
docker ps | grep ${INSTANCE_NAME}

echo -e "\nContainer Logs:"
docker logs ${INSTANCE_NAME}

echo -e "\nPort Status:"
netstat -tuln | grep 65504 || echo "Port 65504 not open - check configuration."

# Display instance management commands
echo -e "\nInstance name: ${INSTANCE_NAME}"
echo "Manage the instance with:"
echo "docker-compose -p ${INSTANCE_NAME} -f ${DOCKER_COMPOSE_FILE} [command]"

