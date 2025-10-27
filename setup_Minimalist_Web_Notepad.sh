#!/bin/bash

set -e

echo "========================================"
echo "Minimalist Web Notepad Setup"
echo "========================================"
echo ""

# Define paths
PROJECT_DIR="/root/Minimalist_Web_Notepad"
DATA_DIR="/data/Minimalist_Web_Notepad"

# Create directories
echo "Creating directories..."
mkdir -p "$PROJECT_DIR"
mkdir -p "$DATA_DIR"

# Navigate to project directory
cd "$PROJECT_DIR"

# Clone or pull the repository
echo "Downloading Minimalist Web Notepad files..."
if [ -d ".git" ]; then
    echo "Repository exists, pulling latest changes..."
    git pull origin docker
else
    echo "Cloning repository..."
    # Remove directory contents if it exists but isn't a git repo
    rm -rf "$PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    git clone --branch docker --single-branch https://github.com/pereorga/minimalist-web-notepad.git .
fi
echo "Files downloaded successfully."

# Create docker-compose.yml
echo "Creating docker-compose.yml..."
cat > docker-compose.yml <<'EOF'
services:
  minimalist-web-notepad:
    build: .
    ports:
      - "3090:80"
    volumes:
      - /data/Minimalist_Web_Notepad:/var/www/html/_tmp
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

echo ""
echo "========================================"
echo "✓ Minimalist Web Notepad Setup Complete"
echo "========================================"
echo ""
echo "Instance Information:"
echo "  • Container Name: $CONTAINER_NAME"
echo "  • Container ID: $CONTAINER_ID"
echo "  • Port: 3090"
echo "  • Access URL: http://localhost:3090"
echo "  • Project Directory: $PROJECT_DIR"
echo "  • Data Directory: $DATA_DIR"
echo ""
echo "Usage:"
echo "  • Open: http://localhost:3090/mynote"
echo "  • View logs: docker-compose -f $PROJECT_DIR/docker-compose.yml logs -f"
echo "  • Stop: docker-compose -f $PROJECT_DIR/docker-compose.yml down"
echo "  • Restart: docker-compose -f $PROJECT_DIR/docker-compose.yml restart"
echo ""
echo "Notes are saved to: $DATA_DIR"
echo "========================================"
