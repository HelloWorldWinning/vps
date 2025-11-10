#!/usr/bin/env bash
# writefreely_setup.sh
# Idempotent, bind-mount-only WriteFreely deployment designed for rsync migration.
# All persistent data lives in: /data/writefreely_d/data
#
# After rsync to another VPS:
#   cd /data/writefreely_d && docker compose up -d
#
# Environment overrides (examples):
#   WF_HOST="http://sg.zhulei.eu.org:${web_port}" WF_ADMIN_USER="admin" WF_ADMIN_PASS="adminpasswd" ./writefreely_setup.sh
#   WF_PORT=${web_port} DB_IMAGE=mariadb:10.11 ./writefreely_setup.sh

set -Eeuo pipefail

# Prompt user for web port with 5 second timeout
read -t 5 -p "Enter web port (default: 3212): " web_port

# If no input or timeout, use default
if [ -z "$web_port" ]; then
	web_port=3212
fi

echo "Using web port: $web_port"

# ------------------------------------------------------------------------------
# Defaults (can be overridden via environment)
# ------------------------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/data/writefreely_d}"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
DATA_DIR="${DATA_DIR:-$BASE_DIR/data}"
DB_DIR="${DB_DIR:-$DATA_DIR/db}"
KEYS_DIR="${KEYS_DIR:-$DATA_DIR/keys}"
CONFIG_FILE="${CONFIG_FILE:-$DATA_DIR/config.ini}"

WF_IMAGE="${WF_IMAGE:-writeas/writefreely:latest}"
DB_IMAGE="${DB_IMAGE:-mariadb:10.11}"

WF_PORT="${WF_PORT:-${web_port}}"
WF_BIND="${WF_BIND:-0.0.0.0}"
WF_SITE_NAME="${WF_SITE_NAME:-WriteFreely}"
#WF_HOST="${WF_HOST:-http://localhost:${WF_PORT}}"

# NEW: smart localhost replacement for WF_HOST
if [ -z "${WF_HOST:-}" ] || [[ "$WF_HOST" =~ (^|//)(localhost|127\.0\.0\.1|0\.0\.0\.0)(:|/|$) ]]; then
	# Try to get user input with timeout
	__WF_DOMAIN=""
	if [ -t 0 ]; then # Check if stdin is a terminal
		echo -n "Enter your domain (press Enter to auto-detect in 5s): " >&2
		if read -t 5 -r __WF_DOMAIN 2>/dev/null; then
			: # Successfully read input
		else
			echo "" >&2 # New line after timeout
		fi
	fi

	if [ -n "$__WF_DOMAIN" ]; then
		__HOST="$__WF_DOMAIN"
	else
		# Try multiple providers to get the public IP (IPv4 preferred)
		__HOST=""

		# Try ip.sb
		if [ -z "$__HOST" ]; then
			__HOST=$(curl -fsS -m 3 https://ip.sb 2>/dev/null | head -n1 | tr -d '[:space:]') || __HOST=""
		fi

		# Try ipify
		if [ -z "$__HOST" ]; then
			__HOST=$(curl -fsS -m 3 https://api.ipify.org 2>/dev/null | head -n1 | tr -d '[:space:]') || __HOST=""
		fi

		# Try OpenDNS resolver
		if [ -z "$__HOST" ] && command -v dig >/dev/null 2>&1; then
			__HOST=$(dig +short +time=2 myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -n1 | tr -d '[:space:]') || __HOST=""
		fi

		# Try ifconfig.me
		if [ -z "$__HOST" ]; then
			__HOST=$(curl -fsS -m 3 https://ifconfig.me 2>/dev/null | head -n1 | tr -d '[:space:]') || __HOST=""
		fi

		# Fallback to localhost if all detection methods fail
		if [ -z "$__HOST" ]; then
			__HOST="localhost"
			echo "Warning: Could not detect public IP, using localhost" >&2
		fi
	fi

	# Ensure scheme is present
	case "$__HOST" in
	http://* | https://*)
		__BASE="$__HOST"
		;;
	*)
		__BASE="http://${__HOST}"
		;;
	esac

	# Add port if needed
	# Check if port is already in the URL
	if [[ "$__BASE" =~ :[0-9]+($|/) ]]; then
		WF_HOST="$__BASE"
	else
		# Add port only if it's not the default for the scheme
		if [[ "$__BASE" == https://* ]] && [[ "${WF_PORT:-443}" == "443" ]]; then
			WF_HOST="$__BASE"
		elif [[ "$__BASE" == http://* ]] && [[ "${WF_PORT:-80}" == "80" ]]; then
			WF_HOST="$__BASE"
		else
			# Strip trailing slash before adding port
			__BASE="${__BASE%/}"
			WF_HOST="${__BASE}:${WF_PORT}"
		fi
	fi
else
	# Use the explicitly provided WF_HOST from environment
	WF_HOST="$WF_HOST"
fi

export WF_HOST

# Display the final WF_HOST value
echo "Using WF_HOST: $WF_HOST" >&2

DB_NAME="${DB_NAME:-writefreely}"
DB_USER="${DB_USER:-writefreely}"
DB_PASS="${DB_PASS:-writefreely_pass}"
DB_ROOT_PASS="${DB_ROOT_PASS:-root_pass}"

#WF_ADMIN_USER="${WF_ADMIN_USER:-admin}"       # 'admin' is often reserved; we'll still accept it and fallback if needed
WF_ADMIN_USER="${WF_ADMIN_USER:-note1}"        # 'admin' is often reserved; we'll still accept it and fallback if needed
WF_ADMIN_PASS="${WF_ADMIN_PASS:-admin_passwd}" # generated if empty

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
log() { echo "[$(date -Is)] $*"; }
err() { echo "[$(date -Is)] ERROR: $*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || {
	err "Missing required command: $1"
	exit 1
}; }

choose_compose() {
	if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
		echo "docker compose -f \"$COMPOSE_FILE\""
	elif command -v docker-compose >/dev/null 2>&1; then
		echo "docker-compose -f \"$COMPOSE_FILE\""
	else
		err "Docker Compose not found (need 'docker compose' or 'docker-compose')."
		exit 1
	fi
}

gen_admin_pass_if_needed() {
	if [[ -z "$WF_ADMIN_PASS" ]]; then
		if command -v openssl >/dev/null 2>&1; then
			WF_ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)"
		else
			WF_ADMIN_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
		fi
	fi
}

write_compose() {
	mkdir -p "$BASE_DIR"
	# No top-level 'version:' (Compose v2+ infers the schema and avoids the warning)
	cat >"$COMPOSE_FILE" <<YAML
networks:
  external_writefreely:
    driver: bridge
  internal_writefreely:
    internal: true

services:
  writefreely-db:
    image: "${DB_IMAGE}"
    container_name: "writefreely-db"
    command: ["--character-set-server=utf8mb4","--collation-server=utf8mb4_unicode_ci"]
    environment:
      - MYSQL_DATABASE=${DB_NAME}
      - MYSQL_USER=${DB_USER}
      - MYSQL_PASSWORD=${DB_PASS}
      - MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}
    volumes:
      - "${DB_DIR}:/var/lib/mysql"
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-uroot", "-p${DB_ROOT_PASS}"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 20s
    networks:
      - internal_writefreely
    restart: unless-stopped

  writefreely-web:
    image: "${WF_IMAGE}"
    container_name: "writefreely-web"
    user: "2:2"           # 'daemon' in the official image
    working_dir: /go
    depends_on:
      writefreely-db:
        condition: service_healthy
    environment:
      - TZ=UTC
    volumes:
      - "${KEYS_DIR}:/go/keys"
      - "${CONFIG_FILE}:/go/config.ini"
    ports:
      - "${WF_PORT}:${web_port}"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${web_port}/ || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - internal_writefreely
      - external_writefreely
    restart: unless-stopped
YAML
}

write_config_if_missing() {
	if [[ -f "$CONFIG_FILE" ]]; then
		log "config.ini already exists; leaving it unchanged."
		return
	fi
	mkdir -p "$DATA_DIR"
	cat >"$CONFIG_FILE" <<INI
[server]
port = ${web_port}
bind = ${WF_BIND}
# Match container mount /go/keys
keys_parent_dir = keys

[database]
type = mysql
username = ${DB_USER}
password = ${DB_PASS}
database = ${DB_NAME}
host = writefreely-db
port = 3306
tls = false

[app]
site_name = ${WF_SITE_NAME}
host = ${WF_HOST}
single_user = false
open_registration = false
local_timeline = true
min_username_len = 1
INI
}

ensure_permissions() {
	mkdir -p "$KEYS_DIR" "$DB_DIR"
	# WF runs as uid/gid 2:2 in the container
	chown -R 2:2 "$KEYS_DIR" || true
	chmod -R 770 "$KEYS_DIR" || true
	# MariaDB official image uses 999:999
	chown -R 999:999 "$DB_DIR" || true
	chmod -R 770 "$DB_DIR" || true
	# Config readable by WF
	chown 2:2 "$CONFIG_FILE" || true
	chmod 640 "$CONFIG_FILE" || true
}

wait_for_db() {
	local compose="$1"
	log "Starting database container..."
	(cd "$BASE_DIR" && eval "$compose up -d writefreely-db")

	log "Waiting for MariaDB healthcheck to pass..."
	local tries=0
	until (cd "$BASE_DIR" && eval "$compose ps --services --filter status=running" | grep -q '^writefreely-db$') &&
		(cd "$BASE_DIR" && eval "$compose exec -T writefreely-db mysqladmin ping -uroot -p\"${DB_ROOT_PASS}\" --silent" >/dev/null 2>&1); do
		sleep 2
		tries=$((tries + 1))
		if ((tries > 120)); then
			err "Timed out waiting for MariaDB to be ready."
			docker logs writefreely-db || true
			exit 1
		fi
	done
	# Extra buffer so peers can accept TCP (helps avoid race seen in earlier attempts)
	sleep 8
	log "MariaDB is ready."
}

compose_run_wf() {
	# Run a one-shot container with service entrypoint (ensures correct PATH/working_dir)
	local compose="$1"
	shift
	(cd "$BASE_DIR" && eval "$compose run --rm -u 2:2 writefreely-web -c /go/config.ini $*")
}

bootstrap_writefreely() {
	local compose="$1"

	log "Generating keys (idempotent)…"
	compose_run_wf "$compose" keys generate || true

	log "Initializing database schema (idempotent)…"
	compose_run_wf "$compose" db init || true

	gen_admin_pass_if_needed

	# Try requested username first; if it fails due to being reserved/invalid, fall back
	local target_user="$WF_ADMIN_USER"
	log "Creating admin user \"${target_user}\" (idempotent)…"
	if ! compose_run_wf "$compose" user create --admin "${target_user}:${WF_ADMIN_PASS}"; then
		# Common reserved names include: admin, administrator, root, etc.
		if [[ "${target_user,,}" =~ ^(admin|administrator|root|owner|support|www|api|public)$ ]]; then
			target_user="wfadmin"
			log "Requested admin username appears reserved; retrying with \"${target_user}\"…"
			compose_run_wf "$compose" user create --admin "${target_user}:${WF_ADMIN_PASS}" || true
		else
			log "Admin creation may have failed (possibly exists already); continuing."
		fi
	fi

	# Persist the actual admin username we ended up with (for the final info block)
	WF_ADMIN_USER="$target_user"
}

start_web() {
	local compose="$1"
	log "Starting WriteFreely web container…"
	(cd "$BASE_DIR" && eval "$compose up -d writefreely-web")
}

wait_for_http() {
	log "Waiting for WriteFreely HTTP endpoint to respond…"
	local tries=0
	until curl -fsS "http://127.0.0.1:${WF_PORT}/" >/dev/null 2>&1; do
		sleep 2
		tries=$((tries + 1))
		if ((tries > 90)); then
			err "WriteFreely HTTP endpoint did not become ready in time."
			docker logs writefreely-web || true
			break
		fi
	done
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
trap 'err "Setup failed. Inspect logs with:
  docker logs writefreely-db || true
  docker logs writefreely-web || true
"' ERR

need docker
mkdir -p "$DATA_DIR" "$DB_DIR" "$KEYS_DIR"

# As requested: remove ALL Docker volumes so only bind mounts hold state (rsync-ready)
log "Removing ALL Docker volumes (for portability)…"
if docker volume ls -q | grep -q .; then
	docker volume ls -q | xargs -r docker volume rm -f >/dev/null 2>&1 || true
fi
docker volume prune -f >/dev/null 2>&1 || true

# Write config + compose, set perms
write_config_if_missing
write_compose
ensure_permissions

COMPOSE_CMD="$(choose_compose)"
log "Using compose command: ${COMPOSE_CMD}"

# Clean stop of any prior stack (bind mounts persist)
log "Stopping any existing stack…"
(cd "$BASE_DIR" && eval "$COMPOSE_CMD down" || true)

# Pull images explicitly for determinism
log "Pulling images…"
docker pull "$DB_IMAGE" >/dev/null
docker pull "$WF_IMAGE" >/dev/null

# 1) Bring up DB and wait until it truly accepts connections
wait_for_db "$COMPOSE_CMD"

# 2) Bootstrap WriteFreely (keys, schema, admin user) using `compose run`
bootstrap_writefreely "$COMPOSE_CMD"

# 3) Start long-running web service
start_web "$COMPOSE_CMD"

# 4) Wait for HTTP to be ready
wait_for_http

# Final required delay, then instance info
sleep 3

cat <<INFO

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ WriteFreely is up.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

URL:                 ${WF_HOST}
Listen:              ${WF_BIND}:${WF_PORT}

Admin username:      ${WF_ADMIN_USER}
Admin password:      ${WF_ADMIN_PASS}

Compose file:        ${COMPOSE_FILE}
Base directory:      ${BASE_DIR}
Data directory:      ${DATA_DIR}
  ├─ Keys:           ${KEYS_DIR}
  └─ DB data:        ${DB_DIR}

Containers:          writefreely-web, writefreely-db
Images:              ${WF_IMAGE}  |  ${DB_IMAGE}

Manage:
  ${COMPOSE_CMD} ps
  ${COMPOSE_CMD} logs -f --tail=100
  ${COMPOSE_CMD} restart writefreely-web
  ${COMPOSE_CMD} down
  ${COMPOSE_CMD} up -d

Migration to another VPS (identical stack & data):
  # On source VPS:
  rsync -aHAX --numeric-ids ${BASE_DIR}/ user@vps_b:${BASE_DIR}/

  # On destination VPS:
  cd ${BASE_DIR}
  ${COMPOSE_CMD} up -d

INFO
