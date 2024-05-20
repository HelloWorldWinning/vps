#!/bin/bash

host=$(hostname)

# Create the directories
mkdir -p jupyter166_d
mkdir -p jupyter1666_d

# Copy the docker-compose.yml files to their respective directories
cat > jupyter166_d/docker-compose.yml <<EOL
version: '3'
services:
  jupyter166:
    image: oklove/jupyter166
    ports:
      - "166:166"
    volumes:
  #   - /data:/data
      - /:/${host}
EOL

cat > jupyter1666_d/docker-compose.yml <<EOL
version: '3'
services:
  jupyter1666:
    image: oklove/jupyter1666
    ports:
      - "1666:1666"
    volumes:
  #   - /data:/data
      - /:/${host}
EOL

# Change to the jupyter166_d directory and start the container
cd jupyter166_d
docker-compose up -d

# Change to the jupyter1666_d directory and start the container
cd ../jupyter1666_d
docker-compose up -d

# Check the running status of the two specific instances
echo "Running containers:"
docker ps -a | grep -E "jupyter166|jupyter1666"
