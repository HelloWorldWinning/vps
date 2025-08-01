#!/bin/bash

# Ghost Docker Compose Startup Script
# This script sets up and runs Ghost CMS with all data stored in /data/ghost_d/

set -e # Exit on any error

# Configuration
GHOST_PATH="/data/ghost_d"
MYSQL_ROOT_PASSWORD="ghostrootpass123"
MYSQL_DATABASE="ghost"
MYSQL_USER="ghostuser"
MYSQL_PASSWORD="ghostpass123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Ghost CMS Docker Setup ===${NC}"

# Function to get public IP
get_public_ip() {
	local public_ip=""

	# Try multiple methods to get public IP
	if command -v curl &>/dev/null; then
		public_ip=$(curl -s https://ipv4.icanhazip.com/ 2>/dev/null || curl -s https://api.ipify.org 2>/dev/null || curl -s https://checkip.amazonaws.com 2>/dev/null)
	elif command -v wget &>/dev/null; then
		public_ip=$(wget -qO- https://ipv4.icanhazip.com/ 2>/dev/null || wget -qO- https://api.ipify.org 2>/dev/null)
	fi

	# Clean up the IP (remove any whitespace)
	public_ip=$(echo "$public_ip" | tr -d '[:space:]')

	# Validate IP format
	if [[ $public_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		echo "$public_ip"
	else
		echo "localhost"
	fi
}

# Get domain/IP from user
echo -e "${YELLOW}Ghost URL Configuration:${NC}"
echo -e "Enter your domain or IP address (e.g., yourdomain.com or 192.168.1.100)"
echo -e "Press Enter to use public IP automatically"
read -p "Domain/IP: " user_input

if [ -z "$user_input" ]; then
	# No input provided, get public IP
	echo -e "${YELLOW}Detecting public IP...${NC}"
	public_ip=$(get_public_ip)
	if [ "$public_ip" != "localhost" ]; then
		GHOST_URL="http://${public_ip}:3001"
		echo -e "${GREEN}Using public IP: ${public_ip}${NC}"
	else
		GHOST_URL="http://localhost:3001"
		echo -e "${YELLOW}Could not detect public IP, using localhost${NC}"
	fi
else
	# User provided input
	# Remove http:// or https:// if present
	user_input=$(echo "$user_input" | sed 's|^https\?://||')

	# Check if it's an IP address or domain
	if [[ $user_input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		# It's an IP address
		GHOST_URL="http://${user_input}:3001"
	else
		# It's a domain
		GHOST_URL="http://${user_input}:3001"
	fi
	echo -e "${GREEN}Using URL: ${GHOST_URL}${NC}"
fi

echo ""

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p "${GHOST_PATH}"
mkdir -p "${GHOST_PATH}/ghost-content"
mkdir -p "${GHOST_PATH}/mysql-data"
mkdir -p "${GHOST_PATH}/redis-data"

# Create docker-compose.yml
echo -e "${YELLOW}Creating docker-compose.yml...${NC}"
cat >"${GHOST_PATH}/docker-compose.yml" <<EOF

services:
  ghost:
    image: ghost:5-alpine
    container_name: ghost-app
    restart: unless-stopped
    ports:
      - "3001:2368"
    environment:
      # Database configuration
      database__client: mysql
      database__connection__host: mysql
      database__connection__user: ${MYSQL_USER}
      database__connection__password: ${MYSQL_PASSWORD}
      database__connection__database: ${MYSQL_DATABASE}
      database__connection__charset: utf8mb4
      
      # Ghost configuration
      url: ${GHOST_URL}
      NODE_ENV: production
      
      # Mail configuration (using mailhog for testing)
      mail__transport: SMTP
      mail__options__service: SMTP
      mail__options__host: mailhog
      mail__options__port: 1025
      mail__options__secure: false
      mail__options__auth__user: ""
      mail__options__auth__pass: ""
      
      # Security configuration to fix admin login issues
      security__staffDeviceVerification: false
      
      # Security
      privacy__useGravatar: false
      privacy__useRpcPing: false
      privacy__useUpdateCheck: false
      
    volumes:
      - ${GHOST_PATH}/ghost-content:/var/lib/ghost/content
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - ghost-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:2368/ghost/api/v4/admin/site/"]
      interval: 30s
      timeout: 10s
      retries: 3

  mysql:
    image: mysql:8.0
    container_name: ghost-mysql
    restart: unless-stopped
    # ports:
    #   - "3306:3306"  # Commented out for security - MySQL only accessible within Docker network
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_CHARSET: utf8mb4
      MYSQL_COLLATION: utf8mb4_unicode_ci
    volumes:
      - ${GHOST_PATH}/mysql-data:/var/lib/mysql
    networks:
      - ghost-network
    command: 
      - --innodb-buffer-pool-size=256M
      - --innodb-log-buffer-size=64M
      - --innodb-flush-log-at-trx-commit=1
      - --innodb-flush-method=O_DIRECT
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7.0-alpine
    container_name: ghost-redis
    restart: unless-stopped
    # ports:
    #   - "6379:6379"  # Commented out for security - Redis only accessible within Docker network
    volumes:
      - ${GHOST_PATH}/redis-data:/data
    networks:
      - ghost-network
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru

  mailhog:
    image: mailhog/mailhog:latest
    container_name: ghost-mailhog
    restart: unless-stopped
    # ports:
    #   - "1025:1025"  # SMTP server - only accessible within Docker network
    #   - "8025:8025"  # Web interface - uncomment if you want to access MailHog web UI
    networks:
      - ghost-network

  # Optional: Nginx reverse proxy for SSL/custom domain
  # nginx:
  #   image: nginx:alpine
  #   container_name: ghost-nginx
  #   restart: unless-stopped
  #   ports:
  #     - "80:80"
  #     - "443:443"
  #   volumes:
  #     - ${GHOST_PATH}/nginx.conf:/etc/nginx/nginx.conf:ro
  #     - ${GHOST_PATH}/ssl:/etc/nginx/ssl:ro
  #   depends_on:
  #     - ghost
  #   networks:
  #     - ghost-network

networks:
  ghost-network:
    driver: bridge

volumes:
  ghost-content:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${GHOST_PATH}/ghost-content
  
  mysql-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${GHOST_PATH}/mysql-data
      
  redis-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${GHOST_PATH}/redis-data
EOF

# Create .env file
echo -e "${YELLOW}Creating .env file...${NC}"
cat >"${GHOST_PATH}/.env" <<EOF
# Ghost Configuration
GHOST_URL=${GHOST_URL}
GHOST_PATH=${GHOST_PATH}

# Database Configuration
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}

# Docker Compose Project Name
COMPOSE_PROJECT_NAME=ghost
EOF

# Create additional configuration file for email troubleshooting
echo -e "${YELLOW}Creating email troubleshooting guide...${NC}"
cat >"${GHOST_PATH}/email-config-examples.md" <<'EOF'
# Ghost Email Configuration Examples

## Issue: Admin login fails with "Failed to send email" error

This happens because Ghost tries to send verification emails when logging in from new devices.

### Quick Fix - Disable Email Verification
Add this to your Ghost environment variables in docker-compose.yml:
```
security__staffDeviceVerification: false
```

### Working Email Configurations

#### 1. Gmail SMTP (Simplest - No SSL issues)
```json
"mail": {
  "from": "'Your Name' <your-email@gmail.com>",
  "transport": "SMTP",
  "options": {
    "service": "Gmail",
    "auth": {
      "user": "your-email@gmail.com",
      "pass": "your-app-password"
    }
  }
}
```

#### 2. Mailgun SMTP (Recommended for production)
```json
"mail": {
  "from": "'Your Site' <noreply@yourdomain.com>",
  "transport": "SMTP",
  "options": {
    "service": "Mailgun",
    "host": "smtp.mailgun.org",
    "port": 465,
    "secure": true,
    "auth": {
      "user": "postmaster@yourdomain.com",
      "pass": "your-mailgun-password"
    }
  }
}
```

#### 3. Mailgun SMTP (Alternative - No SSL)
```json
"mail": {
  "from": "'Your Site' <noreply@yourdomain.com>",
  "transport": "SMTP",
  "options": {
    "service": "Mailgun", 
    "host": "smtp.mailgun.org",
    "port": 587,
    "secure": false,
    "auth": {
      "user": "postmaster@yourdomain.com",
      "pass": "your-mailgun-password"
    }
  }
}
```

## How to Apply Email Configuration

1. Edit your config file:
   ```bash
   nano /data/ghost_d/ghost-content/config.production.json
   ```

2. Add the mail configuration to the JSON file

3. Restart Ghost:
   ```bash
   cd /data/ghost_d && docker compose restart ghost
   ```

## Testing Email

1. Try to reset your password from the login screen
2. Check if you receive the reset email
3. If using MailHog (development), check http://localhost:8025

## Common Issues & Fixes

- **SSL errors**: Use `"secure": false` and port 587
- **Wrong version number error**: Remove `"secureConnection"` and use `"secure": false`
- **Gmail issues**: Use app passwords, not regular passwords
- **Login fails**: Set `security__staffDeviceVerification: false` temporarily

EOF
echo -e "${YELLOW}Creating backup script...${NC}"
cat >"${GHOST_PATH}/backup.sh" <<'EOF'
#!/bin/bash

# Ghost Backup Script
BACKUP_DIR="/data/ghost_d/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="ghost_backup_${TIMESTAMP}.tar.gz"

echo "Creating backup directory..."
mkdir -p "${BACKUP_DIR}"

echo "Backing up Ghost content..."
tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" \
    -C /data/ghost_d \
    ghost-content \
    mysql-data \
    redis-data \
    docker-compose.yml \
    .env

echo "Creating MySQL dump..."
docker exec ghost-mysql mysqldump -u root -pghostroot123 ghost > "${BACKUP_DIR}/ghost_mysql_${TIMESTAMP}.sql"

echo "Backup completed: ${BACKUP_DIR}/${BACKUP_FILE}"
echo "MySQL dump: ${BACKUP_DIR}/ghost_mysql_${TIMESTAMP}.sql"

# Keep only last 7 days of backups
find "${BACKUP_DIR}" -name "ghost_backup_*.tar.gz" -mtime +7 -delete
find "${BACKUP_DIR}" -name "ghost_mysql_*.sql" -mtime +7 -delete
EOF

chmod +x "${GHOST_PATH}/backup.sh"

# Create update script
echo -e "${YELLOW}Creating update script...${NC}"
cat >"${GHOST_PATH}/update.sh" <<'EOF'
#!/bin/bash

set -e

echo "Updating Ghost..."
cd /data/ghost_d

# Create backup before update
echo "Creating backup before update..."
./backup.sh

# Pull latest images
echo "Pulling latest images..."
docker compose pull

# Stop services
echo "Stopping services..."
docker compose down

# Start services
echo "Starting services..."
docker compose up -d

# Show status
echo "Checking services status..."
docker compose ps

echo "Update completed!"
echo "Ghost is available at: http://localhost:3001"
echo "Ghost Admin is available at: http://localhost:3001/ghost"
echo "MailHog is available at: http://localhost:8025"
EOF

chmod +x "${GHOST_PATH}/update.sh"

# Set proper permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R 1000:1000 "${GHOST_PATH}/ghost-content" 2>/dev/null || true
chmod -R 755 "${GHOST_PATH}"

# Navigate to ghost directory
cd "${GHOST_PATH}"

# Check if Docker and Docker Compose are installed
if ! command -v docker &>/dev/null; then
	echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
	exit 1
fi

if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
	echo -e "${RED}Docker Compose is not installed. Please install Docker Compose first.${NC}"
	exit 1
fi

# Check if containers are already running
if docker compose ps | grep -q "Up"; then
	echo -e "${YELLOW}Ghost containers are already running. Stopping them first...${NC}"
	docker compose down
fi

# Start Ghost services
echo -e "${GREEN}Starting Ghost services...${NC}"
docker compose up -d

# Wait for services to be healthy
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
sleep 30

# Check service status
echo -e "${GREEN}Checking service status...${NC}"
docker compose ps

# Show logs if any service failed
if docker compose ps | grep -q "Exit"; then
	echo -e "${RED}Some services failed to start. Showing logs:${NC}"
	docker compose logs
	exit 1
fi

echo -e "${GREEN}=== Ghost CMS Setup Complete! ===${NC}"
echo ""
echo -e "${GREEN}Ghost is now running at: ${GHOST_URL}${NC}"
echo -e "${GREEN}Ghost Admin panel: ${GHOST_URL}/ghost${NC}"
echo -e "${YELLOW}MailHog web interface: http://localhost:8025 (if uncommented)${NC}"
echo ""
echo -e "${GREEN}🔒 Security Note: Database ports are secured (not exposed to internet)${NC}"
echo -e "${GREEN}   - MySQL (3306), Redis (6379), MailHog (1025/8025) are only accessible within Docker network${NC}"
echo -e "${GREEN}   - Only Ghost web port (3001) is exposed for public access${NC}"
echo ""
if [[ $GHOST_URL == *"localhost"* ]]; then
	echo -e "${YELLOW}Note: You're using localhost. Ghost will only be accessible from this server.${NC}"
	echo -e "${YELLOW}To access from other machines, restart with a public IP or domain.${NC}"
	echo ""
fi
echo -e "${YELLOW}Important files:${NC}"
echo -e "  - Ghost content: ${GHOST_PATH}/ghost-content"
echo -e "  - MySQL data: ${GHOST_PATH}/mysql-data"
echo -e "  - Redis data: ${GHOST_PATH}/redis-data"
echo -e "  - Docker Compose: ${GHOST_PATH}/docker-compose.yml"
echo -e "  - Environment: ${GHOST_PATH}/.env"
echo -e "  - Backup script: ${GHOST_PATH}/backup.sh"
echo -e "  - Update script: ${GHOST_PATH}/update.sh"
echo -e "  - Email config guide: ${GHOST_PATH}/email-config-examples.md"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo -e "  - View logs: cd ${GHOST_PATH} && docker compose logs -f"
echo -e "  - Stop Ghost: cd ${GHOST_PATH} && docker compose down"
echo -e "  - Start Ghost: cd ${GHOST_PATH} && docker compose up -d"
echo -e "  - Restart Ghost: cd ${GHOST_PATH} && docker compose restart"
echo -e "  - Create backup: cd ${GHOST_PATH} && ./backup.sh"
echo -e "  - Update Ghost: cd ${GHOST_PATH} && ./update.sh"
echo ""
echo -e "${YELLOW}Security Commands:${NC}"
echo -e "  - To access MySQL: docker exec -it ghost-mysql mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE}"
echo -e "  - To access Redis: docker exec -it ghost-redis redis-cli"
echo -e "  - To enable MailHog web UI: uncomment ports in docker-compose.yml"
echo ""
echo -e "${GREEN}Setup your Ghost site by visiting ${GHOST_URL}/ghost${NC}"
echo ""
echo -e "${YELLOW}🚨 IMPORTANT - Admin Login Issue Fix:${NC}"
echo -e "${GREEN}If you can't log in to Ghost admin, it's likely due to email verification.${NC}"
echo -e "${GREEN}This setup disables email verification for admin logins to prevent issues.${NC}"
echo -e "${GREEN}Check ${GHOST_PATH}/email-config-examples.md for email setup options.${NC}"
