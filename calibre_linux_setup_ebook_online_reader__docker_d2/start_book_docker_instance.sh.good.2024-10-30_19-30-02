#!/bin/bash

# Create necessary directories
mkdir -p /data/book_docker_d
mkdir -p /data/calibre-library

# Create docker-compose.yml
cat > /data/book_docker_d/docker-compose.yml << 'EOF'
version: '3'
services:
  calibre:
    image: oklove/calibre1
    ports:
      - "188:8080"
    volumes:
      - /data/calibre-library:/calibre-library
    command: >
      calibre-server /calibre-library 
      --enable-auth 
      --disable-use-bonjour 
      --log /var/log/calibre-server.log 
      --access-log /var/log/calibre-server.log 
      --compress-min-size=31457280 
      --disable-use-sendfile
    restart: unless-stopped
EOF

# Pull the Docker image
docker pull oklove/calibre1

# Clone books repository
git clone --depth 1 --filter=blob:none --sparse https://github.com/HelloWorldWinning/books.git /tmp/books
cd /tmp/books
git sparse-checkout set default_d
git pull origin main

# Use Docker container to add books to calibre library
docker run --rm \
  -v /data/calibre-library:/calibre-library \
  -v /tmp/books:/tmp/books \
  oklove/calibre1 \
  calibredb add -r /tmp/books/* --library-path /calibre-library

# Clean up temporary books directory
rm -rf /tmp/books

# Start the service using docker-compose
cd /data/book_docker_d
#docker compose down || true  # Ensure any existing service is stopped
docker-compose down
sleep 2
docker-compose up -d

echo "Calibre server has been started on port 188"
