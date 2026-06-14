#!/usr/bin/env bash
#  install_filebrowser.sh
# =====================================
#
# Run:
#   bash install_filebrowser.sh
#
# Default login:
#   Username: winner
#   Password: ofwardao@gmail.com
#
# Image  : filebrowser/filebrowser:s6
# Port   : 88  →  http://PUBLIC_IP:88/
# Root   : / on host, mounted as /srv inside container
# Compose: /root/File_Browser/docker-compose.yml
#
# Important implementation detail:
#   File Browser is configured with a one-shot CLI container BEFORE the service
#   starts. This avoids SQLite "Error: timeout" from editing filebrowser.db while
#   the live File Browser process is using it.
# =============================================================================

set -Eeuo pipefail

# ── Fixed defaults ────────────────────────────────────────────────────────────
APP_DIR="/root/File_Browser"
TZ="Asia/Taipei"

FB_SERVICE="filebrowser"
FB_CONTAINER="filebrowser"
FB_IMAGE="filebrowser/filebrowser:s6"
FB_WEBUI_PORT="88"

FB_USERNAME="winner"
FB_PASSWORD="ofwardao@gmail.com"

# Expose full host filesystem.
# Host "/" appears as "/srv" inside File Browser.
FB_HOST_ROOT="/"
FB_ROOT_IN_CONTAINER="/srv"

FB_DB_DIR="${APP_DIR}/database"
FB_CONFIG_DIR="${APP_DIR}/config"

COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
PASSWD_FILE="${APP_DIR}/passwd.txt"
LOG_FILE="${APP_DIR}/install.log"

# Run File Browser as root so it can browse the mounted host root.
PUID="0"
PGID="0"

# ── Helpers ───────────────────────────────────────────────────────────────────
mkdir -p "$APP_DIR"
touch "$LOG_FILE"

log() {
	echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

die() {
	echo "ERROR: $*" | tee -a "$LOG_FILE" >&2
	exit 1
}

on_error() {
	local exit_code=$?
	local line_no=$1
	echo "" >&2
	echo "Installer failed at line ${line_no} with exit code ${exit_code}." >&2
	echo "Last File Browser logs, if any:" >&2
	docker logs "$FB_CONTAINER" --tail=120 2>/dev/null >&2 || true
	exit "$exit_code"
}
trap 'on_error $LINENO' ERR

if [[ "${EUID}" -ne 0 ]]; then
	die "Run this script as root. Example: bash install_filebrowser.sh"
fi

install_deps() {
	log "Checking dependencies..."

	local need_apt=0
	for bin in curl python3 docker; do
		if ! command -v "$bin" >/dev/null 2>&1; then
			need_apt=1
		fi
	done

	if [[ "$need_apt" -eq 1 ]]; then
		if command -v apt-get >/dev/null 2>&1; then
			log "Installing curl, python3, Docker, and Docker Compose plugin with apt..."
			apt-get update
			apt-get install -y curl python3 docker.io docker-compose-plugin
		else
			die "Missing curl/python3/docker and apt-get is not available. Install them first."
		fi
	fi

	if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
		if command -v apt-get >/dev/null 2>&1; then
			log "Installing Docker Compose..."
			apt-get update
			apt-get install -y docker-compose-plugin || apt-get install -y docker-compose
		else
			die "Docker Compose is missing."
		fi
	fi

	systemctl enable --now docker >/dev/null 2>&1 || true
}

set_compose_cmd() {
	if docker compose version >/dev/null 2>&1; then
		COMPOSE_CMD=(docker compose)
	elif command -v docker-compose >/dev/null 2>&1; then
		COMPOSE_CMD=(docker-compose)
	else
		die "Docker Compose is not available."
	fi

	log "Using compose: ${COMPOSE_CMD[*]}"
}

compose() {
	(cd "$APP_DIR" && "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "$@")
}

get_public_ip() {
	local url ip
	local urls=(
		"https://ip.sb"
		"https://api.ipify.org"
		"https://ifconfig.me/ip"
		"https://icanhazip.com"
		"https://ipinfo.io/ip"
	)

	for url in "${urls[@]}"; do
		ip="$(curl -4fsSL --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
		if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && [[ ! "$ip" =~ ^127\. ]]; then
			echo "$ip"
			return 0
		fi
	done

	ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
	if [[ -n "$ip" && ! "$ip" =~ ^127\. ]]; then
		echo "$ip"
		return 0
	fi

	echo "YOUR_PUBLIC_IP"
}

make_dirs() {
	log "Creating directories..."

	mkdir -p \
		"$APP_DIR" \
		"$FB_DB_DIR" \
		"$FB_CONFIG_DIR"

	chmod 700 "$APP_DIR"
	chmod 700 "$FB_DB_DIR" "$FB_CONFIG_DIR"
}

write_settings_json() {
	log "Writing File Browser settings.json..."

	# root is "/" so File Browser sees the real host paths directly,
	# matching the host-root volume mount (FB_HOST_ROOT="/").
	cat >"${FB_CONFIG_DIR}/settings.json" <<EOF
{
  "port": 80,
  "baseURL": "",
  "address": "0.0.0.0",
  "log": "stdout",
  "database": "/database/filebrowser.db",
  "root": "/"
}
EOF

	chmod 600 "${FB_CONFIG_DIR}/settings.json"
}

write_compose_file() {
	log "Writing ${COMPOSE_FILE}..."

	cat >"$COMPOSE_FILE" <<YAML
services:
  ${FB_SERVICE}:
    image: ${FB_IMAGE}
    container_name: ${FB_CONTAINER}
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${FB_HOST_ROOT}:${FB_ROOT_IN_CONTAINER}
      - ${FB_DB_DIR}:/database
      - ${FB_CONFIG_DIR}:/config
    ports:
      - "${FB_WEBUI_PORT}:80"
YAML

	chmod 600 "$COMPOSE_FILE"
}

fb_cli() {
	docker run --rm \
		--user 0:0 \
		-e "PUID=${PUID}" \
		-e "PGID=${PGID}" \
		-e "TZ=${TZ}" \
		-v "${FB_HOST_ROOT}:${FB_ROOT_IN_CONTAINER}" \
		-v "${FB_DB_DIR}:/database" \
		-v "${FB_CONFIG_DIR}:/config" \
		--entrypoint filebrowser \
		"$FB_IMAGE" \
		-d /database/filebrowser.db "$@"
}

stop_old_filebrowser() {
	log "Stopping/removing old File Browser container while keeping host data..."

	if [[ -f "$COMPOSE_FILE" ]]; then
		compose down --remove-orphans >/dev/null 2>&1 || true
	fi

	docker rm -f "$FB_CONTAINER" >/dev/null 2>&1 || true
}

configure_filebrowser() {
	log "Configuring File Browser static account before startup..."

	mkdir -p "$FB_DB_DIR" "$FB_CONFIG_DIR"

	# Do config through one-shot CLI container, not docker exec into the running service.
	# This avoids SQLite timeout/lock problems.
	if [[ ! -f "${FB_DB_DIR}/filebrowser.db" ]]; then
		fb_cli config init \
			--address 0.0.0.0 \
			--port 80 \
			--root /srv \
			--minimumPasswordLength 1
	else
		fb_cli config set \
			--address 0.0.0.0 \
			--port 80 \
			--root /srv \
			--minimumPasswordLength 1
	fi

	# Update first; if user does not exist, add.
	if fb_cli users update "$FB_USERNAME" \
		--password "$FB_PASSWORD" \
		--scope /srv \
		--perm.admin \
		--perm.create \
		--perm.delete \
		--perm.download \
		--perm.modify \
		--perm.rename \
		--perm.share >/dev/null 2>&1; then
		log "Updated existing File Browser user '${FB_USERNAME}'."
	else
		fb_cli users add "$FB_USERNAME" "$FB_PASSWORD" \
			--scope /srv \
			--perm.admin \
			--perm.create \
			--perm.delete \
			--perm.download \
			--perm.modify \
			--perm.rename \
			--perm.share
		log "Created File Browser user '${FB_USERNAME}'."
	fi

	# Remove default admin unless the configured user is admin.
	if [[ "$FB_USERNAME" != "admin" ]]; then
		fb_cli users rm admin >/dev/null 2>&1 || true
	fi

	chmod 700 "$FB_DB_DIR" "$FB_CONFIG_DIR"
}

wait_for_http() {
	log "Waiting for File Browser on host port ${FB_WEBUI_PORT}..."

	local code
	for _ in $(seq 1 120); do
		code="$(curl -sS --max-time 4 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${FB_WEBUI_PORT}/" || true)"
		if [[ "$code" == "200" || "$code" == "301" || "$code" == "302" || "$code" == "401" || "$code" == "403" ]]; then
			log "File Browser responded with HTTP ${code}."
			return 0
		fi
		sleep 1
	done

	docker logs "$FB_CONTAINER" --tail=160 2>&1 | tee -a "$LOG_FILE" || true
	die "File Browser did not become reachable on host port ${FB_WEBUI_PORT}."
}

verify_filebrowser_login() {
	log "Verifying File Browser login..."

	local payload_file response_file http_code
	payload_file="$(mktemp)"
	response_file="$(mktemp)"

	FB_USERNAME_JSON="$FB_USERNAME" FB_PASSWORD_JSON="$FB_PASSWORD" python3 - "$payload_file" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(
        {
            "username": os.environ["FB_USERNAME_JSON"],
            "password": os.environ["FB_PASSWORD_JSON"],
        },
        f,
    )
PY

	http_code="$(curl -sS --max-time 8 \
		-o "$response_file" \
		-w '%{http_code}' \
		-H 'Content-Type: application/json' \
		--data-binary "@${payload_file}" \
		"http://127.0.0.1:${FB_WEBUI_PORT}/api/login" || true)"

	rm -f "$payload_file"

	if [[ "$http_code" != "200" ]]; then
		echo "" | tee -a "$LOG_FILE"
		echo "File Browser login verification failed. HTTP code: ${http_code}" | tee -a "$LOG_FILE"
		echo "Response body:" | tee -a "$LOG_FILE"
		cat "$response_file" | tee -a "$LOG_FILE" || true
		echo "" | tee -a "$LOG_FILE"
		echo "Known File Browser users from DB:" | tee -a "$LOG_FILE"
		fb_cli users ls 2>&1 | tee -a "$LOG_FILE" || true
		echo "" | tee -a "$LOG_FILE"
		docker logs "$FB_CONTAINER" --tail=160 2>&1 | tee -a "$LOG_FILE" || true
		rm -f "$response_file"
		die "File Browser static login failed."
	fi

	rm -f "$response_file"
	log "File Browser login works."
}

open_ufw_port() {
	if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
		log "Opening ufw port ${FB_WEBUI_PORT}/tcp..."
		ufw allow "${FB_WEBUI_PORT}/tcp" || true
	fi
}

write_passwd_file() {
	local public_host="$1"
	local fb_url="http://${public_host}:${FB_WEBUI_PORT}/"

	log "Writing credentials to ${PASSWD_FILE}..."

	cat >"$PASSWD_FILE" <<EOF
File Browser
URL: ${fb_url}
Username: ${FB_USERNAME}
Password: ${FB_PASSWORD}
WebUI port: ${FB_WEBUI_PORT}
Host root mounted: ${FB_HOST_ROOT}
Container root: ${FB_ROOT_IN_CONTAINER}

Docker
Compose file: ${COMPOSE_FILE}
File Browser container: ${FB_CONTAINER}

Host paths
App dir: ${APP_DIR}
File Browser database dir: ${FB_DB_DIR}
File Browser config dir: ${FB_CONFIG_DIR}

Useful commands
cd ${APP_DIR} && ${COMPOSE_CMD[*]} logs -f
cd ${APP_DIR} && ${COMPOSE_CMD[*]} restart
cd ${APP_DIR} && ${COMPOSE_CMD[*]} down
cd ${APP_DIR} && ${COMPOSE_CMD[*]} up -d
EOF

	chmod 600 "$PASSWD_FILE"
}

main() {
	install_deps
	set_compose_cmd
	make_dirs

	log "Pulling image..."
	docker pull "$FB_IMAGE"

	stop_old_filebrowser
	write_settings_json
	write_compose_file

	configure_filebrowser

	log "Starting File Browser..."
	compose up -d

	wait_for_http
	verify_filebrowser_login
	open_ufw_port

	local public_host
	public_host="$(get_public_ip)"
	write_passwd_file "$public_host"

	log "Done."

	echo
	echo "============================================================"
	echo "File Browser installed."
	echo
	echo "Open:"
	echo "  File Browser: http://${public_host}:${FB_WEBUI_PORT}/"
	echo
	echo "Login:"
	echo "  Username: ${FB_USERNAME}"
	echo "  Password: ${FB_PASSWORD}"
	echo
	echo "Credentials saved at:"
	echo "  ${PASSWD_FILE}"
	echo
	echo "Show credentials later:"
	echo "  cat ${PASSWD_FILE}"
	echo
	echo "Useful commands:"
	echo "  cd ${APP_DIR} && ${COMPOSE_CMD[*]} logs -f"
	echo "  cd ${APP_DIR} && ${COMPOSE_CMD[*]} restart"
	echo "  cd ${APP_DIR} && ${COMPOSE_CMD[*]} down"
	echo "  cd ${APP_DIR} && ${COMPOSE_CMD[*]} up -d"
	echo
	echo "SECURITY WARNING:"
	echo "  This exposes the full host filesystem '/' through File Browser."
	echo "  Protect port ${FB_WEBUI_PORT} with firewall/VPN/reverse proxy if public."
	echo "============================================================"
}

main "$@"
