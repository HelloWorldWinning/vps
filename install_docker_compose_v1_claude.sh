#!/bin/bash

# Define variables
COMPOSE_VERSION="1.29.2"
DESTINATION="/usr/local/bin/docker-compose"

# Print current system information
echo "System Architecture: $(uname -s)-$(uname -m)"
echo "Installing Docker Compose v${COMPOSE_VERSION}"

# Download Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o ${DESTINATION}

# Make it executable
sudo chmod +x ${DESTINATION}

# Verify installation
if [ -x "${DESTINATION}" ]; then
    echo "Installation successful!"
    echo "Docker Compose version:"
    docker-compose --version
else
    echo "Installation failed!"
    exit 1
fi

# Print information about coexisting versions
echo -e "\nDocker Compose versions installed:"
echo "V1 (docker-compose):"
docker-compose --version
echo "V2 (docker compose):"
docker compose version
