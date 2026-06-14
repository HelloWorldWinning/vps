#!/usr/bin/env bash
set -Eeuo pipefail

# qBittorrent + File Browser installer
# Refactored to avoid qBittorrent temporary-password dependency.
# It writes qBittorrent's PBKDF2 password hash directly into qBittorrent.conf before startup.

APP_DIR="${APP_DIR:-/root/qBittorrent_d}"
DATA_DIR="${DATA_DIR:-/data/qBittorrent_d}"

TZ="${TZ:-Asia/Taipei}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

QBT_SERVICE="qbittorrent"
QBT_CONTAINER="qbittorrent"
QBT_IMAGE="${QBT_IMAGE:-lscr.io/linuxserver/qbittorrent:latest}"
QBT_WEBUI_PORT="${QBT_WEBUI_PORT:-16080}"
QBT_BT_PORT="${QBT_BT_PORT:-16881}"
QBT_USERNAME="${QBT_USERNAME:-winner}"
QBT_PASSWORD="${QBT_PASSWORD:-ofwardao@gmail.com}"

FB_SERVICE="filebrowser"
FB_CONTAINER="filebrowser"
FB_IMAGE="${FB_IMAGE:-filebrowser/filebrowser:s6}"
FB_WEBUI_PORT="${FB_WEBUI_PORT:-16081}"
FB_USERNAME="${FB_USERNAME:-winner}"
FB_PASSWORD="${FB_PASSWORD:-ofwardao@gmail.com}"

# Default File Browser root is downloads only.
# This avoids File Browser trying to read qBittorrent runtime sockets under config/qBittorrent.
FB_ROOT_DIR="${FB_ROOT_DIR:-${DATA_DIR}/downloads}"
FB_DB_DIR="${FB_DB_DIR:-${DATA_DIR}/filebrowser/database}"
FB_CONFIG_DIR="${FB_CONFIG_DIR:-${DATA_DIR}/filebrowser/config}"

COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
PASSWD_FILE="${APP_DIR}/passwd.txt"
COOKIE_FILE="${APP_DIR}/.qbt_cookie"
LOG_FILE="${APP_DIR}/install.log"

mkdir -p "$APP_DIR"
touch "$LOG_FILE"

log() {
	echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

die() {
	echo "ERROR: $*" | tee -a "$LOG_FILE" >&2
	exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
	die "Run this script as root."
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
		"${DATA_DIR}/config/qBittorrent" \
		"${DATA_DIR}/downloads" \
		"${DATA_DIR}/watch" \
		"$FB_ROOT_DIR" \
		"$FB_DB_DIR" \
		"$FB_CONFIG_DIR"

	chmod 700 "$APP_DIR"
	chmod -R 775 "$DATA_DIR"
	chown -R "${PUID}:${PGID}" "$DATA_DIR" >/dev/null 2>&1 || true
}

write_compose_file() {
	log "Writing ${COMPOSE_FILE}..."

	cat >"$COMPOSE_FILE" <<YAML
services:
  ${QBT_SERVICE}:
    image: ${QBT_IMAGE}
#   container_name: ${QBT_CONTAINER}
    restart: unless-stopped
    stop_grace_period: "10s"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - WEBUI_PORT=${QBT_WEBUI_PORT}
      - TORRENTING_PORT=${QBT_BT_PORT}
    volumes:
      - ${DATA_DIR}/config:/config
      - ${DATA_DIR}/downloads:/downloads
      - ${DATA_DIR}/watch:/watch
    ports:
      - "${QBT_WEBUI_PORT}:${QBT_WEBUI_PORT}"
      - "${QBT_BT_PORT}:${QBT_BT_PORT}"
      - "${QBT_BT_PORT}:${QBT_BT_PORT}/udp"
    networks:
      - qB_media_net

  ${FB_SERVICE}:
    image: ${FB_IMAGE}
#   container_name: ${FB_CONTAINER}
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${FB_ROOT_DIR}:/srv
      - ${FB_DB_DIR}:/database
      - ${FB_CONFIG_DIR}:/config
    ports:
      - "${FB_WEBUI_PORT}:80"
    networks:
      - qB_media_net

networks:
  qB_media_net:
    name: qB_media_net
YAML

	chmod 600 "$COMPOSE_FILE"
}

make_qbt_pbkdf2_hash() {
	python3 - "$QBT_PASSWORD" <<'PY'
import base64
import hashlib
import os
import sys

password = sys.argv[1].encode("utf-8")
salt = os.urandom(16)
key = hashlib.pbkdf2_hmac("sha512", password, salt, 100000)
print(f"@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(key).decode()})")
PY
}

patch_ini_section() {
	local file="$1"
	local section="$2"
	shift 2

	python3 - "$file" "$section" "$@" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
section = sys.argv[2]
pairs = [arg.split("=", 1) for arg in sys.argv[3:]]
new_keys = {k for k, _ in pairs}

text = path.read_text(errors="ignore") if path.exists() else ""
lines = text.splitlines()
header = f"[{section}]"

if header not in lines:
    if lines and lines[-1].strip():
        lines.append("")
    lines.append(header)

start = lines.index(header)
end = len(lines)
for i in range(start + 1, len(lines)):
    if lines[i].startswith("[") and lines[i].endswith("]"):
        end = i
        break

# Remove keys we are about to force. qBittorrent uses literal backslashes in keys.
i = start + 1
while i < end:
    key = lines[i].split("=", 1)[0]
    if key in new_keys:
        del lines[i]
        end -= 1
    else:
        i += 1

for key, value in pairs:
    lines.insert(end, f"{key}={value}")
    end += 1

path.write_text("\n".join(lines) + "\n")
PY
}

force_qbt_static_config() {
	local conf="${DATA_DIR}/config/qBittorrent/qBittorrent.conf"
	local pass_hash

	log "Forcing qBittorrent static username/password in config before startup..."
	mkdir -p "$(dirname "$conf")"
	touch "$conf"

	pass_hash="$(make_qbt_pbkdf2_hash)"

	patch_ini_section "$conf" "LegalNotice" \
		'Accepted=true'

	patch_ini_section "$conf" "Preferences" \
		'WebUI\Address=*' \
		"WebUI\\Port=${QBT_WEBUI_PORT}" \
		"WebUI\\Username=${QBT_USERNAME}" \
		"WebUI\\Password_PBKDF2=\"${pass_hash}\"" \
		'WebUI\HostHeaderValidation=false' \
		'WebUI\ServerDomains=*' \
		'Downloads\SavePath=/downloads' \
		'BitTorrent\Session\DefaultSavePath=/downloads'

	chown -R "${PUID}:${PGID}" "${DATA_DIR}/config" >/dev/null 2>&1 || true
}

wait_for_http() {
	local name="$1"
	local port="$2"

	log "Waiting for ${name} on host port ${port}..."

	for _ in $(seq 1 120); do
		local code
		code="$(curl -sS --max-time 4 -o /dev/null -w '%{http_code}' "http://localhost:${port}/" || true)"
		if [[ "$code" == "200" || "$code" == "301" || "$code" == "302" || "$code" == "401" || "$code" == "403" ]]; then
			log "${name} responded with HTTP ${code}."
			return 0
		fi
		sleep 1
	done

	die "${name} did not become reachable on host port ${port}."
}

qbt_api_login() {
	local username="$1"
	local password="$2"
	local base="http://localhost:${QBT_WEBUI_PORT}"

	rm -f "$COOKIE_FILE"

	curl -sS --max-time 8 \
		-c "$COOKIE_FILE" \
		-H "Referer: ${base}/" \
		--data-urlencode "username=${username}" \
		--data-urlencode "password=${password}" \
		"${base}/api/v2/auth/login" || true
}

verify_qbt_static_login() {
	local login_result

	log "Verifying qBittorrent static login..."
	login_result="$(qbt_api_login "$QBT_USERNAME" "$QBT_PASSWORD")"

	if [[ "$login_result" != "Ok." ]]; then
		docker logs "$QBT_CONTAINER" 2>&1 | tail -n 120 | tee -a "$LOG_FILE" || true
		echo "" | tee -a "$LOG_FILE"
		echo "qBittorrent config auth lines:" | tee -a "$LOG_FILE"
		grep -E 'WebUI\\(Username|Password_PBKDF2|Port|Address|HostHeaderValidation|ServerDomains)' \
			"${DATA_DIR}/config/qBittorrent/qBittorrent.conf" | tee -a "$LOG_FILE" || true
		die "qBittorrent static login failed. API said: ${login_result}"
	fi

	rm -f "$COOKIE_FILE"
	log "qBittorrent static login works."
}

fb_cli() {
	docker run --rm \
		-v "${FB_ROOT_DIR}:/srv" \
		-v "${FB_DB_DIR}:/database" \
		-v "${FB_CONFIG_DIR}:/config" \
		--entrypoint filebrowser \
		"$FB_IMAGE" \
		-d /database/filebrowser.db "$@"
}

configure_filebrowser() {
	log "Configuring File Browser static account..."

	mkdir -p "$FB_ROOT_DIR" "$FB_DB_DIR" "$FB_CONFIG_DIR"
	chown -R "${PUID}:${PGID}" "$FB_ROOT_DIR" "$FB_DB_DIR" "$FB_CONFIG_DIR" >/dev/null 2>&1 || true

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

	if fb_cli users update "$FB_USERNAME" \
		--password "$FB_PASSWORD" \
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
			--perm.admin \
			--perm.create \
			--perm.delete \
			--perm.download \
			--perm.modify \
			--perm.rename \
			--perm.share
		log "Created File Browser user '${FB_USERNAME}'."
	fi

	if [[ "$FB_USERNAME" != "admin" ]]; then
		fb_cli users rm admin >/dev/null 2>&1 || true
	fi

	chown -R "${PUID}:${PGID}" "$FB_ROOT_DIR" "$FB_DB_DIR" "$FB_CONFIG_DIR" >/dev/null 2>&1 || true
}

write_passwd_file() {
	local public_host="$1"
	local qbt_url="http://${public_host}:${QBT_WEBUI_PORT}/"
	local fb_url="http://${public_host}:${FB_WEBUI_PORT}/"

	log "Writing credentials to ${PASSWD_FILE}..."

	cat >"$PASSWD_FILE" <<EOF
qBittorrent
URL: ${qbt_url}
Username: ${QBT_USERNAME}
Password: ${QBT_PASSWORD}
WebUI port: ${QBT_WEBUI_PORT}
BT TCP port: ${QBT_BT_PORT}
BT UDP port: ${QBT_BT_PORT}

File Browser
URL: ${fb_url}
Username: ${FB_USERNAME}
Password: ${FB_PASSWORD}
WebUI port: ${FB_WEBUI_PORT}
Root dir: ${FB_ROOT_DIR}

Docker
Compose file: ${COMPOSE_FILE}
qBittorrent container: ${QBT_CONTAINER}
File Browser container: ${FB_CONTAINER}
Docker network: media_net

Host paths
App dir: ${APP_DIR}
Data dir: ${DATA_DIR}
qBittorrent config dir: ${DATA_DIR}/config
qBittorrent downloads dir: ${DATA_DIR}/downloads
qBittorrent watch dir: ${DATA_DIR}/watch
File Browser root dir: ${FB_ROOT_DIR}
File Browser database dir: ${FB_DB_DIR}
File Browser config dir: ${FB_CONFIG_DIR}

Internal Docker URLs
qBittorrent: http://${QBT_SERVICE}:${QBT_WEBUI_PORT}
File Browser: http://${FB_SERVICE}:80
EOF

	chmod 600 "$PASSWD_FILE"
}

main() {
	install_deps
	set_compose_cmd
	make_dirs
	write_compose_file

	log "Stopping/removing old containers with the same names while keeping host data..."
	docker rm -f "$QBT_CONTAINER" >/dev/null 2>&1 || true
	docker rm -f qbittorrent_d >/dev/null 2>&1 || true
	docker rm -f "$FB_CONTAINER" >/dev/null 2>&1 || true

	log "Pulling images..."
	compose pull

	configure_filebrowser
	force_qbt_static_config

	log "Starting qBittorrent and File Browser..."
	compose up -d

	wait_for_http "qBittorrent WebUI" "$QBT_WEBUI_PORT"
	verify_qbt_static_login
	wait_for_http "File Browser" "$FB_WEBUI_PORT"

	local public_host
	public_host="$(get_public_ip)"
	write_passwd_file "$public_host"

	log "Done."
	echo
	echo "============================================================"
	echo "qBittorrent + File Browser installed."
	echo
	echo "Open:"
	echo "  qBittorrent:  http://${public_host}:${QBT_WEBUI_PORT}/"
	echo "  File Browser: http://${public_host}:${FB_WEBUI_PORT}/"
	echo
	echo "qBittorrent login:"
	echo "  Username: ${QBT_USERNAME}"
	echo "  Password: ${QBT_PASSWORD}"
	echo
	echo "File Browser login:"
	echo "  Username: ${FB_USERNAME}"
	echo "  Password: ${FB_PASSWORD}"
	echo
	echo "Credentials saved at:"
	echo "  ${PASSWD_FILE}"
	echo
	echo "Show credentials later:"
	echo "  cat ${PASSWD_FILE}"
	echo
	echo "Downloads:"
	echo "  ${DATA_DIR}/downloads"
	echo "============================================================"
}

main "$@"
