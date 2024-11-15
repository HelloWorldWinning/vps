#!/bin/bash

host_name=$(hostname)

# Create the directories
mkdir -p /root/jupyter166_d
mkdir -p /root/jupyter1666_d

# Copy the docker-compose.yml files to their respective directories
cat > /root/jupyter166_d/docker-compose.yml <<EOL
services:
  jupyter166:
    image: oklove/jupyter166
    hostname : ${host_name} 
##  restart: unless-stopped
    restart: always
    ports:
      - "166:166"
    volumes:
  #   - /data:/data
#     - /:/${host_name}
      - /:/Host
EOL

cat > /root/jupyter1666_d/docker-compose.yml <<EOL
services:
  jupyter1666:
    image: oklove/jupyter1666
    hostname : "${host_name}"
 ## restart: unless-stopped
    restart: always
    ports:
      - "1666:1666"
    volumes:
  #   - /data:/data
  #   - /:/${host_name}
      - /:/Host
EOL

# Change to the /root/jupyter166_d directory and start the container
cd /root/jupyter166_d
docker-compose down
sleep 2
docker-compose pull
docker-compose up -d

# Change to the /root/jupyter1666_d directory and start the container
cd /root/jupyter1666_d
docker-compose down
sleep 2
docker-compose pull
docker-compose up -d

# Check the running status of the two specific instances
echo "Running containers:"
docker ps -a | grep -E "jupyter166|jupyter1666"
