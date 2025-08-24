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

# Create the data directory
DATA_DIR="/data/d.share"
echo "📁 Creating data directory: $DATA_DIR"
run_cmd mkdir -p "$DATA_DIR"

# Set proper permissions for the data directory
run_cmd chmod 755 "$DATA_DIR"
echo "✅ Data directory created and permissions set"

# Create the installation directory
INSTALL_DIR="/root/d.share_instance"
echo "📁 Creating installation directory: $INSTALL_DIR"
run_cmd mkdir -p "$INSTALL_DIR"

# Create the docker-compose.yml file
echo "📝 Creating docker-compose.yml..."
run_cmd tee "$INSTALL_DIR/docker-compose.yml" >/dev/null <<'EOF'
services:
  nginx:
    image: nginx
    volumes:
      # Mount your data directory to /data inside container
      - /data/d.share:/data
    ports:
      - "7799:80"
    # Configure nginx to serve root path from /data directory
    command: >
      sh -c "echo 'server {
        listen 80;
        server_name localhost;
        
        location / {
          alias /data/;
          autoindex on;
          autoindex_exact_size off;
          autoindex_localtime on;
        }
      }' > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
EOF

echo "✅ docker-compose.yml created"

# Change to the installation directory
cd "$INSTALL_DIR"

# Pull the nginx image
echo "📥 Pulling nginx Docker image..."
docker pull nginx

# Start the service
echo "🚀 Starting the nginx file server..."
docker-compose up -d

# Wait a moment for the service to start
sleep 3

# Check if the service is running
if docker-compose ps | grep -q "Up"; then
	echo "✅ Nginx file server is running successfully!"
	echo ""
	echo "🌐 Access your file server at:"
	echo "   - http://localhost:7799"
	echo "   - http://$(hostname -I | awk '{print $1}'):7799"
	echo ""
	echo "📁 File directory: $DATA_DIR"
	echo "⚙️  Installation directory: $INSTALL_DIR"
	echo ""
	echo "🔧 Useful commands:"
	echo "   - Stop server: cd $INSTALL_DIR && docker-compose down"
	echo "   - Restart server: cd $INSTALL_DIR && docker-compose restart"
	echo "   - View logs: cd $INSTALL_DIR && docker-compose logs -f"
	echo "   - Check status: cd $INSTALL_DIR && docker-compose ps"
else
	echo "❌ Failed to start nginx file server. Check the logs:"
	docker-compose logs
	exit 1
fi

# Create a simple management script
echo "📝 Creating management script..."
run_cmd tee "$INSTALL_DIR/manage.sh" >/dev/null <<'EOF'
#!/bin/bash
# Nginx File Server Management Script

case "$1" in
    start)
        echo "Starting nginx file server..."
        docker-compose up -d
        ;;
    stop)
        echo "Stopping nginx file server..."
        docker-compose down
        ;;
    restart)
        echo "Restarting nginx file server..."
        docker-compose restart
        ;;
    status)
        echo "Nginx file server status:"
        docker-compose ps
        ;;
    logs)
        echo "Nginx file server logs:"
        docker-compose logs -f
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Available commands:"
        echo "  start   - Start the file server"
        echo "  stop    - Stop the file server" 
        echo "  restart - Restart the file server"
        echo "  status  - Show service status"
        echo "  logs    - Show and follow logs"
        exit 1
        ;;
esac
EOF

run_cmd chmod +x "$INSTALL_DIR/manage.sh"
echo "✅ Management script created at $INSTALL_DIR/manage.sh"

echo ""
echo "🎉 Installation completed successfully!"
echo ""
echo "📋 Summary:"
echo "   ✅ Docker and Docker Compose verified"
echo "   ✅ Data directory created: $DATA_DIR"
echo "   ✅ Nginx file server running on port 7799"
echo "   ✅ Management script available"
echo ""
echo "🚀 Your file server is ready to use!"
