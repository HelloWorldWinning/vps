#!/bin/bash

# flatnotes Docker Compose Setup Script
# ======================================

set -e

# Configuration
COMPOSE_DIR="/root/flatnotes_d"
DATA_DIR="/data/flatnotes_d"
PORT="3100"
USERNAME="admin"
#PASSWORD="flatnotes2024!"
PASSWORD="adminpasswd"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   flatnotes Docker Compose Setup${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Create directories
echo -e "${GREEN}[1/5]${NC} Creating directories..."
mkdir -p "$COMPOSE_DIR"
mkdir -p "$DATA_DIR"
echo -e "      ✓ Created $COMPOSE_DIR"
echo -e "      ✓ Created $DATA_DIR\n"

# Generate secret key
echo -e "${GREEN}[2/5]${NC} Generating secret key..."
SECRET_KEY=$(openssl rand -hex 32)
echo -e "      ✓ Secret key generated\n"

# Create docker-compose.yml
echo -e "${GREEN}[3/5]${NC} Creating docker-compose.yml..."
cat >"$COMPOSE_DIR/docker-compose.yml" <<EOF
version: "3"

services:
  flatnotes:
    container_name: flatnotes
    image: dullage/flatnotes:latest
    environment:
      PUID: 1000
      PGID: 1000
      FLATNOTES_AUTH_TYPE: "password"
      FLATNOTES_USERNAME: "$USERNAME"
      FLATNOTES_PASSWORD: "$PASSWORD"
      FLATNOTES_SECRET_KEY: "$SECRET_KEY"
    volumes:
      - "$DATA_DIR:/data"
    ports:
      - "$PORT:8080"
    restart: unless-stopped
EOF
echo -e "      ✓ Docker Compose file created at $COMPOSE_DIR/docker-compose.yml\n"

# Start the container
echo -e "${GREEN}[4/5]${NC} Starting flatnotes container..."
cd "$COMPOSE_DIR"
docker-compose up -d
echo -e "      ✓ Container started\n"

# Wait for container to be ready
echo -e "${GREEN}[5/5]${NC} Waiting for flatnotes to initialize..."
sleep 3

# Display instance information
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   flatnotes Instance Information${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${YELLOW}Access URL:${NC}"
echo -e "  • http://localhost:$PORT"
echo -e "  • http://$SERVER_IP:$PORT\n"

echo -e "${YELLOW}Login Credentials:${NC}"
echo -e "  Username: ${GREEN}$USERNAME${NC}"
echo -e "  Password: ${GREEN}$PASSWORD${NC}\n"

echo -e "${YELLOW}Directories:${NC}"
echo -e "  Docker Compose: $COMPOSE_DIR"
echo -e "  Notes Data:     $DATA_DIR\n"

echo -e "${YELLOW}Container Status:${NC}"
docker-compose ps

echo -e "\n${YELLOW}Useful Commands:${NC}"
echo -e "  View logs:      cd $COMPOSE_DIR && docker-compose logs -f"
echo -e "  Stop:           cd $COMPOSE_DIR && docker-compose stop"
echo -e "  Start:          cd $COMPOSE_DIR && docker-compose start"
echo -e "  Restart:        cd $COMPOSE_DIR && docker-compose restart"
echo -e "  Remove:         cd $COMPOSE_DIR && docker-compose down\n"

echo -e "${GREEN}✓ flatnotes is now running!${NC}\n"
