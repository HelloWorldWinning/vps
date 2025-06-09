#!/bin/bash

# OpenVPN Image and Container Test Script
# Usage: ./test_image.sh [IMAGE_NAME] [--start-container]

IMAGE_NAME="${1:-oklove/openvpn-server_z_udp}"
START_CONTAINER="${2}"

# Colors
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=================================="
echo "🔍 OpenVPN Complete Test"
echo "=================================="
echo "📦 Image: $IMAGE_NAME"
echo -e "==================================${NC}"

# Test 1: Basic Image Information
echo -e "${BLUE}PART 1: Image Information${NC}"
docker run --rm "$IMAGE_NAME" bash -c "
# Install ip command for testing
echo 'Installing ip command...'
apt-get update >/dev/null 2>&1 && apt-get install -y iproute2 >/dev/null 2>&1

echo -e '${BLUE}📦 OpenVPN Version:${NC}'
openvpn --version | head -1

echo -e '\n${BLUE}🔐 OpenSSL Version:${NC}'
openssl version

echo -e '\n${BLUE}🌐 Docker Container Interfaces:${NC}'
echo 'IPv4:'
ip -4 addr show
echo -e '\nIPv6:'
ip -6 addr show
"

# Test 2: Check for Running Containers
echo -e "\n${BLUE}PART 2: OpenVPN Network Interfaces${NC}"
RUNNING_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i openvpn | head -1)

if [ -n "$RUNNING_CONTAINER" ]; then
    echo -e "${GREEN}✅ Found running OpenVPN container: $RUNNING_CONTAINER${NC}"
    
    docker exec "$RUNNING_CONTAINER" bash -c "
        # Install ip if needed
        apt-get update >/dev/null 2>&1 && apt-get install -y iproute2 >/dev/null 2>&1
        
        echo -e '${BLUE}🌐 OpenVPN Server Network Interfaces:${NC}'
        ip addr show
        
        echo -e '\n${BLUE}🔧 OpenVPN Process Status:${NC}'
        ps aux | grep openvpn | grep -v grep || echo 'No OpenVPN process found'
        
        echo -e '\n${BLUE}🌐 TUN Interface Detail:${NC}'
        ip addr show tun0 2>/dev/null || echo 'TUN interface not active'
        
        echo -e '\n${BLUE}📊 Network Routes:${NC}'
        ip route show | grep tun0 2>/dev/null || echo 'No TUN routes found'
        
        echo -e '\n${BLUE}🔌 Listening Ports:${NC}'
        netstat -tulpn | grep -E ':82|:1194' || echo 'OpenVPN port not listening'
        
        echo -e '\n${BLUE}👥 Connected Clients:${NC}'
        if [ -f /var/log/openvpn/status.log ]; then
            grep 'CLIENT_LIST' /var/log/openvpn/status.log | wc -l | awk '{print \"Connected clients: \" \$1}'
            grep 'CLIENT_LIST' /var/log/openvpn/status.log | head -3 | awk -F',' '{print \"  \" \$2 \" (\" \$3 \")\"}' 2>/dev/null || echo '  No clients connected'
        else
            echo 'No status log found'
        fi
    " 2>/dev/null

elif [ "$START_CONTAINER" = "--start-container" ]; then
    echo -e "${YELLOW}🚀 Starting temporary OpenVPN container...${NC}"
    
    # Start container
    TEMP_CONTAINER="openvpn-test-$"
    docker run -d \
        --name "$TEMP_CONTAINER" \
        --cap-add=NET_ADMIN \
        --device /dev/net/tun \
        -p 82:82/udp \
        "$IMAGE_NAME" >/dev/null
    
    # Wait for startup
    echo "Waiting for OpenVPN to start..."
    sleep 8
    
    # Test the running container
    docker exec "$TEMP_CONTAINER" bash -c "
        apt-get update >/dev/null 2>&1 && apt-get install -y iproute2 >/dev/null 2>&1
        
        echo -e '${GREEN}✅ Temporary OpenVPN container started${NC}'
        echo -e '${BLUE}🌐 OpenVPN Server Network Interfaces:${NC}'
        ip addr show
        
        echo -e '\n${BLUE}🔧 OpenVPN Process:${NC}'
        ps aux | grep openvpn | grep -v grep
        
        echo -e '\n${BLUE}🌐 TUN Interface:${NC}'
        ip addr show tun0 2>/dev/null || echo 'TUN interface not yet active'
        
        echo -e '\n${BLUE}🔌 OpenVPN Port:${NC}'
        netstat -tulpn | grep :82 || echo 'Port not yet listening'
    " 2>/dev/null
    
    # Cleanup
    echo -e "\n${YELLOW}🧹 Cleaning up temporary container...${NC}"
    docker stop "$TEMP_CONTAINER" >/dev/null 2>&1
    docker rm "$TEMP_CONTAINER" >/dev/null 2>&1
    
else
    echo -e "${YELLOW}⚠️  No running OpenVPN container found${NC}"
    echo -e "${BLUE}To test OpenVPN network interfaces:${NC}"
    echo "1. Start a container: docker run -d --name openvpn-test --cap-add=NET_ADMIN --device /dev/net/tun -p 82:82/udp $IMAGE_NAME"
    echo "2. Run: $0 $IMAGE_NAME"
    echo "3. Or run: $0 $IMAGE_NAME --start-container (creates temporary container)"
fi

echo -e "\n${CYAN}✅ Complete test finished!${NC}"
