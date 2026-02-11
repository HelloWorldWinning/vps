#!/bin/bash

set -e # Exit on error

echo "======================================"
echo "Docmost Installation Script"
echo "======================================"
echo ""

# Get VPS IP automatically
echo "Detecting VPS IP address..."
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipecho.net/plain)

if [ -z "$VPS_IP" ]; then
	echo "Error: Could not detect VPS IP automatically"
	echo "Please enter your VPS IP manually:"
	read VPS_IP
fi

echo "VPS IP detected: $VPS_IP"
echo ""

# Generate secrets
echo "Generating secure secrets..."
APP_SECRET=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 16)

echo "APP_SECRET: $APP_SECRET"
echo "DB_PASSWORD: $DB_PASSWORD"
echo ""

# Create installation directory
INSTALL_DIR="/data/docmost"
echo "Creating installation directory: $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create data directories for bind mounts
echo "Creating data directories..."
sudo mkdir -p "$INSTALL_DIR/data/docmost"
sudo mkdir -p "$INSTALL_DIR/data/db_data"
sudo mkdir -p "$INSTALL_DIR/data/redis_data"

# Set proper permissions
echo "Setting permissions..."
sudo chown -R 1000:1000 "$INSTALL_DIR/data/docmost"
sudo chown -R 999:999 "$INSTALL_DIR/data/db_data" # PostgreSQL 18+ uses /var/lib/postgresql as mount
sudo chown -R 999:999 "$INSTALL_DIR/data/redis_data"

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
sudo tee "$INSTALL_DIR/docker-compose.yml" >/dev/null <<EOF
services:
  docmost:
    image: docmost/docmost:latest
    depends_on:
      - db
      - redis
    environment:
      APP_URL: 'http://${VPS_IP}:8300'
      APP_SECRET: '${APP_SECRET}'
      DATABASE_URL: 'postgresql://docmost:${DB_PASSWORD}@db:5432/docmost'
      REDIS_URL: 'redis://redis:6379'
    ports:
      - "8300:3000"
    restart: unless-stopped
    volumes:
      - ./data/docmost:/app/data/storage
    deploy:
      resources:
        limits:
          cpus: '1.0'      # Max 1 CPU core
          memory: 1G       # Max 1GB RAM

  db:
    image: postgres:18
    environment:
      POSTGRES_DB: docmost
      POSTGRES_USER: docmost
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    restart: unless-stopped
    volumes:
      - ./data/db_data:/var/lib/postgresql
    deploy:
      resources:
        limits:
          cpus: '2.0'      # Max 1 CPU core
          memory: 2G       # Max 1GB RAM

  redis:
    image: redis:8
    command: ["redis-server", "--appendonly", "yes", "--maxmemory-policy", "noeviction"]
    restart: unless-stopped
    volumes:
      - ./data/redis_data:/data
    deploy:
      resources:
        limits:
          cpus: '1.0'      # Max 1 CPU core
          memory: 1G       # Max 1GB RAM
EOF

echo ""
echo "======================================"
echo "Installation Summary"
echo "======================================"
echo "Installation directory: $INSTALL_DIR"
echo "Access URL: http://${VPS_IP}:8300"
echo ""
echo "Data locations (bind mounts):"
echo "  - Docmost data: $INSTALL_DIR/data/docmost"
echo "  - Database data: $INSTALL_DIR/data/db_data"
echo "  - Redis data: $INSTALL_DIR/data/redis_data"
echo ""
echo "Credentials saved to: $INSTALL_DIR/credentials.txt"
echo "======================================"
echo ""

# Save credentials
sudo tee "$INSTALL_DIR/credentials.txt" >/dev/null <<EOF
Docmost Installation Credentials
=================================
VPS IP: $VPS_IP
Access URL: http://${VPS_IP}:8300
APP_SECRET: $APP_SECRET
DB_PASSWORD: $DB_PASSWORD

Installation Date: $(date)
EOF

sudo chmod 600 "$INSTALL_DIR/credentials.txt"

# Pull images
echo "Pulling Docker images..."
sudo docker compose pull

# Start services
echo "Starting Docmost services..."
sudo docker compose up -d

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "Waiting for services to start (30 seconds)..."
sleep 30

echo ""
echo "Service status:"
sudo docker compose ps

echo ""
echo "======================================"
echo "Next Steps:"
echo "======================================"
echo "1. Open your browser and navigate to: http://${VPS_IP}:8300"
echo "2. Complete the setup wizard to create your workspace"
echo "3. All data is stored in: $INSTALL_DIR/data/"
echo ""
echo "Useful commands:"
echo "  - View logs: cd $INSTALL_DIR && sudo docker compose logs -f"
echo "  - Restart: cd $INSTALL_DIR && sudo docker compose restart"
echo "  - Stop: cd $INSTALL_DIR && sudo docker compose down"
echo "  - Upgrade: cd $INSTALL_DIR && sudo docker compose pull && sudo docker compose up --force-recreate --build docmost -d"
echo ""
echo "Health check endpoint: http://${VPS_IP}:8300/api/health"
echo "======================================"
