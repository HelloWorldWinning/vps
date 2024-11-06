#!/bin/bash

# Uninstall old versions
echo "Removing old versions..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-compose
sudo apt-get autoremove -y

# Install required packages
echo "Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
echo "Adding Docker's GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo "Setting up Docker repository..."
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
echo "Installing Docker Engine..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
echo "Adding user to docker group..."
sudo usermod -aG docker $USER

# Install Docker Compose v2
echo "Installing Docker Compose v2..."
sudo apt-get install -y docker-compose-plugin


echo "
Installation completed successfully!
NOTE: You may need to log out and log back in for group changes to take effect.
To test installation, you can run:
  docker run hello-world
  docker compose version
"
# Verify installations
echo "Installation complete! Verifying versions..."
docker run hello-world
docker rm $(docker ps -a -q --filter ancestor=hello-world)
docker rmi hello-world
docker --version
docker compose version
