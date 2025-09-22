#!/bin/bash

# Nginx File Server Installation Script
# This script sets up an nginx container to serve files from /data/d.share on port 7799

set -e # Exit on any error

echo "🚀 Starting Nginx File Server Installation..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
	echo "⚠️  Running as root. This is fine for system setup."
else
	echo "ℹ️  Running as non-root user. May need sudo for some operations."
fi

# Function to run commands with sudo if not root
run_cmd() {
	if [[ $EUID -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

# Verify Docker is available
if ! command -v docker &>/dev/null; then
	echo "❌ Docker is not installed. Please install Docker first."
	exit 1
fi
echo "✅ Docker is available"

# Verify Docker Compose is available
if ! command -v docker-compose &>/dev/null; then
	echo "❌ Docker Compose is not installed. Please install Docker Compose first."
	exit 1
fi
echo "✅ Docker Compose is available"

# Check and handle data directory
DATA_DIR="/data/d.share"
if [[ -d "$DATA_DIR" ]]; then
	echo "✅ Data directory already exists: $DATA_DIR (preserving existing files)"
else
	echo "📁 Creating data directory: $DATA_DIR"
	run_cmd mkdir -p "$DATA_DIR"
	# Set proper permissions for the data directory
	run_cmd chmod 755 "$DATA_DIR"
	echo "✅ Data directory created and permissions set"
fi

# Create the installation directory
INSTALL_DIR="/root/d.share_instance"
echo "📁 Preparing installation directory: $INSTALL_DIR"
run_cmd mkdir -p "$INSTALL_DIR"

# Clean up existing instance if it exists
if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
	echo "🧹 Cleaning up existing instance..."
	cd "$INSTALL_DIR"
	
	# Stop and remove existing containers
	if docker-compose ps | grep -q "Up\|Exit"; then
		echo "   - Stopping existing containers..."
		docker-compose down || true
	fi
	
	# Remove any orphaned containers with the same name pattern
	CONTAINER_NAME=$(docker ps -a --filter "name=dshare_instance-nginx" --format "{{.Names}}" | head -1)
	if [[ -n "$CONTAINER_NAME" ]]; then
		echo "   - Removing orphaned container: $CONTAINER_NAME"
		docker rm -f "$CONTAINER_NAME" || true
	fi
	
	# Clean up any containers that might have the old naming pattern
	docker ps -a --filter "name=nginx" --filter "ancestor=nginx" --format "{{.Names}}" | while read container; do
		if [[ "$container" =~ (dshare|d\.share) ]]; then
			echo "   - Removing container: $container"
			docker rm -f "$container" || true
		fi
	done
	
	echo "✅ Existing instance cleaned up"
else
	echo "ℹ️  No existing instance found"
fi

# Create custom nginx configuration file
echo "📝 Creating nginx configuration file..."
run_cmd tee "$INSTALL_DIR/nginx.conf" >/dev/null <<'EOF'
charset utf-8;

server {
    listen 80;
    server_name localhost;
    
    # Set charset for all responses
    charset utf-8;
    
    location / {
        alias /data/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        
        # Force UTF-8 charset for directory listings and files
        charset utf-8;
        
        # Security headers
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        
        # Enable CORS for file access
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, OPTIONS";
        add_header Access-Control-Allow-Headers "Range";
        
        # Ensure proper content type for text files
        location ~* \.(txt|log|conf|ini|cfg)$ {
            add_header Content-Type "text/plain; charset=utf-8";
        }
        
        # Ensure proper content type for various file types
        location ~* \.(html|htm)$ {
            add_header Content-Type "text/html; charset=utf-8";
        }
        
        location ~* \.(css)$ {
            add_header Content-Type "text/css; charset=utf-8";
        }
        
        location ~* \.(js)$ {
            add_header Content-Type "application/javascript; charset=utf-8";
        }
        
        location ~* \.(json)$ {
            add_header Content-Type "application/json; charset=utf-8";
        }
        
        location ~* \.(xml)$ {
            add_header Content-Type "application/xml; charset=utf-8";
        }
    }
    
    # Handle large files
    client_max_body_size 0;
}
EOF

# Create the docker-compose.yml file with automatic restart
echo "📝 Creating docker-compose.yml..."
run_cmd tee "$INSTALL_DIR/docker-compose.yml" >/dev/null <<'EOF'
services:
  nginx:
    image: nginx:latest
    container_name: dshare_fileserver
    restart: unless-stopped
    volumes:
      # Mount your data directory to /data inside container
      - /data/d.share:/data:ro
      # Mount custom nginx config
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "7799:80"
EOF

echo "✅ docker-compose.yml created with automatic restart policy"

# Change to the installation directory
cd "$INSTALL_DIR"

# Pull the nginx image
echo "📥 Pulling nginx Docker image..."
docker pull nginx:latest

# Start the service
echo "🚀 Starting the nginx file server..."
docker-compose up -d

# Wait a moment for the service to start
sleep 5

# Check if the service is running
if docker-compose ps | grep -q "Up"; then
	echo "✅ Nginx file server is running successfully!"
	echo ""
	echo "🌐 Access your file server at:"
	echo "   - http://localhost:7799"
	
	# Get the first non-loopback IP
	SERVER_IP=$(hostname -I | awk '{print $1}')
	if [[ -n "$SERVER_IP" ]]; then
		echo "   - http://$SERVER_IP:7799"
	fi
	
	echo ""
	echo "📁 File directory: $DATA_DIR"
	echo "⚙️  Installation directory: $INSTALL_DIR"
	echo ""
	echo "🔧 Useful commands:"
	echo "   - Stop server: cd $INSTALL_DIR && docker-compose down"
	echo "   - Restart server: cd $INSTALL_DIR && docker-compose restart"
	echo "   - View logs: cd $INSTALL_DIR && docker-compose logs -f"
	echo "   - Check status: cd $INSTALL_DIR && docker-compose ps"
	echo ""
	echo "🔄 The server will automatically restart after system reboots"
	
	# Show container info
	echo ""
	echo "📊 Container Status:"
	docker-compose ps
	
else
	echo "❌ Failed to start nginx file server. Check the logs:"
	docker-compose logs
	exit 1
fi

echo ""
echo "🎉 Installation completed successfully!"
echo ""
echo "📋 Summary:"
echo "   ✅ Docker and Docker Compose verified"
echo "   ✅ Data directory ready: $DATA_DIR"
echo "   ✅ Previous instance cleaned up (if existed)"
echo "   ✅ Nginx file server running on port 7799"
echo "   ✅ Automatic restart configured"
echo ""
echo "🚀 Your file server is ready to use and will start automatically!"
