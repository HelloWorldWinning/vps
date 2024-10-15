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
      - "8080:8080"
    volumes:
      - calibre-library_vol_docker:/data/calibre-library
    restart: unless-stopped

volumes:
  calibre-library_vol_docker:
    name: calibre-library_vol_docker
EOF

echo "Created docker-compose.yml file in $COMPOSE_DIR"

# Start the container
docker-compose up -d

echo "Calibre ebook server is now running"
echo "You can access it at http://localhost:8080"

# Display the logs
echo "Displaying logs (press Ctrl+C to exit):"
docker-compose logs -f
