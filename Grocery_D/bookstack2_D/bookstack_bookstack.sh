#!/bin/bash

# Create base directory if it doesn't exist
mkdir -p /root/bookstack_D

# Create docker-compose.yml
cat > /root/bookstack_D/docker-compose.yml << 'EOF'
---
services:
  mariadb:
    image: lscr.io/linuxserver/mariadb:latest
    container_name: bookstack_db
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - MYSQL_ROOT_PASSWORD=bookstack123!@#
      - MYSQL_DATABASE=bookstackapp
      - MYSQL_USER=bookstack
      - MYSQL_PASSWORD=bookstack456!@#
    volumes:
      - /root/bookstack_D/db:/config
    restart: unless-stopped

  bookstack:
    image: lscr.io/linuxserver/bookstack:latest
    container_name: bookstack
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - APP_URL=http://0.0.0.0:6875
      - DB_HOST=mariadb
      - DB_PORT=3306
      - DB_DATABASE=bookstackapp
      - DB_USERNAME=bookstack
      - DB_PASSWORD=bookstack456!@#
      - APP_KEY=base64:5T0wYnHHJKQzXH2WBr6yqL9DZWRZnhhX0ekBXJ8Xdso=
    volumes:
      - /root/bookstack_D/config:/config
    ports:
      - "0.0.0.0:6875:80"
    depends_on:
      - mariadb
    restart: unless-stopped
EOF

# Create directories
mkdir -p /root/bookstack_D/config
mkdir -p /root/bookstack_D/db

# Set permissions
chown 1000:1000 /root/bookstack_D/config
chown 1000:1000 /root/bookstack_D/db

# Start the containers
cd /root/bookstack_D
docker-compose up -d

echo "
==========================================================================
Setup complete! Please wait about 1-2 minutes for the services to fully start.

Access BookStack at: http://YOUR_SERVER_IP:6875

Default login credentials:
Email:    admin@admin.com
Password: password

Database Credentials (for your records):
Root Password: bookstack123!@#
User Password: bookstack456!@#

IMPORTANT SECURITY NOTES:
1. Change the default admin password after first login!
2. Consider changing the database passwords in docker-compose.yml
3. If needed, generate a new APP_KEY with:
   docker run -it --rm --entrypoint /bin/bash lscr.io/linuxserver/bookstack:latest appkey

The services will automatically restart when your server reboots.
==========================================================================
"

# Check if docker-compose is installed, if not provide installation instructions
if ! command -v docker-compose &> /dev/null; then
    echo "WARNING: docker-compose is not installed! Install it with:"
    echo "curl -L \"https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
    echo "chmod +x /usr/local/bin/docker-compose"
fi

# Check if docker is running
if ! docker info &> /dev/null; then
    echo "WARNING: Docker is not running! Start it with:"
    echo "systemctl start docker"
fi
