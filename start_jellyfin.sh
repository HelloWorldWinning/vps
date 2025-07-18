#!/bin/bash

# Jellyfin Docker Compose Startup Script
# This script creates docker-compose.yml and starts Jellyfin
# Usage: bash start-jellyfin.sh

# Configuration
COMPOSE_DIR="/root/Jellyfin"
DATA_DIR="/data/Jellyfin"

# Create necessary directories
echo "Creating Jellyfin directories..."
mkdir -p "$COMPOSE_DIR"
mkdir -p "$DATA_DIR/config"
mkdir -p "$DATA_DIR/cache"
mkdir -p "$DATA_DIR/media"

# Set proper permissions (adjust UID:GID as needed)
echo "Setting permissions..."
chown -R 1000:1000 "$DATA_DIR"

# Create docker-compose.yml file
echo "Creating docker-compose.yml..."
cat >"$COMPOSE_DIR/docker-compose.yml" <<'EOF'
services:
  jellyfin:
    image: jellyfin/jellyfin
    container_name: jellyfin
    user: 1000:1000
    ports:
      - "8096:8096"
      - "8920:8920"
      - "7359:7359/udp"
      - "1900:1900/udp"
    volumes:
      - /data/Jellyfin/config:/config
      - /data/Jellyfin/cache:/cache
      - type: bind
        source: /data/Jellyfin/media
        target: /media
        read_only: false
    restart: 'unless-stopped'
    # Optional - alternative address used for autodiscovery
    environment:
      - JELLYFIN_PublishedServerUrl=http://localhost:8096
    # Optional - may be necessary for docker healthcheck to pass if running in host network mode
    extra_hosts:
      - 'host.docker.internal:host-gateway'
EOF

# Navigate to docker-compose directory
cd "$COMPOSE_DIR" || {
	echo "Error: Cannot access $COMPOSE_DIR"
	exit 1
}

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
	echo "Error: Docker is not running. Please start Docker first."
	exit 1
fi

# Stop existing container if running
echo "Stopping existing Jellyfin container (if any)..."
docker compose down 2>/dev/null || true

# Start Jellyfin
echo "Starting Jellyfin..."
docker compose up -d

# Check if container started successfully
if [ $? -eq 0 ]; then
	echo ""
	echo "======================================"
	echo "Jellyfin started successfully!"
	echo "======================================"
	echo "Access Jellyfin at: http://localhost:8096"
	echo ""
	echo "Useful commands:"
	echo "  View logs: docker compose logs -f jellyfin"
	echo "  Stop: docker compose down"
	echo "  Restart: docker compose restart jellyfin"
	echo ""
	echo "Data directories:"
	echo "  Config: $DATA_DIR/config"
	echo "  Cache: $DATA_DIR/cache"
	echo "  Media: $DATA_DIR/media"
	echo "======================================"
else
	echo "Error: Failed to start Jellyfin"
	exit 1
fi

# Wait a moment for container to fully start
echo "Waiting for container to start..."
sleep 5

# Check Docker container status
echo ""
echo "======================================"
echo "DOCKER STATUS CHECK"
echo "======================================"

# Check if container is running
CONTAINER_STATUS=$(docker ps --filter "name=jellyfin" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
if [ -n "$CONTAINER_STATUS" ]; then
	echo "Container Status:"
	echo "$CONTAINER_STATUS"
	echo ""

	# Check container health
	HEALTH_STATUS=$(docker inspect jellyfin --format='{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
	if [ "$HEALTH_STATUS" != "no-healthcheck" ]; then
		echo "Health Status: $HEALTH_STATUS"
	fi

	# Check if Jellyfin is responding
	echo "Testing Jellyfin connectivity..."
	if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8096" | grep -q "200\|302"; then
		echo "✓ Jellyfin is responding on port 8096"
	else
		echo "⚠ Jellyfin may still be starting up (port 8096 not ready yet)"
	fi

else
	echo "⚠ Warning: Jellyfin container not found in running containers"
	echo ""
	echo "All containers:"
	docker ps -a --filter "name=jellyfin" --format "table {{.Names}}\t{{.Status}}"
	echo ""
	echo "Check logs with: docker compose logs jellyfin"
fi

echo "======================================"
