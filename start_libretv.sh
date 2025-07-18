#!/bin/bash

# LibreTV Docker Compose Startup Script
# This script starts LibreTV with light theme using docker-compose

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_DIR="/root/libretv"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

echo -e "${GREEN}Starting LibreTV with Docker Compose...${NC}"

# Check if docker-compose is installed
if ! command -v docker-compose &>/dev/null; then
	echo -e "${RED}Error: docker-compose is not installed!${NC}"
	echo "Please install docker-compose first."
	exit 1
fi

# Check if Docker is running
if ! docker info &>/dev/null; then
	echo -e "${RED}Error: Docker is not running!${NC}"
	echo "Please start Docker first."
	exit 1
fi

# Create directory if it doesn't exist
if [ ! -d "$COMPOSE_DIR" ]; then
	echo -e "${YELLOW}Creating directory: $COMPOSE_DIR${NC}"
	mkdir -p "$COMPOSE_DIR"
fi

# Navigate to the compose directory
cd "$COMPOSE_DIR"

# Create docker-compose.yml if it doesn't exist
if [ ! -f "$COMPOSE_FILE" ]; then
	echo -e "${YELLOW}Creating docker-compose.yml file...${NC}"
	cat >"$COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  libretv:
    image: bestzwei/libretv:latest
    container_name: libretv
    restart: unless-stopped
    ports:
      - "8899:8080"
    environment:
      - PASSWORD=a
      - ADMINPASSWORD=a
      - THEME=light
    volumes:
      - ./data:/app/data
      - ./config:/app/config
    networks:
      - libretv_network

networks:
  libretv_network:
    driver: bridge

volumes:
  libretv_data:
  libretv_config:
EOF
	echo -e "${GREEN}✓ docker-compose.yml created successfully${NC}"
fi

# Create data and config directories
echo -e "${YELLOW}Creating data and config directories...${NC}"
mkdir -p data config

# Stop existing containers if running
echo -e "${YELLOW}Stopping existing LibreTV containers...${NC}"
docker-compose down 2>/dev/null || true

# Pull latest image
echo -e "${YELLOW}Pulling latest LibreTV image...${NC}"
docker-compose pull

# Start the services
echo -e "${YELLOW}Starting LibreTV services...${NC}"
docker-compose up -d

# Check if container is running
sleep 5
if docker ps | grep -q libretv; then
	echo -e "${GREEN}✓ LibreTV started successfully!${NC}"
	echo -e "${GREEN}✓ Container is running with light theme${NC}"
	echo -e "${GREEN}✓ Access LibreTV at: http://localhost:8899${NC}"
	echo -e "${GREEN}✓ Password: a${NC}"
	echo -e "${GREEN}✓ Admin Password: a${NC}"
	echo ""
	echo -e "${YELLOW}To view logs: docker-compose logs -f${NC}"
	echo -e "${YELLOW}To stop: docker-compose down${NC}"
else
	echo -e "${RED}✗ Failed to start LibreTV${NC}"
	echo "Check logs with: docker-compose logs"
	exit 1
fi
