#!/bin/bash

# Create directory for OpenVPN server
mkdir -p /root/openvpn-server_z_udp

# Create docker-compose.yml
cat << "EOF" > /root/openvpn-server_z_udp/docker-compose.yml
version: '3'
services:
  openvpn:
    image: oklove/openvpn-server_z_udp
    container_name: openvpn
    privileged: true
    ports:
      - "82:82"
    restart: always
EOF

# Start the container
cd /root/openvpn-server_z_udp
docker-compose pull
docker-compose up -d

# Wait for container to initialize (adjust sleep time if needed)
echo "Waiting for OpenVPN container to initialize..."
sleep 10



# Create directory for client configs
mkdir -p /root/ovpn-clients_udp/

# Get public IP address using multiple services
for service in ifconfig.me icanhazip.com checkip.amazonaws.com; do
    if THIS_HOST_IP=$(curl -s --max-time 3 $service); then
        if [[ $THIS_HOST_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            export THIS_HOST_IP
            echo "IP found: $THIS_HOST_IP"
            break  # Use break instead of exit to continue script execution
        fi
    fi
done

echo "Detected public IP: ${THIS_HOST_IP}"

# Copy and modify client configuration files
echo "Copying and modifying client configuration files..."
for i in {1..100}; do
    docker cp openvpn:/root/client_${i}.ovpn /root/ovpn-clients_udp/ 2>/dev/null
done

sed -i "s/8.210.139.66/$THIS_HOST_IP/g" /root/ovpn-clients_udp/*.ovpn
#zip /root/ovpn-clients_udp/vpn_client_100_configs.zip /root/ovpn-clients_udp/*.ovpn
cd /root/
zip  /root/ovpn-clients_udp/vpn_client_100_configs.zip ovpn-clients_udp/*.ovpn  





# Print server information
echo "============================================"
echo "OpenVPN Server Setup Complete"
echo "============================================"
echo "Server IP: ${THIS_HOST_IP}"
echo "Admin Port: 82"
echo "Client configs location: /root/ovpn-clients_udp/"
echo "Client configs zip location: /root/ovpn-clients_udp/vpn_client_100_configs.zip"
echo "Number of client configs processed: $(ls -1 /root/ovpn-clients_udp/ | wc -l)"
echo "============================================"

# Check if container is running
if docker ps | grep -q openvpn; then
    echo "OpenVPN container is running"
    docker ps | grep openvpn
else
    echo "Warning: OpenVPN container is not running"
    echo "Check logs with: docker logs openvpn"
fi
