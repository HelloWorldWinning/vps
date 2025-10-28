#!/usr/bin/env bash
# 4433.sh — Standard Notes all-in-one installer/manager (HTTPS @ https://HOST:PORT)
# Requires: Docker + (docker compose OR docker-compose)
# Stack: monolith server (API+Files), MySQL, Redis, LocalStack, optional Web, Nginx TLS
#
# What’s new in this build
# - **Interactive domain prompt (20s timeout):** asks for a domain at install; if blank/timeout, falls back to IP mode.
# - **COOKIE_DOMAIN when a domain is provided:** fixes the login refresh-cookie loop on modern SN server builds.
# - **IP-first default** preserved: if you skip domain input, it behaves like the old IP-only installer (may show auth loop in some browsers).
# - Reuse of existing features: origin reconfigure, cert SANs (IP + optional domain), one-click reissue, etc.
#
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
# Defaults
# -----------------------------
PROJECT_DIR="/root/standard-notes"
NETWORK_NAME="standard-notes"

API_PORT_IN=3000
FILES_PORT_IN=3104 # Internal files port (externally usually 3125)
WEB_PORT_IN=80

HTTPS_PORT_OUT=4433
DB_PORT_OUT=3306
REDIS_PORT_OUT=6379
LOCALSTACK_PORT_OUT=4566

DOMAIN_HOST="" # set by prompt_domain() if user enters a domain

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
require_root() {
	if [ "${EUID:-0}" -ne 0 ]; then
		print_error "Run as root (sudo)."
		exit 1
	fi
}
require_docker() {
	if ! command -v docker >/dev/null 2>&1; then
		print_error "Docker not found. Install Docker."
		exit 1
	fi
}

# -----------------------------
# IP / Host detection (PUBLIC-IP first)
# -----------------------------
detect_internal_ip() {
	local ips first
	ips="$(hostname -I 2>/dev/null || true)" || true
	set -- $ips
	first="${1:-}"
	if [ -z "$first" ]; then first="127.0.0.1"; fi
	echo "$first"
}

is_ip() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

_detect_from_cloud() {
	# Try common cloud metadata endpoints (fast timeouts)
	# GCP
	curl -fsS --max-time 1 -H "Metadata-Flavor: Google" \
		"http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || true
	# AWS
	curl -fsS --max-time 1 "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true
	# Azure
	curl -fsS --max-time 1 -H "Metadata:true" \
		"http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text" 2>/dev/null || true
}

_detect_from_dns() {
	# OpenDNS
	if command -v dig >/dev/null 2>&1; then
		dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || true
	fi
}

_detect_from_http() {
	# ipify / checkip (HTTP to avoid TLS issues on minimal hosts; fallback to HTTPS if needed)
	curl -fsS --max-time 2 http://api.ipify.org 2>/dev/null ||
		curl -fsS --max-time 2 http://checkip.amazonaws.com 2>/dev/null ||
		curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null ||
		curl -fsS --max-time 2 https://checkip.amazonaws.com 2>/dev/null || true
}

pick_first_ip() {
	awk 'BEGIN{FS="[[:space:]]+"} {for(i=1;i<=NF;i++){if($i ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/){print $i; exit}}}'
}

_detect_public_from_ifaces() {
	# Best-effort: look at non-RFC1918 addresses on interfaces
	if command -v ip >/dev/null 2>&1; then
		ip -br -4 addr show 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i~"[0-9]+/[0-9]+"){gsub("/.*","",$i); print $i}}}' |
			awk '!($0 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.|169\.254\.)/) {print; exit}' || true
	fi
}

detect_public_ip() {
	local ip
	# 1) Cloud metadata
	ip=$(_detect_from_cloud | pick_first_ip)
	if [ -n "${ip:-}" ] && is_ip "$ip"; then
		echo "$ip"
		return 0
	fi
	# 2) DNS
	ip=$(_detect_from_dns | pick_first_ip)
	if [ -n "${ip:-}" ] && is_ip "$ip"; then
		echo "$ip"
		return 0
	fi
	# 3) HTTP echo
	ip=$(_detect_from_http | pick_first_ip)
	if [ -n "${ip:-}" ] && is_ip "$ip"; then
		echo "$ip"
		return 0
	fi
	# 4) Non-RFC1918 iface address
	ip=$(_detect_public_from_ifaces)
	if [ -n "${ip:-}" ] && is_ip "$ip"; then
		echo "$ip"
		return 0
	fi
	# 5) Fall back to internal
	detect_internal_ip
}

# -----------------------------
# Existing compose introspection
# -----------------------------
get_current_https_port() {
	local compose="${PROJECT_DIR}/docker-compose.yml"
	local port=""
	if [ -f "$compose" ]; then
		port="$(grep -E '^\s*-\s*"?[0-9]+:3001"?' "$compose" 2>/dev/null | sed -E 's/.*"?([0-9]+):3001"?.*/\1/' | head -n1 || true)"
	fi
	if [ -n "$port" ]; then echo "$port"; else echo "$HTTPS_PORT_OUT"; fi
}

get_current_origin_host() {
	# Extract host used in PUBLIC_ORIGIN=https://HOST:PORT
	local compose="${PROJECT_DIR}/docker-compose.yml"
	[ -f "$compose" ] || {
		echo ""
		return 0
	}
	local line host
	line="$(grep -E 'PUBLIC_ORIGIN=https?://[^ "]+' "$compose" | head -n1 || true)"
	host="${line#*=https://}"
	host="${host%%:*}"
	echo "$host"
}

# -----------------------------
# Prompts
# -----------------------------
prompt_https_port() {
	local input=""
	echo -ne "${YELLOW}➜ External HTTPS port [default 4433] (5s to respond): ${NC}"
	if read -t 5 -r input; then :; else input=""; fi
	if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]; then
		HTTPS_PORT_OUT="$input"
	else
		HTTPS_PORT_OUT=4433
	fi
	print_info "Using external HTTPS port: ${HTTPS_PORT_OUT}"
}

is_domain_like() {
	# simple domain check: letters/digits/dots/dashes and at least one dot
	[[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]]
}

prompt_domain() {
	local input=""
	echo -ne "${YELLOW}➜ Optional domain (e.g., notes.example.com) [20s to respond, blank = use IP]: ${NC}"
	if read -t 20 -r input; then :; else input=""; fi
	if [ -n "$input" ]; then
		if is_domain_like "$input"; then
			DOMAIN_HOST="$input"
			print_info "Will use domain: ${DOMAIN_HOST} (COOKIE_DOMAIN will be set)"
		else
			print_error "Invalid domain syntax. Falling back to IP mode."
			DOMAIN_HOST=""
		fi
	else
		print_info "No domain provided; using IP mode (may cause auth loop in some browsers)."
	fi
}

# -----------------------------
# Core write helpers
# -----------------------------
write_env() {
	local host="$1"
	shift
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

# Public files URL via Nginx on https://${host}:${HTTPS_PORT_OUT}
PUBLIC_FILES_SERVER_URL=https://${host}:${HTTPS_PORT_OUT}/files

# Explicitly allow registrations
AUTH_SERVER_DISABLE_USER_REGISTRATION=false
EOF
}

write_nginx_conf() {
	mkdir -p nginx
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
    listen 3001 ssl;
    http2 on;
    server_name _;

    ssl_certificate     /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;

    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy no-referrer;
    client_max_body_size 50m;

    # Web app on /
    location / {
      proxy_pass http://web:80;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_http_version 1.1;
      proxy_set_header Upgrade           $http_upgrade;
      proxy_set_header Connection        $connection_upgrade;
      proxy_read_timeout 300s;
    }

    # Sync API on /api -> server:3000
    location ^~ /api/ {
      rewrite ^/api/?(.*)$ /$1 break;
      proxy_pass http://server:3000;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_http_version 1.1;
      proxy_set_header Upgrade           $http_upgrade;
      proxy_set_header Connection        $connection_upgrade;
      proxy_read_timeout 300s;
    }

    # Files API on /files -> server:3104 (exposed externally as /files)
    location ^~ /files/ {
      rewrite ^/files/?(.*)$ /$1 break;
      proxy_pass http://server:3104;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_cache off;
      proxy_read_timeout 300s;
    }
  }
}
EOF
}

write_localstack_bootstrap() {
	cat >localstack_bootstrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOCALSTACK_HOST=localhost
AWS_REGION=us-east-1
LOCALSTACK_DUMMY_ID=000000000000
get_all_queues(){ awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sqs list-queues; }
create_queue(){   local n=$1; awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sqs create-queue --queue-name ${n}; }
get_all_topics(){ awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns list-topics; }
create_topic(){   local n=$1; awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns create-topic --name ${n}; }
link_queue_and_topic(){ local t=$1 q=$2; awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns subscribe --topic-arn ${t} --protocol sqs --notification-endpoint ${q}; }
get_queue_arn_from_name(){ local n=$1; echo "arn:aws:sns:${AWS_REGION}:${LOCALSTACK_DUMMY_ID}:$n"; }
get_topic_arn_from_name(){ local n=$1; echo "arn:aws:sns:${AWS_REGION}:${LOCALSTACK_DUMMY_ID}:$n"; }

PAYMENTS_TOPIC_NAME="payments-local-topic";             create_topic ${PAYMENTS_TOPIC_NAME}; PAYMENTS_TOPIC_ARN=$(get_topic_arn_from_name $PAYMENTS_TOPIC_NAME)
SYNCING_SERVER_TOPIC_NAME="syncing-server-local-topic"; create_topic ${SYNCING_SERVER_TOPIC_NAME}; SYNCING_SERVER_TOPIC_ARN=$(get_topic_arn_from_name $SYNCING_SERVER_TOPIC_NAME)
AUTH_TOPIC_NAME="auth-local-topic";                     create_topic ${AUTH_TOPIC_NAME}; AUTH_TOPIC_ARN=$(get_topic_arn_from_name $AUTH_TOPIC_NAME)
FILES_TOPIC_NAME="files-local-topic";                   create_topic ${FILES_TOPIC_NAME}; FILES_TOPIC_ARN=$(get_topic_arn_from_name $FILES_TOPIC_NAME)
ANALYTICS_TOPIC_NAME="analytics-local-topic";           create_topic ${ANALYTICS_TOPIC_NAME}; ANALYTICS_TOPIC_ARN=$(get_topic_arn_from_name $ANALYTICS_TOPIC_NAME)
REVISIONS_TOPIC_NAME="revisions-server-local-topic";    create_topic ${REVISIONS_TOPIC_NAME}; REVISIONS_TOPIC_ARN=$(get_topic_arn_from_name $REVISIONS_TOPIC_NAME)
SCHEDULER_TOPIC_NAME="scheduler-local-topic";           create_topic ${SCHEDULER_TOPIC_NAME}; SCHEDULER_TOPIC_ARN=$(get_topic_arn_from_name $SCHEDULER_TOPIC_NAME)

QUEUE_NAME="analytics-local-queue"; create_queue ${QUEUE_NAME}; ANALYTICS_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $PAYMENTS_TOPIC_ARN $ANALYTICS_QUEUE_ARN
QUEUE_NAME="auth-local-queue";      create_queue ${QUEUE_NAME}; AUTH_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $PAYMENTS_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $AUTH_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $FILES_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $REVISIONS_TOPIC_ARN $AUTH_QUEUE_ARN
QUEUE_NAME="files-local-queue";     create_queue ${QUEUE_NAME}; FILES_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $AUTH_TOPIC_ARN $FILES_QUEUE_ARN; link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $FILES_QUEUE_ARN
QUEUE_NAME="syncing-server-local-queue"; create_queue ${QUEUE_NAME}; SYNCING_SERVER_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $SYNCING_SERVER_QUEUE_ARN; link_queue_and_topic $FILES_TOPIC_ARN $SYNCING_SERVER_QUEUE_ARN; link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $AUTH_QUEUE_ARN; link_queue_and_topic $AUTH_TOPIC_ARN $SYNCING_SERVER_QUEUE_ARN
QUEUE_NAME="revisions-server-local-queue"; create_queue ${QUEUE_NAME}; REVISIONS_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME); link_queue_and_topic $SYNCING_SERVER_TOPIC_ARN $REVISIONS_QUEUE_ARN; link_queue_and_topic $REVISIONS_TOPIC_ARN $REVISIONS_QUEUE_ARN
QUEUE_NAME="scheduler-local-queue"; create_queue ${QUEUE_NAME}; SCHEDULER_QUEUE_ARN=$(get_queue_arn_from_name $QUEUE_NAME)
echo "all topics are:"; get_all_topics
echo "all queues are:"; get_all_queues
EOF
	chmod +x localstack_bootstrap.sh
}

write_web_entry() {
	mkdir -p web-entry
	cat >web-entry/50-set-sync-server.sh <<'EOF'
#!/usr/bin/env sh
set -eu
HTML_DIR="/usr/share/nginx/html"
TARGET="${DEFAULT_SYNC_SERVER:-${NEXT_PUBLIC_DEFAULT_SYNC_SERVER:-${SF_DEFAULT_SERVER:-${SF_NEXT_VERSION_SERVER:-}}}}"
if [ -z "${TARGET:-}" ] && [ -n "${PUBLIC_ORIGIN:-}" ]; then
  TARGET="${PUBLIC_ORIGIN%/}/api"
fi
if [ -z "${TARGET:-}" ]; then
  echo "[web-init] No DEFAULT_SYNC_SERVER provided; leaving app defaults."
  exit 0
fi
echo "[web-init] Forcing DEFAULT_SYNC_SERVER to ${TARGET}"
for f in "${HTML_DIR}"/*.js; do
  [ -f "$f" ] || continue
  sed -i "s#https://api\\.standardnotes\\.com#${TARGET}#g" "$f" || true
  sed -i "s#https://sync\\.standardnotes\\.org#${TARGET}#g" "$f" || true
  sed -i "s#https://sync\\.standardnotes\\.com#${TARGET}#g" "$f" || true
  # also patch files host if present (optional)
  if [ -n "${PUBLIC_ORIGIN:-}" ]; then
    FILES_HOST="${PUBLIC_ORIGIN%/}/files"
    sed -i "s#https://files\\.standardnotes\\.com#${FILES_HOST}#g" "$f" || true
  fi
done
EOF
	chmod +x web-entry/50-set-sync-server.sh
}

write_compose() {
	local host="$1" # domain or IP for PUBLIC_ORIGIN
	local domain="${2:-}"
	mkdir -p data/mysql data/redis uploads logs nginx certs
	local cookie_line=""
	if [ -n "$domain" ]; then
		cookie_line="      - COOKIE_DOMAIN=${domain}"
	fi
	cat >docker-compose.yml <<EOF
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
    environment:
      - AUTH_SERVER_DISABLE_USER_REGISTRATION=\${AUTH_SERVER_DISABLE_USER_REGISTRATION}
${cookie_line}
    volumes:
      - ./logs:/var/lib/server/logs
      - ./uploads:/opt/server/packages/files/dist/uploads
    networks: [ ${NETWORK_NAME} ]
    depends_on:
      - db
      - cache
      - localstack

  web:
    image: standardnotes/web
    container_name: standard-notes-web
    restart: unless-stopped
    environment:
      - PUBLIC_ORIGIN=https://${host}:${HTTPS_PORT_OUT}
      - DEFAULT_SYNC_SERVER=https://${host}:${HTTPS_PORT_OUT}/api
      - NEXT_PUBLIC_DEFAULT_SYNC_SERVER=https://${host}:${HTTPS_PORT_OUT}/api
      - SF_DEFAULT_SERVER=https://${host}:${HTTPS_PORT_OUT}/api
      - SF_NEXT_VERSION_SERVER=https://${host}:${HTTPS_PORT_OUT}/api
    volumes:
      - ./web-entry:/docker-entrypoint.d
    networks: [ ${NETWORK_NAME} ]
    depends_on:
      - server

  nginx:
    image: nginx:1.25-alpine
    container_name: standard-notes-proxy
    depends_on:
      - web
      - server
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
}

# -----------------------------
# TLS cert (SANs: localhost + public IP + optional domain)
# -----------------------------
make_cert() {
	local ip="$1"
	shift
	local domain="${1:-}"
	shift || true
	cat >nginx/openssl.cnf <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = v3_req
distinguished_name = dn
[ dn ]
CN = ${domain:-${ip}}
O  = Self-Hosted Standard Notes
[ v3_req ]
subjectAltName = @alt_names
[ alt_names ]
IP.1 = ${ip}
DNS.1 = localhost
EOF
	if [ -n "${domain}" ]; then
		# Insert DNS.2 only if domain provided
		sed -i '/DNS.1 = localhost/a DNS.2 = '"${domain}" nginx/openssl.cnf
	fi
	openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
		-keyout certs/server.key \
		-out certs/server.crt \
		-config nginx/openssl.cnf >/dev/null 2>&1
}

# -----------------------------
# Install flow
# -----------------------------
install_stack() {
	require_root
	require_docker
	local DCMD
	DCMD=$(compose_cmd)

	# Prefer PUBLIC IP
	local PUB_IP
	PUB_IP=$(detect_public_ip)

	prompt_https_port
	prompt_domain

	local HOST_CHOICE
	if [ -n "${DOMAIN_HOST}" ]; then
		HOST_CHOICE="${DOMAIN_HOST}"
	else
		HOST_CHOICE="${PUB_IP}"
	fi

	print_info "Setting up Standard Notes at ${PROJECT_DIR} (host: ${HOST_CHOICE})"

	if [ -d "$PROJECT_DIR" ]; then
		print_info "Existing install found. Stopping & removing..."
		(cd "$PROJECT_DIR" && $DCMD down -v || true)
		rm -rf "$PROJECT_DIR"
	fi

	mkdir -p "$PROJECT_DIR"/{data/mysql,data/redis,uploads,logs,nginx,certs,web-entry}
	cd "$PROJECT_DIR"
	print_success "Directory structure created"

	print_info "Generating secrets..."
	AUTH_JWT_SECRET=$(openssl rand -hex 32)
	AUTH_SERVER_ENCRYPTION_SERVER_KEY=$(openssl rand -hex 32)
	VALET_TOKEN_SECRET=$(openssl rand -hex 32)
	DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
	print_success "Secrets generated"

	print_info "Writing .env..."
	write_env "$HOST_CHOICE"
	print_success ".env written"

	print_info "Generating self-signed TLS cert (SANs: ${PUB_IP}, localhost${DOMAIN_HOST:+, ${DOMAIN_HOST}})..."
	write_nginx_conf
	make_cert "$PUB_IP" "${DOMAIN_HOST:-}"
	print_success "Cert created at certs/server.crt (import it into your OS trust store)"

	print_info "Adding web runtime entry to force local sync server..."
	write_web_entry
	print_success "Web runtime entry added"

	print_info "Writing docker-compose.yml..."
	write_compose "$HOST_CHOICE" "${DOMAIN_HOST:-}"
	print_success "docker-compose.yml written"

	print_info "Writing LocalStack bootstrap..."
	write_localstack_bootstrap
	print_success "LocalStack bootstrap created"

	print_info "Pulling images..."
	$DCMD pull
	print_success "Images pulled"

	print_info "Starting services..."
	$DCMD up -d

	print_info "Waiting for API to respond through Nginx (treating 2xx–4xx as ready; ignoring 5xx/502)..."
	wait_for_api_ready "https://localhost:$(get_current_https_port)/api" 180 || true

	$DCMD ps
	echo
	print_success "Installed! Visit: https://${HOST_CHOICE}:${HTTPS_PORT_OUT}"
	echo "API:   https://${HOST_CHOICE}:${HTTPS_PORT_OUT}/api"
	echo "Files: https://${HOST_CHOICE}:${HTTPS_PORT_OUT}/files"
	echo
	print_info "If the browser complains, import ${PROJECT_DIR}/certs/server.crt into your OS trust store."
	test_api
}

# -----------------------------
# Helper: API readiness (accept 2xx–4xx; reject 5xx/000)
# -----------------------------
wait_for_api_ready() {
	local url="${1:?}"
	local timeout="${2:-120}"
	local start now code
	start=$(date +%s)
	while true; do
		code=$(curl -sk -o /dev/null -w "%{http_code}" "$url" || true)
		if [ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -ge 200 ] && [ "$code" -lt 500 ]; then
			print_success "API responded at $url (HTTP ${code})."
			return 0
		fi
		now=$(date +%s)
		if [ $((now - start)) -ge "$timeout" ]; then
			print_info "API not ready after ${timeout}s; continuing (you can check logs)."
			return 1
		fi
		sleep 3
	done
}

# -----------------------------
# Manager actions
# -----------------------------
start_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	$DCMD up -d
	print_success "Started"
}
stop_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	$DCMD down
	print_success "Stopped"
}
restart_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	$DCMD restart
	print_success "Restarted"
}
status_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	$DCMD ps
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
	# shellcheck disable=SC1091
	. ./.env
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
	if [ "$y" != "yes" ]; then
		echo "Cancelled."
		return 0
	fi
	$DCMD down -v
	rm -rf data/mysql/* data/redis/* uploads/* logs/*
	print_success "Data cleaned."
}

reissue_cert() {
	require_root
	cd "$PROJECT_DIR"
	local domain="${1:-}"
	shift || true
	local PUB_IP
	PUB_IP=$(detect_public_ip)
	print_info "Reissuing self-signed cert for IP ${PUB_IP}${domain:+ and domain ${domain}}..."
	make_cert "$PUB_IP" "${domain:-}"
	print_success "New cert generated at certs/server.crt"
	restart_stack
	echo "Trust the new certificate on your devices."
}

# Update origin to PUBLIC IP (default) or keep domain if configured
update_ip() {
	require_root
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	local NEW_IP
	NEW_IP=$(detect_public_ip)
	local CUR_PORT
	CUR_PORT=$(get_current_https_port)
	local CUR_HOST
	CUR_HOST=$(get_current_origin_host)
	print_info "Detected public IP: ${NEW_IP}"

	# If CUR_HOST is a domain (contains letters), keep domain for origin but include NEW_IP in cert SANs
	if echo "$CUR_HOST" | grep -Eq '[A-Za-z]'; then
		print_info "Compose currently uses domain '${CUR_HOST}'. Keeping it and updating cert SANs with IP ${NEW_IP}."
		reissue_cert "${CUR_HOST}"
		# Ensure .env PUBLIC_FILES_SERVER_URL continues to use the domain
		sed -i "s|^PUBLIC_FILES_SERVER_URL=.*|PUBLIC_FILES_SERVER_URL=https://${CUR_HOST}:${CUR_PORT}/files|" .env
		$DCMD down
		$DCMD up -d
		sleep 8
		echo "Access (domain): https://${CUR_HOST}:${CUR_PORT}"
		echo "Access (IP):     https://${NEW_IP}:${CUR_PORT}"
		return 0
	fi

	print_info "Updating configs to use IP ${NEW_IP}..."
	# Update .env
	sed -i "s|^PUBLIC_FILES_SERVER_URL=.*|PUBLIC_FILES_SERVER_URL=https://${NEW_IP}:${CUR_PORT}/files|" .env
	# Update docker-compose.yml web envs
	sed -i -E "s#(PUBLIC_ORIGIN=)https://[^:]+:[0-9]+#\1https://${NEW_IP}:${CUR_PORT}#g" docker-compose.yml
	sed -i -E "s#(DEFAULT_SYNC_SERVER=)https://[^:]+:[0-9]+/api#\1https://${NEW_IP}:${CUR_PORT}/api#g" docker-compose.yml
	sed -i -E "s#(NEXT_PUBLIC_DEFAULT_SYNC_SERVER=)https://[^:]+:[0-9]+/api#\1https://${NEW_IP}:${CUR_PORT}/api#g" docker-compose.yml
	sed -i -E "s#(SF_DEFAULT_SERVER=)https://[^:]+:[0-9]+/api#\1https://${NEW_IP}:${CUR_PORT}/api#g" docker-compose.yml
	sed -i -E "s#(SF_NEXT_VERSION_SERVER=)https://[^:]+:[0-9]+/api#\1https://${NEW_IP}:${CUR_PORT}/api#g" docker-compose.yml

	# Remove COOKIE_DOMAIN in IP mode (if present)
	sed -i '/COOKIE_DOMAIN=/d' docker-compose.yml || true

	# Reissue cert for new IP
	make_cert "$NEW_IP" ""
	print_success "IP updated to ${NEW_IP}"
	$DCMD down
	$DCMD up -d
	sleep 8
	echo "Access: https://${NEW_IP}:${CUR_PORT}"
}

# Absorb fix.sh: set origin/port to a DOMAIN (optionally specify IP to include in cert)
configure_origin() {
	require_root
	local host="" ip="" port="$(get_current_https_port)"
	while [ $# -gt 0 ]; do
		case "$1" in
		--host)
			host="${2:-}"
			shift 2
			;;
		--ip)
			ip="${2:-}"
			shift 2
			;;
		--port)
			port="${2:-}"
			shift 2
			;;
		*)
			print_error "Unknown option: $1"
			exit 1
			;;
		esac
	done
	if [ -z "$host" ]; then
		print_error "--host is required (e.g., notes.example.com)"
		exit 1
	fi
	if [ -z "$ip" ]; then ip=$(detect_public_ip); fi
	if ! is_ip "$ip"; then
		print_error "Invalid IP to embed in cert SANs: '$ip'"
		exit 1
	fi
	local DCMD
	DCMD=$(compose_cmd)
	cd "$PROJECT_DIR"
	print_info "Stopping stack..."
	$DCMD down || true
	print_info "Updating .env/.yml to host=${host}, port=${port}"
	sed -i "s|^PUBLIC_FILES_SERVER_URL=.*|PUBLIC_FILES_SERVER_URL=https://${host}:${port}/files|" .env
	sed -i -E "s#(PUBLIC_ORIGIN=)https://[^\"]+#\1https://${host}:${port}#" docker-compose.yml
	sed -i -E "s#(DEFAULT_SYNC_SERVER=)https://[^\"]+/api#\1https://${host}:${port}/api#" docker-compose.yml
	sed -i -E "s#(NEXT_PUBLIC_DEFAULT_SYNC_SERVER=)https://[^\"]+/api#\1https://${host}:${port}/api#" docker-compose.yml
	sed -i -E "s#(SF_DEFAULT_SERVER=)https://[^\"]+/api#\1https://${host}:${port}/api#" docker-compose.yml
	sed -i -E "s#(SF_NEXT_VERSION_SERVER=)https://[^\"]+/api#\1https://${host}:${port}/api#" docker-compose.yml
	# Ensure COOKIE_DOMAIN is set for domain mode
	sed -i '/COOKIE_DOMAIN=/d' docker-compose.yml || true
	sed -i '/AUTH_SERVER_DISABLE_USER_REGISTRATION=/a\      - COOKIE_DOMAIN='"${host}" docker-compose.yml

	print_info "Regenerating self-signed cert with SANs: IP=${ip}, DNS=${host}"
	make_cert "$ip" "$host"
	print_info "Starting stack..."
	$DCMD up -d
	echo "Access: https://${host}:${port} (DNS)"
	echo "Access: https://${ip}:${port}   (IP)"
}

# -----------------------------
# Uninstall
# -----------------------------
uninstall_stack() {
	local DCMD
	DCMD=$(compose_cmd)
	echo "WARNING: This will STOP and REMOVE ${PROJECT_DIR} entirely."
	read -p "Type 'delete' to proceed: " conf
	if [ "$conf" != "delete" ]; then
		echo "Cancelled."
		return 0
	fi
	if [ -d "$PROJECT_DIR" ]; then
		(cd "$PROJECT_DIR" && $DCMD down -v || true)
		(cd /root && rm -rf "$PROJECT_DIR")
	fi
	print_success "Uninstalled."
}

# -----------------------------
# API probe (lightweight built-in)
# -----------------------------
test_api() {
	echo
	print_info "Testing via Nginx proxy (HTTPS, self-signed; -k used)..."
	local port base code
	port=$(get_current_https_port)
	base="https://localhost:${port}"
	for p in "/api" "/files" "/"; do
		code=$(curl -sk -o /dev/null -w "%{http_code}" "${base}${p}" || true)
		if [ -n "$code" ] && [ "$code" != "000" ]; then
			print_success "Proxy responded at ${p} (HTTP ${code})."
		else
			print_error "No response at ${p}."
		fi
	done
}

# -----------------------------
# Menu / CLI
# -----------------------------
show_menu() {
	cat <<MENU

Standard Notes Manager (IP-first with optional domain)
=====================================================
1) Install (prompts for domain; defaults to IP)
2) Start
3) Stop
4) Restart
5) Status
6) Logs (all)
7) Logs (choose service)
8) Backup
9) Clean data (DANGEROUS)
10) Update IP + reissue cert (keep domain if configured)
11) Reissue cert only (auto IP; add domain if provided)
12) Uninstall (DANGEROUS)
13) Configure origin (domain)  — optional advanced tool
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
	11)
		read -p "Optional domain for SAN (blank to skip): " d
		reissue_cert "${d:-}"
		;;
	12) uninstall_stack ;;
	13)
		read -p "Domain (e.g., notes.example.com): " dom
		read -p "Port [default $(get_current_https_port)]: " prt
		prt="${prt:-$(get_current_https_port)}"
		configure_origin --host "$dom" --port "$prt"
		;;
	0) exit 0 ;;
	*) echo "Unknown choice" ;;
	esac
}

usage() {
	cat <<USAGE
Usage: $0 <command> [options]

Commands:
  install                 Install the whole stack (prompts for domain; defaults to IP; prompts for HTTPS port)
  start                   Start containers
  stop                    Stop containers
  restart                 Restart containers
  status                  Show container status
  logs [service]          Tail logs (optionally one service)
  backup                  Dump DB + uploads + .env under ./backups/
  clean                   Stop & delete MySQL/Redis/uploads/logs data (DANGEROUS)
  update-ip               Detect public IP, update configs & cert; keep domain if configured
  reissue-cert [domain]   Regenerate self-signed certificate (SANs: public IP [+ domain]) and restart
  set-origin --host H [--ip X.X.X.X] [--port N]
                          Point origin to domain H, rewrite envs, regenerate cert incl. IP+DNS (advanced; optional)
  test-api                Quick readiness check through https://localhost:PORT
  uninstall               Stop stack and remove ${PROJECT_DIR} (DANGEROUS)
  help                    This help
(no args)                 Interactive menu
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
	reissue-cert)
		shift || true
		reissue_cert "${1:-}"
		;;
	set-origin)
		shift || true
		configure_origin "$@"
		;;
	test-api) test_api ;;
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
