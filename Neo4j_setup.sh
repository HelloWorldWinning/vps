#!/bin/bash

# Neo4j Docker Setup Script
# This script sets up Neo4j with Docker Compose

set -e # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Main setup
print_info "Starting Neo4j setup..."

# Create directory structure
print_info "Creating directory structure at /data/Neo4j_D/"
mkdir -p /data/Neo4j_D/
mkdir -p /data/Neo4j_D/data
mkdir -p /data/Neo4j_D/data/logs
mkdir -p /data/Neo4j_D/data/plugins

# Create docker-compose.yml file
print_info "Creating docker-compose.yml file..."
cat >/data/Neo4j_D/docker-compose.yml <<'EOF'
services:
  neo4j:
    image: neo4j:5-enterprise
    container_name: neo4j
    restart: unless-stopped
    # Expose the Neo4j Browser (HTTP) and Bolt ports
    ports:
      - "7474:7474"   # HTTP
      - "7687:7687"   # Bolt
    # Change the password below before first run.
    # Example format: NEO4J_AUTH: neo4j/yourStrongPassword
    environment:
      NEO4J_AUTH: neo4j/admin_passwd
      NEO4J_ACCEPT_LICENSE_AGREEMENT: "yes"
    # Keep all data under ./data; logs specifically under ./data/logs
    volumes:
      - ./data:/data
      - ./data/logs:/logs
      - ./data/plugins:/plugins
#     - ./data/import:/var/lib/neo4j/import
EOF

print_info "docker-compose.yml created successfully"

# Navigate to Neo4j directory
cd /data/Neo4j_D/

# Stop existing containers if running
print_info "Stopping existing Neo4j containers (if any)..."
docker compose down 2>/dev/null || print_warning "No existing containers to stop"

# Clean up unused Docker images
print_info "Cleaning up unused Docker images..."
docker image prune -f || print_warning "No unused images to remove"

# Start Neo4j container
print_info "Starting Neo4j container..."
if docker compose up -d; then
	print_info "Neo4j container started successfully"
else
	print_error "Failed to start Neo4j container"
	exit 1
fi

# Wait for container to initialize
print_info "Waiting for Neo4j to initialize..."
sleep 3

# Check container status
print_info "Checking container status..."
echo ""
echo "=== Container Status ==="
docker ps --filter "name=neo4j" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check if container is running
if docker ps | grep -q neo4j; then

	PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipecho.net/plain)
	echo ""
	print_info "✓ Neo4j is running successfully!"
	echo ""
	echo "=== Connection Information ==="
	#   echo "Browser URL: http://localhost:7474"
	#   echo "Bolt URL: bolt://localhost:7687"
	echo "Browser URL: http://${PUBLIC_IP}:7474"
	echo "Bolt URL: bolt://${PUBLIC_IP}:7687"
	echo "Default credentials: neo4j/admin_passwd"
	echo ""
	echo "=== Container Logs (last 10 lines) ==="
	docker logs --tail 10 neo4j 2>&1 | sed 's/^/  /'
	echo ""
	print_info "Setup completed successfully!"
else
	echo ""
	print_error "Neo4j container is not running!"
	echo ""
	echo "=== Error Logs ==="
	docker logs neo4j 2>&1 | tail -20 | sed 's/^/  /'
	echo ""
	print_error "Please check the logs above for error details"
	exit 1
fi

# Additional useful information
echo ""
echo "=== Useful Commands ==="
echo "View logs:        docker logs -f neo4j"
echo "Stop Neo4j:       cd /data/Neo4j_D && docker compose down"
echo "Restart Neo4j:    cd /data/Neo4j_D && docker compose restart"
echo "Check status:     docker ps | grep neo4j"
echo ""
