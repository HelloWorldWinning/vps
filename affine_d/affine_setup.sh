#!/bin/bash

set -e

echo "=== AFFiNE Setup Script ==="
echo ""

# Create directory
echo "Creating directory /data/affine_d..."
mkdir -p /data/affine_d

# Download docker-compose.yml
echo "Downloading docker-compose.yml..."
curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/affine_d/docker-compose.yml -o /data/affine_d/docker-compose.yml

# Change to the directory
cd /data/affine_d

# Stop any existing containers
echo "Stopping existing containers..."
docker compose down 2>/dev/null || true

# Start containers
echo "Starting AFFiNE containers..."
docker compose up -d

# Wait for services to initialize
echo "Waiting for services to start..."
sleep 3

# Display running info
echo ""
echo "=== AFFiNE Status ==="
echo ""
echo "Container Status:"
docker compose ps

echo ""
echo "=== Running Services ==="
docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Logs (last 20 lines) ==="
docker compose logs --tail=20

echo ""
echo "=== Setup Complete ==="
echo "AFFiNE should now be running!"
echo "Access the application at: http://localhost:3010 (or your server IP)"
echo ""
echo "Useful commands:"
echo "  View logs: cd /data/affine_d && docker compose logs -f"
echo "  Restart:   cd /data/affine_d && docker compose restart"
echo "  Stop:      cd /data/affine_d && docker compose down"
echo "  Status:    cd /data/affine_d && docker compose ps"
