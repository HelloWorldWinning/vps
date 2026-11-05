#!/bin/bash

set -e

echo "========================================"
echo "Minimalist Web Notepad Setup"
echo "========================================"
echo ""

# Define paths
PROJECT_DIR="/root/Minimalist_Web_Notepad_passwd"
DATA_DIR="/data/Minimalist_Web_Notepad_passwd"

# Create directories
echo "Creating directories..."
mkdir -p "$PROJECT_DIR"
mkdir -p "$DATA_DIR"

# Navigate to project directory
cd "$PROJECT_DIR"

# Clone or pull the repository
echo "Downloading Minimalist Web Notepad files..."
##if [ -d ".git" ]; then
##	echo "Repository exists, pulling latest changes..."
##	git pull origin docker
##else
##	echo "Cloning repository..."
##	# Remove directory contents if it exists but isn't a git repo
##	rm -rf "$PROJECT_DIR"
##	mkdir -p "$PROJECT_DIR"
##	cd "$PROJECT_DIR"
##	#git clone --branch docker --single-branch https://github.com/pereorga/minimalist-web-notepad.git .
##	#git clone --branch docker --single-branch https://github.com/HelloWorldWinning/minimalist-web-notepad.git .
##	git clone --branch main --single-branch https://github.com/HelloWorldWinning/search_list_minimalist-web-notepad .
##fi

# Navigate to project directory first (in case it exists)
cd "$PROJECT_DIR" 2>/dev/null || true

# Stop and remove containers BEFORE deleting project directory
echo "Stopping existing containers..."
docker-compose down 2>/dev/null || true

# Remove the if-else completely and replace with:
echo "Removing existing installation..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "Cloning repository..."
#git clone --branch main --single-branch https://github.com/HelloWorldWinning/search_list_minimalist-web-notepad .
git clone --branch main --single-branch https://github.com/HelloWorldWinning/passwd_search_list_minimalist-web-notepad .

echo "Files downloaded successfully."

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
#cat >docker-compose.yml <<'EOF'
#services:
#  minimalist-web-notepad:
#    build: .
#    ports:
#      - "3099:80"
#    volumes:
#      - /data/Minimalist_Web_Notepad:/var/www/html/_tmp
#    environment:
#      - MWN_BASE_URL=
#      - MWN_SAVE_PATH=/var/www/html/_tmp
#    restart: unless-stopped
#EOF

cat >docker-compose.yml <<EOF
services:
  minimalist-web-notepad:
    build: .
    ports:
      - "3099:80"
    volumes:
      - ${DATA_DIR}:/var/www/html/_tmp
    environment:
      - MWN_BASE_URL=
      - MWN_SAVE_PATH=/var/www/html/_tmp
    restart: unless-stopped
EOF

# Set permissions for data directory
echo "Setting permissions..."
chmod -R 755 "$DATA_DIR"

# Stop existing container if running
echo "Stopping existing containers..."
docker-compose down 2>/dev/null || true

# Build and start the container
echo "Building and starting container..."
docker-compose up -d --build

# Wait for container to be ready
echo "Waiting for service to start..."
sleep 3

# Get container info
CONTAINER_ID=$(docker-compose ps -q minimalist-web-notepad)
CONTAINER_NAME=$(docker ps --filter "id=$CONTAINER_ID" --format "{{.Names}}")

# Step 1: Get public IP address (IPv4 first, then IPv6 fallback)
IP=$(curl -4 -s --max-time 2 ifconfig.me 2>/dev/null || curl -4 -s --max-time 2 icanhazip.com 2>/dev/null || curl -4 -s --max-time 2 api.ipify.org 2>/dev/null)

if [ -z "$IP" ]; then
	# Fallback to IPv6
	IP=$(curl -6 -s --max-time 2 ifconfig.me 2>/dev/null || curl -6 -s --max-time 2 icanhazip.com 2>/dev/null || curl -6 -s --max-time 2 api6.ipify.org 2>/dev/null)
fi

if [ -z "$IP" ]; then
	# Last resort: local IP
	IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

if [ -z "$IP" ]; then
	IP="localhost"
fi

echo ""
echo "========================================"
echo "✓ Minimalist Web Notepad Setup Complete"
echo "========================================"
echo ""
echo "Instance Information:"
echo "  • Container Name: $CONTAINER_NAME"
echo "  • Container ID: $CONTAINER_ID"
echo "  • Port: 3099"
echo "  • Access URL: http://${IP}:3099"
echo "  • Project Directory: $PROJECT_DIR"
echo "  • Data Directory: $DATA_DIR"
echo ""
echo "Usage:"
echo "  • Open: http://${IP}:3099/mynote"
echo "  • View logs: docker-compose -f $PROJECT_DIR/docker-compose.yml logs -f"
echo "  • Stop: docker-compose -f $PROJECT_DIR/docker-compose.yml down"
echo "  • Restart: docker-compose -f $PROJECT_DIR/docker-compose.yml restart"
echo ""
echo "Notes are saved to: $DATA_DIR"
echo "========================================"
