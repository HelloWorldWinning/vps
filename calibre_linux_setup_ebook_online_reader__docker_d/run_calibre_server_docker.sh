#!/bin/bash

# Set the directory for docker-compose.yml
COMPOSE_DIR="/data/calibre-library_docker_compose_d"

# Create the directory if it doesn't exist
mkdir -p "$COMPOSE_DIR"

# Change to the directory
cd "$COMPOSE_DIR"

# Create docker-compose.yml file
cat << "EOF" > docker-compose.yml
version: '3'
services:
  calibre:
    container_name: calibre-ebook-server_instance
    image: oklove/calibre-ebook-server:latest
    ports:
      - "188:8080"
    volumes:
      - calibre_services_library_vol:/data/calibre-library
    restart: unless-stopped

volumes:
  calibre_services_library_vol:
    name: calibre_services_library_vol
EOF

echo "Created docker-compose.yml file in $COMPOSE_DIR"

# Start the container
docker-compose up -d

# Wait for a moment to allow the container to start
sleep 5

# Check if the container is running
if docker ps | grep -q calibre-ebook-server_instance; then
    echo "Calibre ebook server is now running"
    echo "You can access it at http://localhost:188"
else
    echo "Failed to start Calibre ebook server"
    docker-compose logs calibre
    exit 1
fi

# Verify volume creation
if docker volume ls | grep -q calibre_services_library_vol; then
    echo "Volume calibre_services_library_vol has been created successfully"
else
    echo "Failed to create volume calibre_services_library_vol"
    exit 1
fi

echo "Setup completed successfully"



#!/bin/bash

# ... [previous parts of the script remain unchanged] ...

# Check if the container is running
if docker ps | grep -q calibre-ebook-server_instance; then
    echo "Calibre ebook server is now running"
    echo "You can access it at http://localhost:188"
    echo "Container details:"
    docker ps | grep calibre-ebook-server_instance
else
    echo "Failed to start Calibre ebook server"
    docker-compose logs calibre
    exit 1
fi

# Verify volume creation and check its size
if docker volume ls | grep -q calibre_services_library_vol; then
    echo "Volume calibre_services_library_vol has been created successfully"
    echo "Volume details:"
    docker volume inspect calibre_services_library_vol
    echo "Estimated volume size:"
    docker run --rm -v calibre_services_library_vol:/data/calibre-library oklove/calibre-ebook-server:latest du -sh /data/calibre-library
else
    echo "Failed to create volume calibre_services_library_vol"
    exit 1
fi

echo "Setup completed successfully"
