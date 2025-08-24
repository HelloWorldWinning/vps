#!/bin/bash
# Configuration
COMPOSE_FILE="/root/book_docker_d/docker-compose.yml"

# Get the old image ID before building
OLD_IMAGE=$(docker images oklove/calibre1 --format "table {{.ID}}" | tail -n +2 | head -n 1)

# Stop and remove existing containers
docker-compose -f $COMPOSE_FILE down

# Build new image in current directory
docker build -t oklove/calibre1 .

# Start new containers with updated image
docker-compose -f $COMPOSE_FILE up -d

# Remove old image if it exists and is different from current
if [ ! -z "$OLD_IMAGE" ]; then
    CURRENT_IMAGE=$(docker images oklove/calibre1 --format "table {{.ID}}" | tail -n +2 | head -n 1)
    if [ "$OLD_IMAGE" != "$CURRENT_IMAGE" ]; then
        docker image rm $OLD_IMAGE 2>/dev/null || true
    fi
fi

# Push the new image
docker push oklove/calibre1
