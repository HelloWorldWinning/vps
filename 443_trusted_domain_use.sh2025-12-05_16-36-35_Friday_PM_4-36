#!/usr/bin/env bash
# 443_trusted_domain_use.sh (v5 Rate Limit Smart Fix)
#
# Updates:
# 1. REUSE CERTIFICATES: Checks if certs exist in ~/.acme.sh before requesting new ones.
#    This bypasses the HTTP 429 Rate Limit error.
# 2. Keeps verbose debugging enabled just in case.
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

HTTPS_PORT_OUT=443
HTTP_PORT_OUT=80
DB_PORT_OUT=3306
REDIS_PORT_OUT=6379
LOCALSTACK_PORT_OUT=4566

DOMAIN_HOST=""
ACME_EMAIL=""

# -----------------------------
# Helpers
# -----------------------------
compose_cmd() {
    if docker compose version >/dev/null 2>&1; then echo "docker compose";
    elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose";
    else print_error "Docker Compose not found."; exit 1; fi
}

require_root() {
    if [ "${EUID:-0}" -ne 0 ]; then print_error "Run as root (sudo)."; exit 1; fi
}

require_tools() {
    if ! command -v docker >/dev/null 2>&1; then print_error "Docker not found."; exit 1; fi
    if ! command -v socat >/dev/null 2>&1; then
        print_info "Installing socat (needed for standalone certs)..."
        if [ -x "$(command -v apt-get)" ]; then apt-get update && apt-get install -y socat
        elif [ -x "$(command -v yum)" ]; then yum install -y socat
        fi
    fi
}

port_free() {
    local port="$1"
    if ss -lnt "( sport = :$port )" | awk 'NR>1{exit 1}'; then return 0; fi
    return 1
}

prompt_inputs() {
    local input=""
    echo -ne "${YELLOW}➜ External HTTPS port [default 443] (5s to respond): ${NC}"
    if read -t 5 -r input; then :; else input=""; fi
    if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]; then
        HTTPS_PORT_OUT="$input"
    else
        HTTPS_PORT_OUT=443
        echo "" 
    fi
    print_info "Using external HTTPS port: ${HTTPS_PORT_OUT}"

    echo -ne "${YELLOW}➜ Domain (e.g., notes.example.com) [REQUIRED]: ${NC}"
    if ! read -r input || [ -z "$input" ]; then print_error "Domain is required."; exit 1; fi
    DOMAIN_HOST="$input"

    local clean_dom=$(echo "$DOMAIN_HOST" | tr -d '.-')
    ACME_EMAIL="${clean_dom}@gmail.com"
    print_info "Domain: ${DOMAIN_HOST} | Email: ${ACME_EMAIL}"
}

write_env() {
    cat >.env <<EOF
DB_HOST=db
DB_PORT=3306
DB_USERNAME=std_notes_user
DB_PASSWORD=${DB_PASSWORD}
DB_DATABASE=standard_notes_db
DB_TYPE=mysql
REDIS_PORT=6379
REDIS_HOST=cache
CACHE_TYPE=redis
AUTH_JWT_SECRET=${AUTH_JWT_SECRET}
AUTH_SERVER_ENCRYPTION_SERVER_KEY=${AUTH_SERVER_ENCRYPTION_SERVER_KEY}
VALET_TOKEN_SECRET=${VALET_TOKEN_SECRET}
PUBLIC_FILES_SERVER_URL=https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}/files
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
  keepalive_timeout  65;
  server_tokens off;
  gzip on;
  limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=10r/s;

  map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
  }

  server {
    listen 80;
    server_name _;
    location / { return 301 https://$host$request_uri; }
  }

  server {
    listen 3001 ssl;
    http2 on;
    server_name _;
    ssl_certificate     /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    location ~ /\.(?!well-known) { return 444; }
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
    }
    location ^~ /files/ {
      rewrite ^/files/?(.*)$ /$1 break;
      proxy_pass http://server:3104;
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_cache off;
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
if [ -z "${TARGET:-}" ] && [ -n "${PUBLIC_ORIGIN:-}" ]; then TARGET="${PUBLIC_ORIGIN%/}/api"; fi
if [ -z "${TARGET:-}" ]; then exit 0; fi
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
    mkdir -p data/mysql data/redis uploads logs nginx certs
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
    ports: ["${DB_PORT_OUT}:3306"]
    volumes: [./data/mysql:/var/lib/mysql]
    networks: [${NETWORK_NAME}]

  cache:
    image: redis:7-alpine
    container_name: standard-notes-cache
    restart: unless-stopped
    command: redis-server --appendonly yes
    ports: ["${REDIS_PORT_OUT}:6379"]
    volumes: [./data/redis:/data]
    networks: [${NETWORK_NAME}]

  localstack:
    image: localstack/localstack:3.0
    container_name: standard-notes-localstack
    restart: unless-stopped
    environment:
      - SERVICES=sns,sqs
      - HOSTNAME_EXTERNAL=localstack
      - LS_LOG=warn
    ports: ["${LOCALSTACK_PORT_OUT}:${LOCALSTACK_PORT_OUT}"]
    volumes: [./localstack_bootstrap.sh:/etc/localstack/init/ready.d/localstack_bootstrap.sh]
    networks: [${NETWORK_NAME}]

  server:
    image: standardnotes/server
    container_name: standard-notes-server
    restart: unless-stopped
    env_file: .env
    environment:
      - AUTH_SERVER_DISABLE_USER_REGISTRATION=\${AUTH_SERVER_DISABLE_USER_REGISTRATION}
      - COOKIE_DOMAIN=${DOMAIN_HOST}
      - LOG_LEVEL=debug
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - AWS_REGION=us-east-1
      - SNS_ENDPOINT=http://localstack:4566
      - SQS_ENDPOINT=http://localstack:4566
      - GLOBAL_SNS_ENDPOINT=http://localstack:4566
      - GLOBAL_SQS_ENDPOINT=http://localstack:4566
    volumes:
      - ./logs:/var/lib/server/logs
      - ./uploads:/opt/server/packages/files/dist/uploads
    networks: [${NETWORK_NAME}]
    depends_on: [db, cache, localstack]

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
    volumes: [./web-entry:/docker-entrypoint.d]
    networks: [${NETWORK_NAME}]
    depends_on: [server]

  nginx:
    image: nginx:1.25-alpine
    container_name: standard-notes-proxy
    depends_on: [web, server]
    ports: ["${HTTPS_PORT_OUT}:3001", "${HTTP_PORT_OUT}:80"]
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
    networks: [${NETWORK_NAME}]

networks:
  ${NETWORK_NAME}: { name: ${NETWORK_NAME}, driver: bridge }
EOF
}

write_localstack_bootstrap() {
    cat >localstack_bootstrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOCALSTACK_HOST=localhost
AWS_REGION=us-east-1
LOCALSTACK_DUMMY_ID=000000000000
get_q_arn(){ echo "arn:aws:sns:${AWS_REGION}:${LOCALSTACK_DUMMY_ID}:$1"; }
get_t_arn(){ echo "arn:aws:sns:${AWS_REGION}:${LOCALSTACK_DUMMY_ID}:$1"; }
c_top(){ awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns create-topic --name $1; }
c_que(){ awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sqs create-queue --queue-name $1; }
link(){ awslocal --endpoint-url=http://${LOCALSTACK_HOST}:4566 sns subscribe --topic-arn $1 --protocol sqs --notification-endpoint $2; }

T_PAY="payments-local-topic"; c_top $T_PAY
T_SYNC="syncing-server-local-topic"; c_top $T_SYNC
T_AUTH="auth-local-topic"; c_top $T_AUTH
T_FILE="files-local-topic"; c_top $T_FILE
T_ANA="analytics-local-topic"; c_top $T_ANA
T_REV="revisions-server-local-topic"; c_top $T_REV
T_SCH="scheduler-local-topic"; c_top $T_SCH

Q_ANA="analytics-local-queue"; c_que $Q_ANA; link $(get_t_arn $T_PAY) $(get_q_arn $Q_ANA)
Q_AUTH="auth-local-queue"; c_que $Q_AUTH
link $(get_t_arn $T_PAY) $(get_q_arn $Q_AUTH); link $(get_t_arn $T_AUTH) $(get_q_arn $Q_AUTH)
link $(get_t_arn $T_FILE) $(get_q_arn $Q_AUTH); link $(get_t_arn $T_REV) $(get_q_arn $Q_AUTH)

Q_FILE="files-local-queue"; c_que $Q_FILE
link $(get_t_arn $T_AUTH) $(get_q_arn $Q_FILE); link $(get_t_arn $T_SYNC) $(get_q_arn $Q_FILE)

Q_SYNC="syncing-server-local-queue"; c_que $Q_SYNC
link $(get_t_arn $T_SYNC) $(get_q_arn $Q_SYNC); link $(get_t_arn $T_FILE) $(get_q_arn $Q_SYNC)
link $(get_t_arn $T_SYNC) $(get_q_arn $Q_AUTH); link $(get_t_arn $T_AUTH) $(get_q_arn $Q_SYNC)

Q_REV="revisions-server-local-queue"; c_que $Q_REV
link $(get_t_arn $T_SYNC) $(get_q_arn $Q_REV); link $(get_t_arn $T_REV) $(get_q_arn $Q_REV)

c_que "scheduler-local-queue"
echo "Localstack Init Complete"
EOF
    chmod +x localstack_bootstrap.sh
}

ensure_acme() {
    if [ -x "/root/.acme.sh/acme.sh" ]; then print_success "acme.sh installed."; return 0; fi
    print_info "Installing acme.sh..."
    curl -fsSL https://get.acme.sh | sh -s email="${ACME_EMAIL}" >/dev/null 2>&1 || { print_error "Install failed"; exit 1; }
    print_success "acme.sh installed."
}

issue_cert_smart() {
    local acme="/root/.acme.sh/acme.sh"
    
    # 1. Force clear port 80 if needed
    if ! port_free 80; then
        print_info "Port 80 busy. Stopping docker stack..."
        if [ -d "$PROJECT_DIR" ]; then (cd "$PROJECT_DIR" && $(compose_cmd) down >/dev/null 2>&1 || true); fi
        sleep 3
        if ! port_free 80; then
             print_error "Port 80 is STILL busy. Manual intervention required."
             exit 1
        fi
    fi

    # 2. SMART CHECK: Do valid certs already exist?
    if "$acme" --list | grep -q "${DOMAIN_HOST}"; then
         print_success "Existing certificate found for ${DOMAIN_HOST}. Skipping issuance to avoid Rate Limit (429)."
    else
         print_info "Requesting NEW certificate for ${DOMAIN_HOST}..."
         # Only issue if we don't have one
         "$acme" --issue --standalone -d "${DOMAIN_HOST}" --debug --force || {
            print_error "Certificate issuance FAILED."
            print_info "If you see '429', you hit the rate limit. Wait 1 hour or use a different domain."
            exit 1
         }
    fi

    # 3. Install Certs (copies files to project dir)
    mkdir -p "${PROJECT_DIR}/certs"
    print_info "Installing certificates to ${PROJECT_DIR}/certs..."
    
    "$acme" --install-cert -d "${DOMAIN_HOST}" \
        --key-file       "${PROJECT_DIR}/certs/server.key" \
        --fullchain-file "${PROJECT_DIR}/certs/server.crt" \
        --reloadcmd      "cd ${PROJECT_DIR} && $(compose_cmd) exec -T nginx nginx -s reload" \
        >/dev/null 2>&1 || print_info "Cert files copied (stack is down, reload skipped)."
        
    print_success "Certificates ready."
}

install_stack() {
    require_root
    require_tools
    prompt_inputs
    if ! port_free "${HTTPS_PORT_OUT}"; then print_error "Port ${HTTPS_PORT_OUT} busy."; exit 1; fi
    
    if [ -d "$PROJECT_DIR" ]; then
        print_info "Removing old stack..."
        (cd "$PROJECT_DIR" && $(compose_cmd) down -v >/dev/null 2>&1 || true)
        rm -rf "$PROJECT_DIR"
    fi

    mkdir -p "$PROJECT_DIR"/{data/mysql,data/redis,uploads,logs,nginx,certs,web-entry}
    cd "$PROJECT_DIR"

    AUTH_JWT_SECRET=$(openssl rand -hex 32)
    AUTH_SERVER_ENCRYPTION_SERVER_KEY=$(openssl rand -hex 32)
    VALET_TOKEN_SECRET=$(openssl rand -hex 32)
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    write_env
    write_nginx_conf
    write_web_entry
    write_compose
    write_localstack_bootstrap

    ensure_acme
    issue_cert_smart

    print_info "Starting stack..."
    $(compose_cmd) pull -q
    $(compose_cmd) up -d
    print_success "Installed! https://${DOMAIN_HOST}:${HTTPS_PORT_OUT}"
}

start_stack() { cd "$PROJECT_DIR" && $(compose_cmd) up -d; }
stop_stack() { cd "$PROJECT_DIR" && $(compose_cmd) down; }
restart_stack() { cd "$PROJECT_DIR" && $(compose_cmd) restart; }
logs_stack() { cd "$PROJECT_DIR" && $(compose_cmd) logs -f "${1:-}"; }
uninstall_stack() {
    read -p "Type 'delete' to uninstall: " c
    if [ "$c" == "delete" ]; then cd "$PROJECT_DIR" && $(compose_cmd) down -v; rm -rf "$PROJECT_DIR"; print_success "Deleted"; fi
}

show_menu() {
    cat <<MENU
Standard Notes (Smart Fix)
1) Install
2) Start
3) Stop
4) Restart
5) Logs
6) Uninstall
0) Exit
MENU
    read -p "Select: " c
    case "$c" in
        1) install_stack ;; 2) start_stack ;; 3) stop_stack ;; 4) restart_stack ;; 5) logs_stack ;; 6) uninstall_stack ;; 0) exit 0 ;; *) show_menu ;;
    esac
}
main() { if [ "${1:-}" != "" ]; then "$@"; else show_menu; fi; }
main "$@"
