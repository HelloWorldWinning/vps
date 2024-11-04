#!/bin/bash

# Create directory for OpenVPN server
mkdir -p /root/openvpn-server_z

# Create docker-compose.yml
cat << "EOF" > /root/openvpn-server_z/docker-compose.yml
version: '3'
services:
  openvpn:
    image: oklove/openvpn-server_z
    container_name: openvpn
    privileged: true
    ports:
      - "81:81"
    restart: always
EOF

# Start the container
cd /root/openvpn-server_z
docker-compose pull
docker-compose up -d

# Wait for container to initialize (adjust sleep time if needed)
echo "Waiting for OpenVPN container to initialize..."
sleep 10

# Create directory for client configs
mkdir -p /root/ovpn-clients/

# Get public IP address
THIS_HOST_IP=$(curl -s ifconfig.me)
echo "Detected public IP: ${THIS_HOST_IP}"

# Copy and modify client configuration files
echo "Copying and modifying client configuration files..."
for i in {1..100}; do
    # Copy client config from container
    docker cp openvpn:/root/client_${i}.ovpn /root/ovpn-clients/ 2>/dev/null
    
    # If file exists, replace IP address
    if [ -f "/data/ovpn-clients/client_${i}.ovpn" ]; then
        sed -i "s/8.210.139.66/${THIS_HOST_IP}/g" "/root/ovpn-clients/client_${i}.ovpn"
        echo "Processed client_${i}.ovpn"
    fi
done

# Print server information
echo "============================================"
echo "OpenVPN Server Setup Complete"
echo "============================================"
echo "Server IP: ${THIS_HOST_IP}"
echo "Admin Port: 81"
echo "Client configs location: /root/ovpn-clients/"
echo "Number of client configs processed: $(ls -1 /root/ovpn-clients/ | wc -l)"
echo "============================================"

# Check if container is running
if docker ps | grep -q openvpn; then
    echo "OpenVPN container is running"
    docker ps | grep openvpn
else
    echo "Warning: OpenVPN container is not running"
    echo "Check logs with: docker logs openvpn"
fi
