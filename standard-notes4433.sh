#!/bin/bash
# Standard Notes - All-in-one installer & manager (HTTPS @ https://IP:PORT)
# Works on a clean Linux host with Docker + (docker compose OR docker-compose)
# V2 stack: server (monolith API+Files), MySQL, Redis, LocalStack, optional Web, Nginx TLS

set -euo pipefail

# -----------------------------
# Pretty printing
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}➜ $1${NC}"; }

# -----------------------------
# Defaults (edit if needed)
# -----------------------------
PROJECT_DIR="/root/standard-notes"
NETWORK_NAME="standard-notes"

API_PORT_IN=3000   # internal API (container)
FILES_PORT_IN=3104 # internal Files server (container, maps to 3125 outside if needed)
WEB_PORT_IN=80     # internal web (container)

# EXTERNAL HTTPS (host) — will be set during install via prompt (5s timeout).
# Default fallback if nothing is entered: 4433
HTTPS_PORT_OUT=4433

DB_PORT_OUT=3306
REDIS_PORT_OUT=6379
LOCALSTACK_PORT_OUT=4566

# -----------------------------
# Compose wrapper
# -----------------------------
compose_cmd() {
	if docker compose version >/dev/null 2>&1; then
		echo "docker compose"
	elif command -v docker-compose >/dev/null 2>&1; then
		echo "docker-compose"
	else
		print_error "Docker Compose not found. Install Docker Compose."
		exit 1
	fi
}

# -----------------------------
# Pre-flight checks
# -----------------------------
require_root() { [ "${EUID:-0}" -eq 0 ] || {
	print_error "Run as root (sudo)."
	exit 1
}; }
require_docker() {
	command -v docker >/dev/null 2>&1 || {
		print_error "Docker not found. Install Docker."
		exit 1
	}
}

detect_ip() {
	local ip
	ip=$(hostname -I 2>/dev/null | awk '{print $1}')
	[ -z "$ip" ] && ip="127.0.0.1"
	echo "$ip"
}

# Determine currently configured external HTTPS port from docker-compose.yml
get_current_https_port() {
	local compose="${PROJECT_DIR}/docker-compose.yml"
	local port=""
	if [ -f "$compose" ]; then
		port=$(grep -E '^\s*-\s*"[0-9]+:3001"' "$compose" 2>/dev/null | head -n1 | sed -E 's/.*"([0-9]+):3001".*/\1/')
	fi
	if [ -n "${port}" ]; then
		echo "${port}"
	else
		echo "${HTTPS_PORT_OUT}"
	fi
}

# Prompt for external HTTPS port with 5s timeout; default to 4433 if empty/invalid
prompt_https_port() {
	local input=""
	echo -ne "${YELLOW}➜ External HTTPS port [default 4433] (5s to respond): ${NC}"
	if read -t 5 -r input; then
		:
	else
		input=""
	fi
	if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]; then
		HTTPS_PORT_OUT="$input"
	else
		HTTPS_PORT_OUT=4433
	fi
	print_info "Using external HTTPS port: ${HTTPS_PORT_OUT}"
}

# -----------------------------
# Install flow
# -----------------------------
install_stack() {
	require_root
	require_docker
	local DCMD
	DCMD=$(compose_cmd)
	local SERVER_IP
	SERVER_IP=$(detect_ip)

	# Ask for port (5s timeout, default 4433)
	prompt_https_port

	print_info "Setting up Standard Notes at ${PROJECT_DIR} (IP: ${SERVER_IP})"

	# fresh dir
	if [ -d "$PROJECT_DIR" ]; then
		print_info "Existing install found. Stopping & removing..."
		cd "$PROJECT_DIR"
		$DCMD down -v || true
		cd /root
		rm -rf "$PROJECT_DIR"
	fi

	mkdir -p "$PROJECT_DIR"/{data/mysql,data/redis,uploads,logs,nginx,certs}
	cd "$PROJECT_DIR"
	print_success "Directory structure created"

	# secrets
	print_info "Generating secrets..."
	AUTH_JWT_SECRET=$(openssl rand -hex 32)
	AUTH_SERVER_ENCRYPTION_SERVER_KEY=$(openssl rand -hex 32)
	VALET_TOKEN_SECRET=$(openssl rand -hex 32)
	DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
	print_success "Secrets generated"

	# .env (V2 minimal + files URL)
	print_info "Writing .env..."
	cat >.env <<EOF
###### # DB # ######
DB_HOST=db
DB_PORT=3306
DB_USERNAME=std_notes_user
DB_PASSWORD=${DB_PASSWORD}
DB_DATABASE=standard_notes_db
DB_TYPE=mysql

######### # CACHE # #########
REDIS_PORT=6379
REDIS_HOST=cache
CACHE_TYPE=redis

######## # KEYS # ########
AUTH_JWT_SECRET=${AUTH_JWT_SECRET}
AUTH_SERVER_ENCRYPTION_SERVER_KEY=${AUTH_SERVER_ENCRYPTION_SERVER_KEY}
VALET_TOKEN_SECRET=${VALET_TOKEN_SECRET}

# Public files URL via Nginx on https://${SERVER_IP}:${HTTPS_PORT_OUT}
PUBLIC_FILES_SERVER_URL=https://${SERVER_IP}:${HTTPS_PORT_OUT}/files
EOF
	print_success ".env written"

	# TLS cert for IP (SAN)
	print_info "Generating self-signed TLS cert (SAN = ${SERVER_IP})..."
	cat >nginx/openssl.cnf <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = v3_req
distinguished_name = dn
[ dn ]
CN = ${SERVER_IP}
O  = Self-Hosted Standard Notes
[ v3_req ]
subjectAltName = @alt_names
[ alt_names ]
IP.1 = ${SERVER_IP}
EOF
	openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
		-keyout certs/server.key \
		-out certs/server.crt \
		-config nginx/openssl.cnf >/dev/null 2>&1
	print_success "Cert created at certs/server.crt (import it into your OS trust store)"

	# Nginx
	print_info "Writing nginx.conf..."
	cat >nginx/nginx.conf <<'EOF'
events {}
http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;
  sendfile      on;
  tcp_nopush    on;
  tcp_nodelay   on;
  keepalive_timeout  65;
  server_tokens off;

  gzip on;
  gzip_types text/plain text/css application/json application/javascript application/xml+rss application/xml text/javascript image/svg+xml;

  map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
  }

  server {
    # INTERNAL LISTENER (container) stays on 3001; host port is mapped by docker-compose.
    listen 3001 ssl http2;
    server_name _;

    ssl_certificate     /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy no-referrer;
    client_max_body_size 50m;

    # Web app
    location / {
      proxy_pass http://web:80;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_http_version 1.1;
      proxy_set_header Upgrade           $http_upgrade;
      proxy_set_header Connection        $connection_upgrade;
    }

    # API at /api/*
    location ^~ /api/ {
      rewrite ^/api/?(.*)$ /$1 break;
      proxy_pass http://server:3000/;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_http_version 1.1;
      proxy_set_header Upgrade           $http_upgrade;
      proxy_set_header Connection        $connection_upgrade;
    }

    # Files server at /files/*
    location ^~ /files/ {
      rewrite ^/files/?(.*)$ /$1 break;
      proxy_pass http://server:3104/;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_cache off;
    }
  }
}
EOF
	print_success "nginx.conf written"

	# LocalStack bootstrap (official)
	print_info "Writing LocalStack bootstrap..."
	cat >localstack_bootstrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "configuring sns/sqs"
echo "==================="
LOCALSTACK_HOST=localhost
AWS_REGION=us-east-1
LOCALSTACK_DUMMY_ID=000000000000

get_all_queues() { awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sqs list-queues; }
create_queue()   { local n=$1; awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sqs create-queue --queue-name ${n}; }
get_all_topics() { awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns list-topics; }
create_topic()   { local n=$1; awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns create-topic --name ${n}; }
link_queue_and_topic() { local t=$1 q=$2; awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns subscribe --topic-arn ${t} --protocol sqs --notification-endpoint ${q}; }
get_queue_arn_from_name() { local n=$1; echo "arn:aws:sns:${AWS_REGION}:${LOCALSTACK_DUMMY_ID}:$n"; }
get_topic_arn_from_name() { local n=$1; echo "arn:aws:sns:${AWS_REGION}:${LOCALSTACK_DUMMY_ID}:$n"; }

PAYMENTS_TOPIC_NAME="payments-local-topic";               echo "creating topic $PAYMENTS_TOPIC_NAME"; create_topic ${PAYMENTS_TOPIC_NAME}; PAYMENTS_TOPIC_ARN=$(get_topic_arn_from_name $PAYMENTS_TOPIC_NAME)
SYNCING_SERVER_TOPIC_NAME="syncing-server-local-topic";   echo "creating topic $SYNCING_SERVER_TOPIC_NAME"; create_topic ${SYNCING_SERVER_TOPIC_NAME}; SYNCING_SERVER_TOPIC_ARN=$(get_topic_arn_from_name $SYNCING_SERVER_TOPIC_NAME)
AUTH_TOPIC_NAME="auth-local-topic";                       echo "creating topic $AUTH_TOPIC_NAME"; create_topic ${AUTH_TOPIC_NAME}; AUTH_TOPIC_ARN=$(get_topic_arn_from_name $AUTH_TOPIC_NAME)
FILES_TOPIC_NAME="files-local-topic";                     echo "creating topic $FILES_TOPIC_NAME"; create_topic ${FILES_TOPIC_NAME}; FILES_TOPIC_ARN=$(get_topic_arn_from_name $FILES_TOPIC_NAME)
ANALYTICS_TOPIC_NAME="analytics-local-topic";             echo "creating topic $ANALYTICS_TOPIC_NAME"; create_topic ${ANALYTICS_TOPIC_NAME}; ANALYTICS_TOPIC_ARN=$(get_topic_arn_from_name $ANALYTICS_TOPIC_NAME)
REVISIONS_TOPIC_NAME="revisions-server-local-topic";      echo "creating topic $REVISIONS_TOPIC_NAME"; create_topic ${REVISIONS_TOPIC_NAME}; REVISIONS_TOPIC_ARN=$(get_topic_arn_from_name $REVISIONS_TOPIC_NAME)
SCHEDULER_TOPIC_NAME="scheduler-local-topic";             echo "creating topic $SCHEDULER_TOPIC_NAME"; create_topic ${SCHEDULER_TOPIC_NAME}; SCHEDULER_TOPIC_ARN=$(get_topic_arn_from_name $SCHEDULER_TOPIC_NAME)

QUEUE_NAME="analytics-local-queue"; echo "creating queue $QUEUE_NAME"; create_queue ${QUEUE_NAME}; ANALYTICS_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $PAYMENTS_TOPIC_ARN $ANALYTICS_QUEUE_ARN
QUEUE_NAME="auth-local-queue";      echo "creating queue $QUEUE_NAME"; create_queue ${QUEUE_NAME}; AUTH_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $PAYMENTS_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $AUTH_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $FILES_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $REVISIONS_TOPIC_ARN $AUTH_QUEUE_ARN
QUEUE_NAME="files-local-queue";     echo "creating queue $QUEUE_NAME"; create_queue ${QUEUE_NAME}; FILES_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $AUTH_TOPIC_ARN $FILES_QUEUE_ARN; link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $FILES_QUEUE_ARN
QUEUE_NAME="syncing-server-local-queue"; echo "creating queue $QUEUE_NAME"; create_queue ${QUEUE_NAME}; SYNCING_SERVER_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $SYNCING_SERVER_QUEUE_ARN; link_queue_and_topic $FILES_TOPIC_ARN $SYNCING_SERVER_QUEUE_ARN; link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $AUTH_TOPIC_ARN $SYNCING_SERVER_QUEUE_ARN
QUEUE_NAME="revisions-server-local-queue"; echo "creating queue $QUEUE_NAME"; create_queue ${QUEUE_NAME}; REVISIONS_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $REVISIONS_QUEUE_ARN; link_queue_and_topic $REVISIONS_TOPIC_ARN $REVISIONS_QUEUE_ARN
QUEUE_NAME="scheduler-local-queue"; echo "creating queue $QUEUE_NAME"; create_queue ${QUEUE_NAME}; SCHEDULER_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME)

echo "all topics are:";   get_all_topics
echo "all queues are:";   get_all_queues
EOF
	chmod +x localstack_bootstrap.sh
	print_success "LocalStack bootstrap created"

	# Compose (V2)
	print_info "Writing docker-compose.yml..."
	cat >docker-compose.yml <<EOF
version: '3.8'

services:
  db:
    image: mysql:8.0
    container_name: standard-notes-db
    restart: unless-stopped
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    environment:
      MYSQL_DATABASE: \${DB_DATABASE}
      MYSQL_USER: \${DB_USERNAME}
      MYSQL_PASSWORD: \${DB_PASSWORD}
      MYSQL_ROOT_PASSWORD: \${DB_PASSWORD}
    ports:
      - "${DB_PORT_OUT}:3306"
    volumes:
      - ./data/mysql:/var/lib/mysql
    networks: [ ${NETWORK_NAME} ]

  cache:
    image: redis:7-alpine
    container_name: standard-notes-cache
    restart: unless-stopped
    command: redis-server --appendonly yes
    ports:
      - "${REDIS_PORT_OUT}:6379"
    volumes:
      - ./data/redis:/data
    networks: [ ${NETWORK_NAME} ]

  localstack:
    image: localstack/localstack:3.0
    container_name: standard-notes-localstack
    restart: unless-stopped
    environment:
      - SERVICES=sns,sqs
      - HOSTNAME_EXTERNAL=localstack
      - LS_LOG=warn
    ports:
      - "${LOCALSTACK_PORT_OUT}:${LOCALSTACK_PORT_OUT}"
    volumes:
      - ./localstack_bootstrap.sh:/etc/localstack/init/ready.d/localstack_bootstrap.sh
    networks: [ ${NETWORK_NAME} ]

  server:
    image: standardnotes/server
    container_name: standard-notes-server
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./logs:/var/lib/server/logs
      - ./uploads:/opt/server/packages/files/dist/uploads
    networks: [ ${NETWORK_NAME} ]
    # Ports are internal-only; Nginx proxies externally.
    # If you want to debug directly, uncomment:
    # ports:
    #   - "3000:3000"
    #   - "3125:3104"

  web:
    image: standardnotes/web
    container_name: standard-notes-web
    restart: unless-stopped
    networks: [ ${NETWORK_NAME} ]

  nginx:
    image: nginx:1.25-alpine
    container_name: standard-notes-proxy
    depends_on: [ web, server ]
    ports:
      - "${HTTPS_PORT_OUT}:3001"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
    networks: [ ${NETWORK_NAME} ]

networks:
  ${NETWORK_NAME}:
    name: ${NETWORK_NAME}
    driver: bridge
EOF
	print_success "docker-compose.yml written"

	# Pull & start
	print_info "Pulling images..."
	$DCMD pull
	print_success "Images pulled"

	print_info "Starting services..."
	$DCMD up -d
	print_info "Waiting ~45s for initialization..."
	sleep 45

	$DCMD ps
	echo
	print_success "Installed! Visit: https://${SERVER_IP}:${HTTPS_PORT_OUT}"
	echo "API:   https://${SERVER_IP}:${HTTPS_PORT_OUT}/api"
	echo "Files: https://${SERVER_IP}:${HTTPS_PORT_OUT}/files"
	echo
	print_info "If the browser complains, import ${PROJECT_DIR}/certs/server.crt into your OS trust store."
	test_api
}

# -----------------------------
# Manager actions
# -----------------------------
start_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR" && $DCMD up -d && print_success "Started"
}
stop_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR" && $DCMD down && print_success "Stopped"
}
restart_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR" && $DCMD restart && print_success "Restarted"
}
status_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR" && $DCMD ps
}

logs_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	if [ "${1:-}" != "" ]; then $DCMD logs -f "$1"; else $DCMD logs -f; fi
}

backup_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	mkdir -p backups
	local ts="backups/$(date +%Y%m%d_%H%M%S)"
	mkdir -p "$ts"
	source .env
	print_info "Dumping database..."
	$DCMD exec -T db mysqldump -u${DB_USERNAME} -p${DB_PASSWORD} ${DB_DATABASE} >"$ts/database.sql"
	cp -r ./uploads "$ts/uploads"
	cp .env "$ts/.env"
	print_success "Backup complete: $ts"
}

clean_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	echo "WARNING: Deletes ALL data under $PROJECT_DIR/data and uploads/logs!"
	read -p "Type 'yes' to continue: " y
	[ "$y" = "yes" ] || {
		echo "Cancelled."
		return 0
	}
	$DCMD down -v
	rm -rf data/mysql/* data/redis/* uploads/* logs/*
	print_success "Data cleaned."
}

reissue_cert() {
	require_root
	local SERVER_IP
	SERVER_IP=$(detect_ip)
	cd "$PROJECT_DIR"
	print_info "Reissuing self-signed cert for IP ${SERVER_IP}..."
	cat >nginx/openssl.cnf <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = v3_req
distinguished_name = dn
[ dn ]
CN = ${SERVER_IP}
O  = Self-Hosted Standard Notes
[ v3_req ]
subjectAltName = @alt_names
[ alt_names ]
IP.1 = ${SERVER_IP}
EOF
	openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
		-keyout certs/server.key \
		-out certs/server.crt \
		-config nginx/openssl.cnf >/dev/null 2>&1
	print_success "New cert generated at certs/server.crt"
	restart_stack
	echo "Trust the new certificate on your devices."
}

update_ip() {
	require_root
	local DCMD
	DCMD=$(compose_cmd)
	local NEW_IP
	NEW_IP=$(detect_ip)
	cd "$PROJECT_DIR"
	print_info "Updating configs for IP ${NEW_IP}..."

	# reissue cert
	reissue_cert

	# detect current external port from compose
	local CUR_PORT
	CUR_PORT=$(get_current_https_port)

	# rewrite .env URLs
	sed -i "s|PUBLIC_FILES_SERVER_URL=https://.*:.*\/files|PUBLIC_FILES_SERVER_URL=https://${NEW_IP}:${CUR_PORT}/files|" .env

	print_success "IP updated to ${NEW_IP}"
	$DCMD down
	$DCMD up -d
	sleep 8
	echo "Access: https://${NEW_IP}:${CUR_PORT}"
}

uninstall_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	echo "WARNING: This will STOP and REMOVE ${PROJECT_DIR} entirely."
	read -p "Type 'delete' to proceed: " conf
	[ "$conf" = "delete" ] || {
		echo "Cancelled."
		return 0
	}
	if [ -d "$PROJECT_DIR" ]; then
		cd "$PROJECT_DIR" && $DCMD down -v || true
		cd /root && rm -rf "$PROJECT_DIR"
	fi
	print_success "Uninstalled."
}

test_api() {
	echo
	print_info "Testing API (HTTPS)..."
	# Try a few common endpoints; succeed if any return <400
	local port
	port=$(get_current_https_port)
	local base="https://localhost:${port}"
	for p in "/api/version" "/api/status" "/api" "/"; do
		code=$(curl -sk -o /dev/null -w "%{http_code}" "${base}${p}" || true)
		if [ -n "$code" ] && [ "$code" -lt 400 ]; then
			print_success "API responded at ${p} (HTTP ${code})."
			return 0
		fi
	done
	print_info "API may still be warming up. Check logs with: $0 logs server"
}

# -----------------------------
# Menu / CLI
# -----------------------------
show_menu() {
	cat <<MENU

Standard Notes Manager
======================
1) Install
2) Start
3) Stop
4) Restart
5) Status
6) Logs (all)
7) Logs (choose service)
8) Backup
9) Clean data (DANGEROUS)
10) Update IP + reissue cert
11) Reissue cert only
12) Uninstall (DANGEROUS)
0) Exit

MENU
	read -p "Select an option: " choice
	case "$choice" in
	1) install_stack ;;
	2) start_stack ;;
	3) stop_stack ;;
	4) restart_stack ;;
	5) status_stack ;;
	6) logs_stack ;;
	7)
		read -p "Service name (db|cache|localstack|server|web|nginx): " svc
		logs_stack "$svc"
		;;
	8) backup_stack ;;
	9) clean_stack ;;
	10) update_ip ;;
	11) reissue_cert ;;
	12) uninstall_stack ;;
	0) exit 0 ;;
	*) echo "Unknown choice" ;;
	esac
}

usage() {
	cat <<USAGE
Usage: $0 <command>

Commands:
  install           Install the whole stack (prompts for external HTTPS port; default 4433 after 5s)
  start             Start containers
  stop              Stop containers
  restart           Restart containers
  status            Show container status
  logs [service]    Tail logs (optionally one service)
  backup            Dump DB + uploads + .env under ./backups/
  clean             Stop & delete MySQL/Redis/uploads/logs data (DANGEROUS)
  update-ip         Detect new IP, reissue cert, rewrite URLs, restart
  reissue-cert      Regenerate self-signed IP certificate and restart
  uninstall         Stop stack and remove ${PROJECT_DIR} (DANGEROUS)
  help              This help
(no args)           Interactive menu
USAGE
}

main() {
	case "${1:-}" in
	install) install_stack ;;
	start) start_stack ;;
	stop) stop_stack ;;
	restart) restart_stack ;;
	status) status_stack ;;
	logs)
		shift || true
		logs_stack "${1:-}"
		;;
	backup) backup_stack ;;
	clean) clean_stack ;;
	update-ip) update_ip ;;
	reissue-cert) reissue_cert ;;
	uninstall) uninstall_stack ;;
	help | -h | --help) usage ;;
	"") show_menu ;;
	*)
		usage
		exit 1
		;;
	esac
}

main "$@"
