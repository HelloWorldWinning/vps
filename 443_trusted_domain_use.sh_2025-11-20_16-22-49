#!/usr/bin/env bash
# 443_trusted_domain.sh — Standard Notes all-in-one installer/manager with trusted TLS (Let's Encrypt via acme.sh)
# Requires: root, Docker, Docker Compose, open TCP/80 on the host (HTTP-01), outbound HTTPS
# Stack: Standard Notes server (API+Files), MySQL, Redis, LocalStack, Web, Nginx (TLS @ 443)
#
# Key points
# - Domain is REQUIRED (trusted certs need a FQDN + public DNS).
# - Default external HTTPS port is 443.
# - Uses acme.sh (Let’s Encrypt) with HTTP-01 on port 80 (served from nginx webroot).
# - No self-signed certs; certs auto-renew and nginx auto-reloads on renew.
# - Nginx: fixed HTTP/2 deprecation (use `http2 on;`), plus optional hardening to drop common scanner noise.
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
FILES_PORT_IN=3104
WEB_PORT_IN=80

HTTPS_PORT_OUT=443 # default 443
HTTP_PORT_OUT=80
DB_PORT_OUT=3306
REDIS_PORT_OUT=6379
LOCALSTACK_PORT_OUT=4566

DOMAIN_HOST="" # required
ACME_EMAIL=""  # optional; for LE notices

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

port_free() {
	local port="$1"
	# returns 0 if free
	if ss -lnt "( sport = :$port )" | awk 'NR>1{exit 1}'; then
		return 0
	fi
	return 1
}

# -----------------------------
# Prompts
# -----------------------------
prompt_https_port() {
	local input=""
	echo -ne "${YELLOW}➜ External HTTPS port [default 443] (5s to respond): ${NC}"
	if read -t 5 -r input; then :; else input=""; fi
	if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]; then
		HTTPS_PORT_OUT="$input"
	else
		HTTPS_PORT_OUT=443
	fi
	print_info "Using external HTTPS port: ${HTTPS_PORT_OUT}"
}

is_domain_like() {
	[[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]]
}

prompt_domain_required() {
	local input=""
	echo -ne "${YELLOW}➜ Domain (e.g., notes.example.com) [REQUIRED]: ${NC}"
	if ! read -r input || [ -z "$input" ]; then
		print_error "Domain is required for trusted TLS. Aborting."
		exit 1
	fi
	if ! is_domain_like "$input"; then
		print_error "Invalid domain syntax."
		exit 1
	fi
	DOMAIN_HOST="$input"
	print_info "Will use domain: ${DOMAIN_HOST} (COOKIE_DOMAIN will be set)"
}

prompt_acme_email_optional() {
	local input=""
	echo -ne "${YELLOW}➜ Email for Let's Encrypt notices (optional, Enter to skip): ${NC}"
	if read -r input && [ -n "$input" ]; then
		ACME_EMAIL="$input"
		print_info "ACME contact email set: ${ACME_EMAIL}"
	else
		ACME_EMAIL=""
		print_info "No ACME email provided."
	fi
}

# -----------------------------
# Core write helpers
# -----------------------------
write_env() {
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

# Public files URL via Nginx on https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}
PUBLIC_FILES_SERVER_URL=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/files

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

  # ---------- Hardening / noise reduction ----------
  # Basic rate limit (per IP)
  limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=10r/s;

  # Fast-drop common scanner paths
  map $request_uri $deny_scan {
    default 0;
    ~^/(\.env|\.git|\.hg|\.svn|server-status|info\.php) 1;
    ~^/telescope/ 1;
    ~^/wp- 1;
    ~^/\?_?rest_route= 1;
    ~^/v2/_catalog 1;
  }

  map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
  }

  # ---------- Port 80 server: ACME + redirect ----------
  server {
    listen 80;
    server_name _;

    # ACME challenge directory (shared with acme.sh webroot)
    location ^~ /.well-known/acme-challenge/ {
      alias /var/www/acme/.well-known/acme-challenge/;
      default_type "text/plain";
      allow all;
    }

    location / {
      return 301 https://$host$request_uri;
    }
  }

  # ---------- Port 443 server (internal 3001) ----------
  server {
    listen 3001 ssl;   # fixed: no 'http2' here
    http2 on;          # fixed: modern directive
    server_name _;

    ssl_certificate     /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;

    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy no-referrer;
    client_max_body_size 50m;

    # Apply rate limit globally in this server
    limit_req zone=req_limit_per_ip burst=20 nodelay;

    # Drop common scanner paths fast
    if ($deny_scan) { return 444; }

    # Do not serve dotfiles (defense-in-depth; still allow /.well-known)
    location ~ /\.(?!well-known) {
      return 444;
    }

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

    # Files API on /files -> server:3104
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
  if [ -n "${PUBLIC_ORIGIN:-}" ]; then
    FILES_HOST="${PUBLIC_ORIGIN%/}/files"
    sed -i "s#https://files\\.standardnotes\\.com#${FILES_HOST}#g" "$f" || true
  fi
done
EOF
	chmod +x web-entry/50-set-sync-server.sh
}

write_compose() {
	mkdir -p data/mysql data/redis uploads logs nginx certs nginx/acme
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
      - COOKIE_DOMAIN=${DOMAIN_HOST}
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
      - PUBLIC_ORIGIN=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}
      - DEFAULT_SYNC_SERVER=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api
      - NEXT_PUBLIC_DEFAULT_SYNC_SERVER=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api
      - SF_DEFAULT_SERVER=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api
      - SF_NEXT_VERSION_SERVER=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api
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
      - "${HTTP_PORT_OUT}:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
      - ./nginx/acme:/var/www/acme:ro
    networks: [ ${NETWORK_NAME} ]

networks:
  ${NETWORK_NAME}:
    name: ${NETWORK_NAME}
    driver: bridge
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

# -----------------------------
# ACME (Let's Encrypt via acme.sh)
# -----------------------------
ensure_acme() {
	if [ -x "/root/.acme.sh/acme.sh" ]; then
		print_success "acme.sh already installed."
		return 0
	fi
	print_info "Installing acme.sh..."
	curl -fsSL https://get.acme.sh | sh -s email="${ACME_EMAIL:-}" >/dev/null 2>&1 || {
		print_error "Failed to install acme.sh"
		exit 1
	}
	print_success "acme.sh installed."
}

acme_issue_cert() {
	local acme="/root/.acme.sh/acme.sh"
	"$acme" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

	mkdir -p "${PROJECT_DIR}/nginx/acme/.well-known/acme-challenge" "${PROJECT_DIR}/certs"
	print_info "Issuing certificate for ${DOMAIN_HOST} via HTTP-01 (webroot)..."
	"$acme" --issue \
		-d "${DOMAIN_HOST}" \
		--webroot "${PROJECT_DIR}/nginx/acme" \
		--key-file "${PROJECT_DIR}/certs/server.key" \
		--fullchain-file "${PROJECT_DIR}/certs/server.crt" \
		--reloadcmd "cd ${PROJECT_DIR} && $(compose_cmd) exec -T nginx nginx -s reload" \
		--force >/dev/null 2>&1 || {
		print_error "Let's Encrypt issuance failed. Ensure the domain resolves to this server and port 80 is open."
		exit 1
	}
	print_success "Certificate issued for ${DOMAIN_HOST}."
	print_info "Files: ${PROJECT_DIR}/certs/server.crt and server.key"
}

# -----------------------------
# API readiness probe
# -----------------------------
wait_for_api_ready() {
	local url="${1:?}"
	local timeout="${2:-180}"
	local start code now
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
install_stack() {
	require_root
	require_docker

	prompt_https_port
	prompt_domain_required
	prompt_acme_email_optional

	if ! port_free "${HTTPS_PORT_OUT}"; then
		print_error "Port ${HTTPS_PORT_OUT} is already in use."
		exit 1
	fi
	if ! port_free "${HTTP_PORT_OUT}"; then
		print_error "Port ${HTTP_PORT_OUT} is already in use. Stop whatever listens on :80 so nginx can serve ACME challenge."
		exit 1
	fi

	local DCMD
	DCMD=$(compose_cmd)

	if [ -d "$PROJECT_DIR" ]; then
		print_info "Existing install found. Stopping & removing..."
		(cd "$PROJECT_DIR" && $DCMD down -v || true)
		rm -rf "$PROJECT_DIR"
	fi

	mkdir -p "$PROJECT_DIR"/{data/mysql,data/redis,uploads,logs,nginx,certs,web-entry,backups,nginx/acme}
	cd "$PROJECT_DIR"
	print_success "Directory structure created"

	print_info "Generating secrets..."
	AUTH_JWT_SECRET=$(openssl rand -hex 32)
	AUTH_SERVER_ENCRYPTION_SERVER_KEY=$(openssl rand -hex 32)
	VALET_TOKEN_SECRET=$(openssl rand -hex 32)
	DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
	print_success "Secrets generated"

	print_info "Writing .env..."
	write_env
	print_success ".env written"

	print_info "Writing nginx.conf..."
	write_nginx_conf
	print_success "nginx.conf written"

	print_info "Adding web runtime entry to force local sync server..."
	write_web_entry
	print_success "Web runtime entry added"

	print_info "Writing docker-compose.yml..."
	write_compose
	print_success "docker-compose.yml written"

	print_info "Writing LocalStack bootstrap..."
	write_localstack_bootstrap
	print_success "LocalStack bootstrap created"

	print_info "Creating temporary placeholder key/cert so nginx can start..."
	mkdir -p certs
	: >certs/server.key
	: >certs/server.crt

	print_info "Pulling images..."
	$DCMD pull
	print_success "Images pulled"

	print_info "Starting db/cache/localstack/server/web..."
	$DCMD up -d db cache localstack server web

	# Boot nginx on :80 to serve ACME webroot; TLS will reload after issuance
	# Create a tiny self-signed just to let nginx parse PEMs (will be replaced immediately)
	if [ ! -s certs/server.key ] || [ ! -s certs/server.crt ]; then
		openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
			-subj "/CN=bootstrap.invalid" \
			-keyout certs/server.key \
			-out certs/server.crt >/dev/null 2>&1 || true
	fi
	print_info "Starting nginx (to serve ACME challenge on :80)..."
	$DCMD up -d nginx

	ensure_acme
	acme_issue_cert

	print_info "Reloading nginx with trusted cert..."
	$DCMD exec -T nginx nginx -s reload || true

	print_info "Waiting for API to respond through Nginx (2xx–4xx=ready)..."
	wait_for_api_ready "https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api" 180 || true

	$DCMD ps
	echo
	print_success "Installed! Visit: https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}"
	echo "API:   https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api"
	echo "Files: https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/files"
	echo
	print_info "acme.sh installed a cron for renewals. On renew, nginx auto-reloads via reloadcmd."
}

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
	if [ -z "${1:-}" ]; then
		print_error "Usage: $0 reissue-cert <domain>"
		exit 1
	fi
	local new_domain="$1"
	DOMAIN_HOST="$new_domain"

	# Update compose/web envs and COOKIE_DOMAIN
	sed -i -E "s#(PUBLIC_ORIGIN=)https://[^\"]+#\1https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}#" docker-compose.yml
	sed -i -E "s#(DEFAULT_SYNC_SERVER=)https://[^\"]+/api#\1https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api#" docker-compose.yml
	sed -i -E "s#(NEXT_PUBLIC_DEFAULT_SYNC_SERVER=)https://[^\"]+/api#\1https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api#" docker-compose.yml
	sed -i -E "s#(SF_DEFAULT_SERVER=)https://[^\"]+/api#\1https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api#" docker-compose.yml
	sed -i -E "s#(SF_NEXT_VERSION_SERVER=)https://[^\"]+/api#\1https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/api#" docker-compose.yml
	sed -i "s|^PUBLIC_FILES_SERVER_URL=.*|PUBLIC_FILES_SERVER_URL=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/files|" .env
	sed -i -E "s#- COOKIE_DOMAIN=.*#- COOKIE_DOMAIN=${DOMAIN_HOST}#" docker-compose.yml

	ensure_acme
	acme_issue_cert
}

test_api() {
	echo
	print_info "Testing via Nginx proxy (trusted TLS; -k not needed if OS trusts LE root)..."
	local base="https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}"
	for p in "/api" "/files" "/"; do
		code=$(curl -s -o /dev/null -w "%{http_code}" "${base}${p}" || true)
		if [ -n "$code" ] && [ "$code" != "000" ]; then
			print_success "Proxy responded at ${p} (HTTP ${code})."
		else
			print_error "No response at ${p}."
		fi
	done
}

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
	echo "Note: Certificates remain in ${PROJECT_DIR}/certs (if directory still exists)."
}

# -----------------------------
# Menu / CLI
# -----------------------------
show_menu() {
	cat <<MENU

Standard Notes Manager (Domain + Let's Encrypt @ :80/:443)
=========================================================
1) Install (requires domain; prompts for HTTPS port = 443 default; ACME email optional)
2) Start
3) Stop
4) Restart
5) Status
6) Logs (all)
7) Logs (choose service)
8) Backup
9) Clean data (DANGEROUS)
10) Reissue cert (enter domain)
11) Uninstall (DANGEROUS)
12) Test API
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
	10)
		read -p "Domain (e.g., notes.example.com): " dom
		reissue_cert "$dom"
		;;
	11) uninstall_stack ;;
	12) test_api ;;
	0) exit 0 ;;
	*) echo "Unknown choice" ;;
	esac
}

usage() {
	cat <<USAGE
Usage: $0 <command> [options]

Commands:
  install                 Install the whole stack (domain required; HTTPS port prompt; ACME email optional)
  start                   Start containers
  stop                    Stop containers
  restart                 Restart containers
  status                  Show container status
  logs [service]          Tail logs (optionally one service)
  backup                  Dump DB + uploads + .env under ./backups/
  clean                   Stop & delete MySQL/Redis/uploads/logs data (DANGEROUS)
  reissue-cert <domain>   Re-issue Let's Encrypt cert for domain and reload nginx
  test-api                Quick readiness check through https://DOMAIN:PORT
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
	reissue-cert)
		shift || true
		reissue_cert "${1:-}"
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
