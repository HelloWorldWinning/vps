#!/bin/bash

# Set up error handling
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required commands
for cmd in docker-compose git; do
    if ! command_exists "$cmd"; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Create necessary directories
mkdir -p /data/typecho_d/data/themes/

# Create the docker-compose.yml file
cat << "EOF" > /data/typecho_d/docker-compose.yml
version: '3'
services:
  typecho:
    image: 80x86/typecho:latest
    container_name: typecho
    restart: always
    tmpfs:
      - /tmp
    volumes:
      - /data/typecho_d/data:/data
    environment:
      - PHP_TZ=Asia/Shanghai
      - PHP_MAX_EXECUTION_TIME=600
    ports:
      - "90:80"
    healthcheck:
      test: ["CMD", "curl", "-INfs", "http://localhost/", "||", "exit", "1"]
      interval: 6s
      timeout: 3s
      retries: 3
EOF

echo "docker-compose.yml created successfully."

# Step 1: Run docker-compose up -d
echo "Starting Typecho container..."
cd /data/typecho_d
docker-compose up -d

# Check if the container is running
if ! docker-compose ps | grep -q "Up"; then
    echo "Error: Failed to start Typecho container. Please check docker-compose logs."
    exit 1
fi

echo "Typecho container started successfully."


# Step 2: Clone the repository
# echo "Cloning Typecho theme..."
#git clone https://bitbucket.org/imlinhai/typecho-theme-simple /data/typecho_d/data/themes/typecho-theme-simple


# Step 2: Clone the repository
echo "Cloning Typecho theme..."
git clone https://github.com/HelloWorldWinning/vps.git /tmp/vps
mv /tmp/vps/typecho-theme-simple /data/typecho_d/data/themes/
rm -rf /tmp/vps


# Check Typecho container status
echo "Checking Typecho container status..."
CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' typecho)

if [ "$CONTAINER_STATUS" = "running" ]; then
    echo "Typecho container is running."
else
    echo "Warning: Typecho container is not running. Current status: $CONTAINER_STATUS"
    echo "You may need to start the container manually."
fi

# Final setup message
if [ "$CONTAINER_STATUS" = "running" ]; then
    echo "Setup completed successfully. Typecho is running and favicon has been added."
else
    echo "Setup completed, but Typecho container is not running. Please check and start the container if necessary."
fi


echo "Setup completed successfully."




