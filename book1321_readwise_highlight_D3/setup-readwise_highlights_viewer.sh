#!/bin/bash

# Exit on any error
set -e

# Define variables
BASE_DIR="/data/readwise_highlights_viewer_d"
DATA_DIR="${BASE_DIR}/data"
COMPOSE_FILE="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/book1321_readwise_highlight_D/docker-compose.yml"
DATA_FILE="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/book1321_readwise_highlight_D/data/readwise-data.csv"

# Create necessary directories
echo "Creating directories..."
mkdir -p "${DATA_DIR}"

# Download required files
echo "Downloading docker-compose.yml..."
wget -4 --no-check-certificate "${COMPOSE_FILE}" -O "${BASE_DIR}/docker-compose.yml"

echo "Downloading readwise-data.csv..."
wget -4 --no-check-certificate "${DATA_FILE}" -O "${DATA_DIR}/readwise-data.csv"

# Navigate to the directory
cd "${BASE_DIR}"

# Stop any existing containers
echo "Stopping existing containers..."
docker-compose down || true

# Wait for containers to fully stop
echo "Waiting for containers to stop..."


docker-compose pull

sleep 2

# Start the service
echo "Starting the service..."
docker-compose up -d

# Check container status
echo "Checking container status..."
docker ps | grep readwise-viewer_instance

echo "Setup complete! The service should be available on port 189"
