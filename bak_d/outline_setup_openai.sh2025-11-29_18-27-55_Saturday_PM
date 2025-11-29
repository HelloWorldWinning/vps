#!/bin/bash
echo """
https://api.slack.com/apps/A080KC8TN57?created=1
8005753479059.8019416940177
cef3f14d2c2abaab3903e61078568107
Verification Token
zCEKJYQkW2LbotjAfc1eVKqA

.ProseMirror  {
	font-size: 240%
}



"""

# Set fixed path
full_path="$HOME/Outline_D"

# Create directory if it doesn't exist
mkdir -p "$full_path"

# Create data directories
mkdir -p "$full_path/data"
mkdir -p "$full_path/data/https-portal-data"
mkdir -p "$full_path/data/storage-data"
mkdir -p "$full_path/data/database-data"

# Adjust ownership to fix permission issues
sudo chown -R 1000:1000 "$full_path/data/storage-data"
sudo chown -R 999:999 "$full_path/data/database-data"
sudo chown -R 1000:1000 "$full_path/data/https-portal-data"
sudo chmod -R 777  "$full_path"
# Change to the working directory
cd "$full_path" || exit 1

# Prompt for the domain name
echo "Enter your domain name (e.g., docs.mycompany.com):"
read DOMAIN

# Generate SECRET_KEY and UTILS_SECRET using openssl
SECRET_KEY=$(openssl rand -hex 32)
UTILS_SECRET=$(openssl rand -hex 32)

# Ask for the authentication provider
echo "Select an authentication provider:"
echo "1) Slack"
echo "2) Google"
echo "3) Microsoft Azure"
read -p "Enter the number of your choice: " AUTH_CHOICE

# Initialize variables for authentication
case $AUTH_CHOICE in
  1)
    AUTH_PROVIDER="Slack"
    read -p "Enter your Slack Client ID: " SLACK_CLIENT_ID
    read -p "Enter your Slack Client Secret: " SLACK_CLIENT_SECRET
    ;;
  2)
    AUTH_PROVIDER="Google"
    read -p "Enter your Google Client ID: " GOOGLE_CLIENT_ID
    read -p "Enter your Google Client Secret: " GOOGLE_CLIENT_SECRET
    ;;
  3)
    AUTH_PROVIDER="Microsoft Azure"
    read -p "Enter your Azure Client ID: " AZURE_CLIENT_ID
    read -p "Enter your Azure Client Secret: " AZURE_CLIENT_SECRET
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

# Create docker.env file
cat > "$full_path/docker.env" <<EOF
NODE_ENV=production
SECRET_KEY=$SECRET_KEY
UTILS_SECRET=$UTILS_SECRET

DATABASE_URL=postgres://user:pass@postgres:5432/outline
PGSSLMODE=disable
REDIS_URL=redis://redis:6379

URL=https://$DOMAIN
PORT=3000

FILE_STORAGE=local
FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data
EOF

# Append authentication provider settings to docker.env
case $AUTH_CHOICE in
  1)
    cat >> "$full_path/docker.env" <<EOF
SLACK_CLIENT_ID=$SLACK_CLIENT_ID
SLACK_CLIENT_SECRET=$SLACK_CLIENT_SECRET
EOF
    ;;
  2)
    cat >> "$full_path/docker.env" <<EOF
GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET
EOF
    ;;
  3)
    cat >> "$full_path/docker.env" <<EOF
AZURE_CLIENT_ID=$AZURE_CLIENT_ID
AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET
EOF
    ;;
esac

# Optionally configure SMTP settings
echo "Do you want to configure SMTP settings for email notifications? (y/N)"
read SMTP_CHOICE

if [ "$SMTP_CHOICE" = "y" ]; then
  read -p "Enter your SMTP host: " SMTP_HOST
  read -p "Enter your SMTP port: " SMTP_PORT
  read -p "Enter your SMTP username: " SMTP_USERNAME
  read -p "Enter your SMTP password: " SMTP_PASSWORD
  read -p "Enter your 'From' email address: " SMTP_FROM_EMAIL
  read -p "Enter your 'Reply-To' email address: " SMTP_REPLY_EMAIL

  cat >> "$full_path/docker.env" <<EOF
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USERNAME=$SMTP_USERNAME
SMTP_PASSWORD=$SMTP_PASSWORD
SMTP_FROM_EMAIL=$SMTP_FROM_EMAIL
SMTP_REPLY_EMAIL=$SMTP_REPLY_EMAIL
EOF
fi

# Generate docker-compose.yml file
cat > "$full_path/docker-compose.yml" <<EOF
services:
  outline:
    image: docker.getoutline.com/outlinewiki/outline:latest
    env_file: ./docker.env
#   ports:
#     - "3000:3000"
    restart: always
    volumes:
      - ./data/storage-data:/var/lib/outline/data
    depends_on:
      - postgres
      - redis

  redis:
    image: redis
    env_file: ./docker.env
#   ports:
#     - "6379:6379"
    restart: always
    volumes:
      - ./data/redis.conf:/redis.conf
    command: ["redis-server", "/redis.conf"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 30s
      retries: 3

  postgres:
    image: postgres
    env_file: ./docker.env
#   ports:
#     - "5432:5432"
    restart: always
    volumes:
      - ./data/database-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-d", "outline", "-U", "user"]
      interval: 30s
      timeout: 20s
      retries: 3
    environment:
      POSTGRES_USER: 'user'
      POSTGRES_PASSWORD: 'pass'
      POSTGRES_DB: 'outline'

  https-portal:
    image: steveltn/https-portal
    container_name: webpage_outline
    env_file: ./docker.env
    ports:
      - '80:80'
      - '443:443'
    links:
      - outline
    restart: always
    volumes:
      - ./data/https-portal-data:/var/lib/https-portal
    healthcheck:
      test: ["CMD", "service", "nginx", "status"]
      interval: 30s
      timeout: 20s
      retries: 3
    environment:
      DOMAINS: '$DOMAIN -> http://outline:3000'
      STAGE: 'production'
      WEBSOCKET: 'true'
      CLIENT_MAX_BODY_SIZE: '0'
EOF

echo "Configuration files generated successfully at $full_path"
echo "Starting Docker services..."

# Pull and start Docker containers
docker compose pull
sudo chmod -R 777  $full_path
docker compose up -d
# Wait for services to start
sleep 7
docker compose down
sleep 7
sudo chmod -R 777  "$full_path"
docker compose up -d
# Show running containers
echo "Running Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E 'outline|redis|postgres|webpage_outline'

