#!/bin/bash

# Function to prompt for authentication details
prompt_auth_details() {
    read -p "Username: " username
    read -p "Password: " password
    echo "Username: $username"
    echo "Password: $password"
}

# Function to create docker-compose file
create_docker_compose() {
    local auth_flag=$1
    local compose_file="/data/book_docker_d/docker-compose.yml"
    
    local cmd="calibre-server /calibre-library --disable-use-bonjour --log /var/log/calibre-server.log --access-log /var/log/calibre-server.log --compress-min-size=31457280 --disable-use-sendfile"
    
    if [ "$auth_flag" = "true" ]; then
        cmd="sh -c 'calibre-server --manage-users -- add $username $password && $cmd --enable-auth'"
    fi
    
    cat > "$compose_file" << EOF
version: '3'
services:
  calibre:
    image: oklove/calibre1
    ports:
      - "188:8080"
    volumes:
      - /data/calibre-library:/calibre-library
    command: >
      $cmd
    restart: unless-stopped
#######  --enable-auth
EOF
}

# Create directories
mkdir -p /data/book_docker_d /data/calibre-library

# Quick prompt with 5s timeout
echo "Select access mode (5s timeout):"
echo "1) myself (default)"
echo "2) everyone"
read -t 5 choice

# Default to "myself" if no input or timeout
case $choice in
    2)
        create_docker_compose "false"
        auth_enabled=false
        ;;
    *)
        prompt_auth_details
        create_docker_compose "true"
        auth_enabled=true
        ;;
esac

# Pull image and setup
docker pull oklove/calibre1

# Clone and setup books
git clone --depth 1 --filter=blob:none --sparse https://github.com/HelloWorldWinning/books.git /tmp/books
cd /tmp/books
git sparse-checkout set default_d
git pull origin main

# Configure server and add books
if [ "$auth_enabled" = "true" ]; then
    docker run --rm \
        -v /data/calibre-library:/calibre-library \
        -v /tmp/books:/tmp/books \
        oklove/calibre1 \
        calibredb add -r /tmp/books/* --library-path /calibre-library
else
    docker run --rm \
        -v /data/calibre-library:/calibre-library \
        -v /tmp/books:/tmp/books \
        oklove/calibre1 \
        calibredb add -r /tmp/books/* --library-path /calibre-library
fi

# Cleanup and start service
rm -rf /tmp/books
cd /data/book_docker_d
docker-compose down
sleep 2
docker-compose up -d

# Show completion message
echo "================================================================="
echo "Calibre server started on port 188"
if [ "$auth_enabled" = "true" ]; then
    echo "Authentication enabled with:"
    echo "Username: $username"
    echo "Password: $password"
else
    echo "Authentication disabled - open to everyone"
fi
echo "================================================================="

sleep 2

# Function to check container status and get details
check_calibre_status() {
    local CONTAINER_ID=$(docker-compose ps -q calibre)
    if [ -z "$CONTAINER_ID" ]; then
        echo "❌ Error: Calibre container is not running"
        exit 1
    fi

    local STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_ID")
    local HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_ID" 2>/dev/null || echo "N/A")
    local UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER_ID")
    local PORT_STATUS=$(netstat -tuln | grep ":188 " || echo "")

    echo "----------------------------------------"
    echo "📚 Calibre Server Status"
    echo "----------------------------------------"
    echo "🔄 Container Status: $STATUS"
    echo "⏰ Started At: $UPTIME"
    echo "🏥 Health Status: $HEALTH"

    if [ -n "$PORT_STATUS" ]; then
        echo "🌐 Port 188: LISTENING"
    else
        echo "🌐 Port 188: NOT LISTENING"
    fi

    # Check if service is responding
    if curl -s -m 5 http://localhost:188 > /dev/null; then
        echo "✅ Web Interface: ACCESSIBLE"
    else
        echo "⚠️ Web Interface: NOT RESPONDING"
    fi
    echo "----------------------------------------"
}

# Wait for container to start and check status
check_calibre_status

# Monitor logs for startup
echo "📋 Recent Logs:"
docker-compose logs --tail=5 calibre
