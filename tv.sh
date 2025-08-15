#!/bin/bash

# LibreTV Docker Management Script
# This script will install or reinstall the LibreTV container

CONTAINER_NAME="tv"
IMAGE_NAME="bestzwei/libretv:latest"

echo "Checking if container '$CONTAINER_NAME' exists..."

# Check if container exists (running or stopped)
if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
	echo "Container '$CONTAINER_NAME' found. Removing existing setup..."

	# Stop the container if it's running
	echo "Stopping container..."
	docker stop $CONTAINER_NAME 2>/dev/null

	# Remove the container
	echo "Removing container..."
	docker rm $CONTAINER_NAME 2>/dev/null

	# Remove the image
	echo "Removing image '$IMAGE_NAME'..."
	docker rmi $IMAGE_NAME 2>/dev/null

	echo "Cleanup completed."
else
	echo "Container '$CONTAINER_NAME' not found. Proceeding with fresh installation..."
fi

echo "Pulling latest image and starting container..."

# Run the container
docker run -d \
	--name tv \
	--restart unless-stopped \
	-p 8899:8080 \
	-e PASSWORD=tv \
	bestzwei/libretv:latest

if [ $? -eq 0 ]; then
	echo "✓ LibreTV container started successfully!"
	echo "✓ Access it at: http://localhost:8899"
	echo "✓ Password: tv"
else
	echo "✗ Failed to start LibreTV container"
	exit 1
fi



# Check if #tv_identifier exists in crontab, if not add the job
(crontab -l 2>/dev/null | grep -q "#tv_identifier") || (crontab -l 2>/dev/null; echo "51 5 * * * bash <(curl -4sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tv.sh) #tv_identifier") | crontab -
