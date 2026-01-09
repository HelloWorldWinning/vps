#!/bin/bash

# Create directory for OpenVPN server
mkdir -p /root/openvpn-server_z

# Create docker-compose.yml
cat <<"EOF" >/root/openvpn-server_z/docker-compose.yml
services:
  openvpn:
    image: oklove/openvpn-server_z
#   network_mode: host
#   container_name: openvpn
    privileged: true
    ports:
      - "81:81"
    restart: always
EOF

# Start the container
cd /root/openvpn-server_z
docker-compose pull
docker compose pull
docker compose down
docker-compose down
docker-compose up -d
docker compose up -d

# Wait for container to initialize (adjust sleep time if needed)
echo "Waiting for OpenVPN container to initialize..."
sleep 10

# Create directory for client configs
mkdir -p /root/openvpn-clients/

# Get public IP address using multiple services
for service in ifconfig.me icanhazip.com checkip.amazonaws.com; do
	if THIS_HOST_IP=$(curl -s --max-time 3 $service); then
		if [[ $THIS_HOST_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			export THIS_HOST_IP
			echo "IP found: $THIS_HOST_IP"
			break # Use break instead of exit to continue script execution
		fi
	fi
done

echo "Detected public IP: ${THIS_HOST_IP}"

# Copy and modify client configuration files
echo "Copying and modifying client configuration files..."
#for i in {1..100}; do
#    docker cp openvpn:/root/client_${i}.ovpn /root/openvpn-clients/ 2>/dev/null
#done

hostname=$(hostname)
CONTAINER_NAME=$(docker ps --filter "ancestor=oklove/openvpn-server_z" --format "{{.Names}}" | head -1)
for i in {1..1000}; do
	docker cp "${CONTAINER_NAME}:/root/client_${i}.ovpn" /root/openvpn-clients/${hostname}_client_${i}.ovpn 2>/dev/null
done
#For i in {1..1000}; do
#	docker cp openvpn:/root/client_${i}.ovpn /root/openvpn-clients/${hostname}_client_${i}.ovpn 2>/dev/null
#Done

sed -i "s/8.210.139.66/$THIS_HOST_IP/g" /root/openvpn-clients/*.ovpn
sed -i '$ a block-ipv6' /root/openvpn-clients/*.ovpn
#zip /root/openvpn-clients/vpn_client_100_configs.zip /root/openvpn-clients/*.ovpn
cd /root/
zip /root/openvpn-clients/${hostname}_vpn_client_1000_configs.zip openvpn-clients/*.ovpn

# Print server information
echo "============================================"
echo "OpenVPN Server Setup Complete"
echo "============================================"
echo "Server IP: ${THIS_HOST_IP}"
echo "Admin Port: 81"
echo "Client configs location: /root/openvpn-clients/"
#echo "Client configs zip location: /root/openvpn-clients/vpn_client_100_configs.zip"
echo "Client configs zip location:  /root/openvpn-clients/${hostname}_vpn_client_1000_configs.zip  "
echo "Number of client configs processed: $(ls -1 /root/openvpn-clients/ | wc -l)"
echo "============================================"

# Check if container is running
if docker ps | grep -q openvpn; then
	echo "OpenVPN container is running"
	docker ps | grep openvpn
else
	echo "Warning: OpenVPN container is not running"
	echo "Check logs with: docker logs openvpn"
fi

# Clean up old/dangling images of oklove/openvpn-server_z
echo ""
echo "============================================"
echo "Cleaning up old images..."
echo "============================================"

# Get the currently used image ID
CURRENT_IMAGE_ID=$(docker ps --filter "ancestor=oklove/openvpn-server_z" --format "{{.Image}}" | head -1)
CURRENT_IMAGE_FULL_ID=$(docker images oklove/openvpn-server_z --format "{{.ID}}" | head -1)

echo "Current image in use: ${CURRENT_IMAGE_ID} (ID: ${CURRENT_IMAGE_FULL_ID})"

# Find all oklove/openvpn-server_z images
ALL_IMAGES=$(docker images oklove/openvpn-server_z --format "{{.ID}}")

# Count images before cleanup
IMAGE_COUNT=$(echo "$ALL_IMAGES" | grep -v "^$" | wc -l)

if [ "$IMAGE_COUNT" -gt 1 ]; then
	echo "Found $IMAGE_COUNT images of oklove/openvpn-server_z"
	echo "Removing old images (keeping current: ${CURRENT_IMAGE_FULL_ID})..."

	for img_id in $ALL_IMAGES; do
		if [ "$img_id" != "$CURRENT_IMAGE_FULL_ID" ]; then
			echo "Removing old image: $img_id"
			docker rmi "$img_id" 2>/dev/null || echo "  (Image $img_id may be in use by stopped containers)"
		fi
	done

	# Also remove dangling images
	DANGLING=$(docker images -f "dangling=true" -q)
	if [ -n "$DANGLING" ]; then
		echo "Removing dangling images..."
		docker rmi $DANGLING 2>/dev/null || echo "  (Some dangling images could not be removed)"
	fi

	echo "Cleanup complete!"
else
	echo "Only one image found, no cleanup needed."
fi

echo "============================================"
