#!/bin/bash

# Set up error handling
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check and install required commands
for cmd in "docker compose" git; do
    if [ "$cmd" = "docker compose" ]; then
        if ! docker compose version >/dev/null 2>&1; then
            echo "Docker Compose V2 is not installed. Installing..."
            bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_docker_compose_v2_claude.sh)
        fi
    elif ! command_exists "$cmd"; then
        echo "$cmd is not installed. Installing..."
        case "$cmd" in
            git)
                apt update && apt -y install git
                ;;
        esac
    fi
done

# Create necessary directories
path_d="/root/typecho_d"
mkdir -p "$path_d"
mkdir -p "$path_d/data/themes"
mkdir -p "$path_d/data/plugins"

echo "Installation completed successfully!"
echo "Docker compose version:"
docker compose version

# Create the docker compose.yml file
cat << EOF > "${path_d}/docker-compose.yml"
version: '3'
services:
  typecho:
    image: 80x86/typecho:latest
    container_name: typecho
    restart: always
    tmpfs:
      - /tmp
    volumes:
      - ./data:/data
    environment:
      - PHP_TZ=Asia/Shanghai
      - PHP_MAX_EXECUTION_TIME=600
    ports:
      - "88:80"
    healthcheck:
      test: ["CMD", "curl", "-INfs", "http://localhost/", "||", "exit", "1"]
      interval: 6s
      timeout: 3s
      retries: 3
EOF

echo "docker-compose.yml created successfully."

# Step 1: Run docker compose up -d
echo "Starting Typecho container..."
cd "$path_d"
docker compose down
docker compose pull
docker compose up -d

# Check if the container is running
if ! docker compose ps | grep -q "Up"; then
    echo "Error: Failed to start Typecho container. Please check docker compose logs."
    exit 1
fi

echo "Typecho container started successfully."

# Step 2: Clone the repository and move only the theme folder
echo "Cloning Typecho theme..."
TMP_DIR=$(mktemp -d)
git clone https://github.com/HelloWorldWinning/vps.git "$TMP_DIR/vps"

# Check if the theme directory already exists and remove it
if [ -d "$path_d/data/themes/typecho-theme-simple" ]; then
    echo "The theme 'typecho-theme-simple' already exists. Removing it..."
    rm -rf "$path_d/data/themes/typecho-theme-simple"
fi

# Move only the theme folder
mv "$TMP_DIR/vps/typecho-theme-simple" "$path_d/data/themes/"

# Clean up
rm -rf "$TMP_DIR"

echo "Typecho theme 'typecho-theme-simple' has been updated successfully."

# Step 3: Clone the comment2telegram plugin repository
echo "Cloning Comment2Telegram plugin..."
TMP_DIR=$(mktemp -d)
git clone https://github.com/Adoream/typecho-plugin-comment2telegram.git "$TMP_DIR/comment2telegram"

# Check if the plugin directory already exists and remove it
if [ -d "$path_d/data/plugins/Comment2Telegram" ]; then
    echo "The plugin 'Comment2Telegram' already exists. Removing it..."
    rm -rf "$path_d/data/plugins/Comment2Telegram"
fi

# Move the plugin folder
mv "$TMP_DIR/comment2telegram" "$path_d/data/plugins/Comment2Telegram"

# Clean up
rm -rf "$TMP_DIR"
echo "Comment2Telegram plugin has been added successfully."

# Install CommentShowIp plugin
echo "Installing CommentShowIp plugin..."
git clone https://github.com/SocialSisterYi/Typecho-Plugin-CommentShowIp "$path_d/data/plugins/CommentShowIp"

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
    echo "Setup completed successfully. Typecho is running."
else
    echo "Setup completed, but Typecho container is not running. Please check and start the container if necessary."
fi

echo "Setup completed successfully."
