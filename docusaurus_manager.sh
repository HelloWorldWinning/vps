#!/bin/bash

# docusaurus_manager.sh - Manage Docusaurus Docker deployments
# Template stored in image at /template/my-doc
# Working directory: ./my-doc mapped to /my-doc in container

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PATH="/data/my-doc"
DOCKER_IMAGE="oklove/docusaurus"
PORT="13838"

# Functions for colored output
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_header() { echo -e "${CYAN}$1${NC}"; }

# Function to get public IP
get_public_ip() {
	local ip=""
	# Try multiple services in order of reliability
	ip=$(curl -s --connect-timeout 3 ip.sb 2>/dev/null) ||
		ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null) ||
		ip=$(curl -s --connect-timeout 3 icanhazip.com 2>/dev/null) ||
		ip=$(curl -s --connect-timeout 3 ipinfo.io/ip 2>/dev/null) ||
		ip="localhost"
	echo "$ip"
}

# Function to create docker-compose.yml
create_docker_compose() {
	local target_path="$1"
	cat >"${target_path}/docker-compose.yml" <<'EOF'
services:
  docusaurus:
    image: oklove/docusaurus
    restart: unless-stopped
    ports:
      - "13838:13838"
    volumes:
      - ./my-doc:/my-doc
EOF
	print_success "Created docker-compose.yml at ${target_path}"
}

# Function to show menu header
show_header() {
	clear
	echo ""
	print_header "=========================================="
	print_header "       🦖 Docusaurus Manager 🦖"
	print_header "=========================================="
	echo ""
}

# Function to check if path has valid docusaurus setup
check_setup_status() {
	local path="$1"
	local has_compose=false
	local has_mydoc=false
	local has_package=false

	[ -f "${path}/docker-compose.yml" ] && has_compose=true
	[ -d "${path}/my-doc" ] && has_mydoc=true
	[ -f "${path}/my-doc/package.json" ] && has_package=true

	echo "${has_compose}:${has_mydoc}:${has_package}"
}

# ==================== MAIN SCRIPT ====================

show_header

# Get public IP at start
print_info "Detecting public IP..."
PUBLIC_IP=$(get_public_ip)
print_success "Public IP: ${PUBLIC_IP}"
echo ""

# ==================== STEP 1: Path Selection ====================
print_info "Step 1: Select deployment path"
echo ""
echo "  [Enter] Default: ${DEFAULT_PATH}"
echo "  [1]     Current directory: ${PWD}"
echo "  [0]     Enter custom path manually"
echo ""
read -p "Your choice: " path_choice

case "$path_choice" in
"1")
	DEPLOY_PATH="${PWD}"
	;;
"0")
	read -p "Enter custom path: " custom_path
	if [ -z "$custom_path" ]; then
		DEPLOY_PATH="${DEFAULT_PATH}"
	else
		DEPLOY_PATH="${custom_path}"
	fi
	;;
*)
	DEPLOY_PATH="${DEFAULT_PATH}"
	;;
esac

# Remove trailing slash if present
DEPLOY_PATH="${DEPLOY_PATH%/}"

echo ""
print_info "Selected path: ${DEPLOY_PATH}"

# Create directory if it doesn't exist
if [ ! -d "${DEPLOY_PATH}" ]; then
	print_warning "Directory does not exist. Creating: ${DEPLOY_PATH}"
	mkdir -p "${DEPLOY_PATH}"
fi

cd "${DEPLOY_PATH}"
echo ""

# ==================== STEP 2: Check Status ====================
print_info "Step 2: Checking deployment status at ${DEPLOY_PATH}"
echo ""

# Get setup status
STATUS=$(check_setup_status "${DEPLOY_PATH}")
HAS_COMPOSE=$(echo $STATUS | cut -d: -f1)
HAS_MYDOC=$(echo $STATUS | cut -d: -f2)
HAS_PACKAGE=$(echo $STATUS | cut -d: -f3)

IS_EMPTY=true

if [ "$HAS_COMPOSE" = "true" ] || [ "$HAS_PACKAGE" = "true" ]; then
	IS_EMPTY=false
fi

if [ "$IS_EMPTY" = "true" ]; then
	# Path is empty - set up new deployment
	print_warning "Path is empty or not initialized"
	echo ""
	print_info "Setting up new Docusaurus deployment..."

	# Create docker-compose.yml
	create_docker_compose "${DEPLOY_PATH}"

	# Create empty my-doc directory (container will copy template)
	if [ ! -d "my-doc" ]; then
		mkdir -p my-doc
		print_info "Created empty my-doc directory"
		print_info "Template will be copied from image on first container start"
	fi

	echo ""
	print_success "Initial setup complete!"
	echo ""
	echo "Directory structure:"
	echo "  ${DEPLOY_PATH}/"
	echo "  ├── docker-compose.yml"
	echo "  └── my-doc/ (empty, template will be copied on first run)"
	echo ""

else
	# Path has existing setup - show status
	print_success "Found existing Docusaurus setup"
	echo ""

	echo "Setup status:"
	echo "─────────────────────────────────────"
	[ "$HAS_COMPOSE" = "true" ] && echo "  ✅ docker-compose.yml exists" || echo "  ❌ docker-compose.yml missing"
	[ "$HAS_MYDOC" = "true" ] && echo "  ✅ my-doc directory exists" || echo "  ❌ my-doc directory missing"
	[ "$HAS_PACKAGE" = "true" ] && echo "  ✅ my-doc/package.json exists" || echo "  ⚠️  my-doc/package.json missing (will copy template)"
	echo "─────────────────────────────────────"
	echo ""

	# Create docker-compose.yml if missing
	if [ "$HAS_COMPOSE" = "false" ]; then
		print_warning "Creating missing docker-compose.yml..."
		create_docker_compose "${DEPLOY_PATH}"
	fi

	# Show docker compose status
	echo "Docker Compose Status:"
	echo "─────────────────────────────────────"
	docker compose ps 2>/dev/null || echo "  No containers running or docker compose not available"
	echo "─────────────────────────────────────"
	echo ""
fi

# ==================== STEP 3: Actions ====================
print_info "Step 3: Choose action"
echo ""
echo "  [Enter] Default: Restart (down && up -d)"
echo "  ─────────────────────────────────────"
echo "  [1]     Start       (docker compose up -d)"
echo "  [2]     Stop        (docker compose down)"
echo "  [3]     Logs        (docker compose logs -f)"
echo "  [4]     Pull & Up   (pull latest image && up -d)"
echo "  [5]     Status      (docker compose ps)"
echo "  [6]     Shell       (enter container bash)"
echo "  [7]     Reset       (remove my-doc, copy fresh template)"
echo "  [8]     Show Config (cat docker-compose.yml)"
echo "  [0]     Exit"
echo ""
read -p "Your choice: " action_choice

echo ""

case "$action_choice" in
"1")
	print_info "Starting containers..."
	docker compose up -d
	print_success "Containers started"
	echo ""
	print_info "🌐 Docusaurus available at: http://${PUBLIC_IP}:${PORT}"
	;;
"2")
	print_info "Stopping containers..."
	docker compose down
	print_success "Containers stopped"
	;;
"3")
	print_info "Showing logs (Ctrl+C to exit)..."
	echo ""
	docker compose logs -f
	;;
"4")
	print_info "Pulling latest image and starting..."
	docker compose down 2>/dev/null || true
	docker compose pull
	docker compose up -d
	print_success "Containers updated and started"
	echo ""
	print_info "🌐 Docusaurus available at: http://${PUBLIC_IP}:${PORT}"
	;;
"5")
	echo "Container Status:"
	echo "─────────────────────────────────────"
	docker compose ps
	echo "─────────────────────────────────────"
	;;
"6")
	print_info "Entering container shell (type 'exit' to return)..."
	docker compose exec docusaurus /bin/bash 2>/dev/null || docker compose exec docusaurus /bin/sh
	;;
"7")
	echo ""
	print_warning "⚠️  WARNING: This will DELETE ./my-doc and copy fresh template on next start!"
	print_warning "All your custom content will be LOST!"
	echo ""
	read -p "Type 'yes' to confirm: " confirm
	if [ "$confirm" = "yes" ]; then
		print_info "Stopping containers..."
		docker compose down 2>/dev/null || true
		print_info "Removing my-doc directory..."
		rm -rf ./my-doc
		mkdir -p ./my-doc
		print_success "my-doc directory reset to empty"
		echo ""
		print_info "Starting container to copy fresh template..."
		docker compose up -d
		print_success "Fresh template will be copied. Container starting..."
		echo ""
		print_info "🌐 Docusaurus available at: http://${PUBLIC_IP}:${PORT}"
	else
		print_info "Reset cancelled"
	fi
	;;
"8")
	echo "docker-compose.yml content:"
	echo "─────────────────────────────────────"
	cat docker-compose.yml 2>/dev/null || print_error "docker-compose.yml not found"
	echo "─────────────────────────────────────"
	;;
"0")
	print_info "Exiting..."
	exit 0
	;;
*)
	# Default action: restart
	print_info "Restarting containers (default action)..."
	docker compose down 2>/dev/null || true
	docker compose up -d
	print_success "Containers restarted"
	echo ""
	print_info "🌐 Docusaurus available at: http://${PUBLIC_IP}:${PORT}"
	;;
esac

echo ""
echo "─────────────────────────────────────"
print_success "Working directory: ${DEPLOY_PATH}"
echo "─────────────────────────────────────"
echo ""
