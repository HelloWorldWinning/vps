#!/bin/bash

# Set up error handling
set -e

# Define the installation directory
full_path="$HOME/calibre_highlight_converter_fastapi_docker2"

# Create the installation directory
echo "Creating installation directory at $full_path"
mkdir -p "$full_path"
cd "$full_path"

# Create docker-compose.yml
echo "Creating docker-compose.yml"
cat > docker-compose.yml << 'EOL'
version: '3.8'
services:
  highlights_converter:
    image: oklove/fastapi_calibrew_highlights_convertor:latest
    container_name: calibre_highlights_converter
    ports:
      - "187:187"
    restart: unless-stopped
#   volumes:
#     - ./static:/app/static
    environment:
      - TZ=Asia/Shanghai
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:187/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
EOL

# Create static directory for volumes
#echo "Creating static directory for volumes"
#mkdir -p static

# Stop any existing containers
echo "Stopping existing containers..."
docker-compose down

# Pull the latest image
echo "Pulling latest image..."
docker-compose pull

# Start the container
echo "Starting container..."
docker-compose up -d

# Wait for container to initialize
echo "Waiting for container to initialize..."
sleep 3

# Display container status
echo "Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep calibre_highlights_converter

# Check if the service is responding
echo "Checking service health..."
if curl -s -f http://localhost:187/ > /dev/null; then
    echo "Service is up and running!"
else
    echo "Warning: Service may not be running properly. Please check logs with: docker-compose logs"
fi

echo "Setup complete! The service should be available at http://localhost:187/"
