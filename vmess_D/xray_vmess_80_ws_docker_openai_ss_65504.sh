#!/bin/bash

# Set working directory
XRAY_DIR="/root/xray_docker_d"

# Function to get version using method 1 (using jq)
get_version_method1() {
    if ! command -v jq &> /dev/null; then
        apt-get update && apt-get install -y jq
    fi
    
    local version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name' | sed 's/v//')
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$version"
        return 0
    fi
    return 1
}

# Function to get version using method 2 (using wget and grep)
get_version_method2() {
    if ! command -v wget &> /dev/null; then
        apt-get update && apt-get install -y wget
    fi
    
    local version=$(wget -qO- https://github.com/XTLS/Xray-core/releases/latest | grep -oP 'tag/v\K[^"]+' | head -1)
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$version"
        return 0
    fi
    return 1
}

# Try both methods to get the version
echo "Attempting to get latest version..."
if latest_version_number=$(get_version_method1); then
    echo "✓ Got version using method 1 (jq): $latest_version_number"
elif latest_version_number=$(get_version_method2); then
    echo "✓ Got version using method 2 (wget): $latest_version_number"
else
    echo "Error: Failed to get version using both methods. Using fallback version."
    latest_version_number="1.8.4"  # Fallback to a known stable version
    echo "Using fallback version: $latest_version_number"
fi

# Function to check if Docker image exists
check_docker_image() {
    local tag="$1"
    if docker manifest inspect "ghcr.io/xtls/xray-core:$tag" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Find the correct image tag
if check_docker_image "$latest_version_number"; then
    DOCKER_IMAGE="ghcr.io/xtls/xray-core:$latest_version_number"
    echo "✓ Found image: $DOCKER_IMAGE"
elif check_docker_image "$latest_version_number-ls"; then
    DOCKER_IMAGE="ghcr.io/xtls/xray-core:$latest_version_number-ls"
    echo "✓ Found image: $DOCKER_IMAGE"
else
    echo "✗ No matching Docker image found for version $latest_version_number"
    echo "Trying hardcoded fallback versions..."
    
    # Try some known good versions
    for version in "1.8.4" "1.8.3" "1.8.2"; do
        if check_docker_image "$version"; then
            DOCKER_IMAGE="ghcr.io/xtls/xray-core:$version"
            echo "✓ Found fallback image: $DOCKER_IMAGE"
            break
        elif check_docker_image "$version-ls"; then
            DOCKER_IMAGE="ghcr.io/xtls/xray-core:$version-ls"
            echo "✓ Found fallback image: $DOCKER_IMAGE"
            break
        fi
    done
    
    if [ -z "$DOCKER_IMAGE" ]; then
        echo "Error: No working Docker image found"
        exit 1
    fi
fi

# Create directory and download config
mkdir -p "$XRAY_DIR"
#curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vmess_80_ws.config > "$XRAY_DIR/config.json"
curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vmess_D/vmess_80_openai_to_ss_65504.yml > "$XRAY_DIR/config.yml" 










# Create docker-compose.yml
cat > "$XRAY_DIR/docker-compose.yml" << EOL
services:
  xray:
    image: ${DOCKER_IMAGE}
    container_name: xray_docker_instance
    user: root
    volumes:
      - ./config.yml:/config.yml
    network_mode: "host"  # Changed from ports mapping to network: host
#   ports:
#     - "80:80"
    command: run -c /config.yml
    restart: unless-stopped
EOL

# Change to working directory
cd "$XRAY_DIR"

# Stop existing containers and remove them
docker-compose down

# Pull latest image
docker-compose pull

# Start containers in detached mode
docker-compose up -d

# Wait for container to start
sleep 3

# Show container info
echo "Container information:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter name=xray_docker_instance
echo -e "\nContainer logs:"
docker logs xray_docker_instance
