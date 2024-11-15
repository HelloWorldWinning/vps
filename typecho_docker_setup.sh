#!/bin/bash

##### https://bitbucket.org/imlinhai/typecho-theme-simple/src/main/
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
#mkdir -p /data/typecho_d/data/themes/
$path_D="/root/typecho_d"
#mkdir -p /data/typecho_d/data/themes/
mkdir -p $path_d

# Create the docker-compose.yml file
#cat << "EOF" > /data/typecho_d/docker-compose.yml
cat << EOF > ${path_D}/docker-compose.yml
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

# Step 1: Run docker-compose up -d
echo "Starting Typecho container..."
#cd /data/typecho_d
cd  $path_d
docker-compose pull
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


## Step 2: Clone the repository
#echo "Cloning Typecho theme..."
#git clone https://github.com/HelloWorldWinning/vps.git /tmp/vps
#mv /tmp/vps/typecho-theme-simple /data/typecho_d/data/themes/
#rm -rf /tmp/vps

# Step 2: Clone the repository and move only the theme folder
echo "Cloning Typecho theme..."
TMP_DIR=$(mktemp -d)
git clone https://github.com/HelloWorldWinning/vps.git "$TMP_DIR/vps"

# Check if the theme directory already exists and remove it
if [ -d "/data/typecho_d/data/themes/typecho-theme-simple" ]; then
    echo "The theme 'typecho-theme-simple' already exists. Removing it..."
    rm -rf "/data/typecho_d/data/themes/typecho-theme-simple"
fi

# Move only the theme folder
#mv "$TMP_DIR/vps/typecho-theme-simple" /data/typecho_d/data/themes/
mv "$TMP_DIR/vps/typecho-theme-simple" $path_d/data/themes/

# Clean up
rm -rf "$TMP_DIR"

echo "Typecho theme 'typecho-theme-simple' has been updated successfully."


# Step 3: Clone the comment2telegram plugin repository
echo "Cloning Comment2Telegram plugin..."
TMP_DIR=$(mktemp -d)
git clone https://github.com/Adoream/typecho-plugin-comment2telegram.git "$TMP_DIR/comment2telegram"

# Check if the plugin directory already exists and remove it
if [ -d "/data/typecho_d/data/plugins/Comment2Telegram" ]; then
    echo "The plugin 'Comment2Telegram' already exists. Removing it..."
    rm -rf "/data/typecho_d/data/plugins/Comment2Telegram"
fi

# Move the plugin folder
#mv "$TMP_DIR/comment2telegram" /data/typecho_d/data/plugins/Comment2Telegram
mv "$TMP_DIR/comment2telegram"  $path_d/data/plugins/Comment2Telegram

# Clean up
rm -rf "$TMP_DIR"
echo "Comment2Telegram plugin has been added successfully."



#git clone https://github.com/SocialSisterYi/Typecho-Plugin-CommentShowIp  /data/typecho_d/data/plugins/CommentShowIp
git clone https://github.com/SocialSisterYi/Typecho-Plugin-CommentShowIp  $path_d/data/plugins/CommentShowIp


### git clone https://github.com/vndroid/RobotsLogs /data/typecho_d/data/plugins/RobotsLogs

### VisitorLogger
### https://www.maisblog.cn/index.php/archives/153/comment-page-4#comments
### https://github.com/PengMai1998/VisitorLogger


 

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




