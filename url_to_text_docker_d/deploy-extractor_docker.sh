#!/bin/bash

# Get the directory of the source files (where the script is run from)
SOURCE_DIR=$(pwd)

# Create full path directory
sudo mkdir -p /data/text-extractor_docker_d

# Copy all necessary files to the deployment directory
echo "Copying application files..."
cp -r "$SOURCE_DIR"/{app.py,requirements.txt,Dockerfile,docker-compose.yml} /data/text-extractor_docker_d/

# Change to deployment directory
cd /data/text-extractor_docker_d

# Create docker-compose.yml (this is optional since we copied it, but keeping for consistency)
cat << "EOF" > docker-compose.yml
version: '3'
services:
  text-extractor:
    image: oklove/text-extractor
    network_mode: "host"
    environment:
      - FLASK_APP=app.py
      - FLASK_RUN_PORT=9977
    volumes:
      - ./:/app
    restart: unless-stopped
EOF

# Start docker compose
docker-compose up -d

# Wait for container to initialize
sleep 2

# Check running status
echo "Container Status:"
docker ps --filter "name=text-extractor" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check logs
echo -e "\nContainer Logs:"
docker-compose logs
