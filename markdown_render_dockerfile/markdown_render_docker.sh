#!/usr/bin/bash

# Get the hostname of the current machine
get_host_name=$(hostname)

echo "Starting setup on host: $get_host_name"

# Prompt for username and password
read -p "Enter username (leave empty for a): " username
read -p "Enter password (leave empty for a): " password
echo

# Create a new directory for the markdown render docker compose file
mkdir markdown_render_docker

# Change into the newly created directory
cd markdown_render_docker

# Use a heredoc to write the docker-compose.yml file
cat << EOF > docker-compose.yml
version: '3.8'

services:
  markdown-app:
    image: oklove/markdown:latest
    hostname: $get_host_name
    restart: unless-stopped
    ports:
      - "177:177"
    volumes:
    # - /data:/data
      - /:/Host
    environment:
      - USERNAME=${username:-a}
      - PASSWORD=${password:-a}
EOF

docker-compose down
docker-compose up -d

echo "Docker compose setup for markdown-app has been created successfully."

