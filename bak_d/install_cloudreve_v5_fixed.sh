#!/usr/bin/env bash
set -euo pipefail

# install_cloudreve_v5_fixed.sh
#
# Cloudreve v4 + Aria2-Pro installer/fixer.
#
# Fixes handled:
#   1. Cloudreve users/settings disappearing after docker compose down/up:
#      persist /cloudreve/data on host.
#   2. Aria2 cannot write .aria2 progress files:
#      make shared /data writable and run Aria2 with Cloudreve-compatible UID/GID.
#   3. Magnet stuck after restart:
#      persist /config/aria2.session and force Aria2 save/load session.
#   4. Re-adding same magnet fails with:
#        InfoHash ... is already registered
#      remove stale zero-size [METADATA] / orphan magnet tasks from Aria2 and resave session.
#
# Safe defaults:
#   - Does NOT delete /data/Cloudreve/cloudreve/data
#   - Does NOT delete completed files
#   - Cleans only Aria2 metadata/orphan tasks by default
#
# Useful env overrides:
#   DEST=/data/Cloudreve
#   CLEAN_ORPHANED_METADATA=true        # default true
#   CLEAN_ALL_ARIA2_TASKS=false         # default false, dangerous; removes all active/waiting Aria2 tasks
#   RESET_ARIA2_SESSION=false           # default false, dangerous; backs up and empties aria2.session
#   ARIA2_SECRET=cloudreve_password
#   ARIA2_BT_PORT=6888

DEST="${DEST:-/data/Cloudreve}"
CLOUDREVE_PORT="${CLOUDREVE_PORT:-1111}"
ARIA2_RPC_HOST_PORT="${ARIA2_RPC_HOST_PORT:-1112}"
ARIA2_RPC_PORT="${ARIA2_RPC_PORT:-6800}"
ARIA2_BT_PORT="${ARIA2_BT_PORT:-6888}"
ARIA2_SECRET="${ARIA2_SECRET:-cloudreve_password}"
TZ_VALUE="${TZ_VALUE:-Asia/Tokyo}"

CLEAN_ORPHANED_METADATA="${CLEAN_ORPHANED_METADATA:-true}"
CLEAN_ALL_ARIA2_TASKS="${CLEAN_ALL_ARIA2_TASKS:-false}"
RESET_ARIA2_SESSION="${RESET_ARIA2_SESSION:-false}"

COMPOSE_FILE="$DEST/docker-compose.yml"
REPORT_FILE="$DEST/cloudreve_admin_password.txt"
BACKUP_DIR="$DEST/backups/$(date +%Y%m%d_%H%M%S)"
TMP_DIR="/tmp/cloudreve_v5_fix_$$"

log() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }

cleanup_tmp() {
	rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup_tmp EXIT

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		err "Missing command: $1"
		exit 1
	}
}

get_public_ip() {
	local ip=""
	for url in "https://ip.sb" "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
		ip="$(curl -s --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
		if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
			echo "$ip"
			return
		fi
	done
	echo "<YOUR_SERVER_IP>"
}

rpc_raw() {
	local payload="$1"
	curl -sS --max-time 15 "http://127.0.0.1:${ARIA2_RPC_HOST_PORT}/jsonrpc" \
		-H 'Content-Type: application/json' \
		-d "$payload" 2>/dev/null || true
}

aria2_rpc() {
	local method="$1"
	local extra_params="${2:-}"
	local params
	if [ -n "$extra_params" ]; then
		params="[\"token:${ARIA2_SECRET}\",${extra_params}]"
	else
		params="[\"token:${ARIA2_SECRET}\"]"
	fi
	rpc_raw "{\"jsonrpc\":\"2.0\",\"id\":\"cli\",\"method\":\"${method}\",\"params\":${params}}"
}

save_aria2_session_if_running() {
	if docker inspect aria2 >/dev/null 2>&1; then
		info "Asking Aria2 to save current session..."
		aria2_rpc "aria2.saveSession" >/dev/null || true
	fi
}

upsert_conf() {
	local file="$1"
	local key="$2"
	local value="$3"

	mkdir -p "$(dirname "$file")"
	touch "$file"

	if grep -qE "^[[:space:]]*#?[[:space:]]*${key}=" "$file"; then
		sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}=.*|${key}=${value}|" "$file"
	else
		printf '%s=%s\n' "$key" "$value" >>"$file"
	fi
}

ensure_aria2_conf() {
	local conf="$DEST/aria2/config/aria2.conf"
	local session="$DEST/aria2/config/aria2.session"

	mkdir -p "$DEST/aria2/config"
	touch "$conf" "$session"

	# Cloudreve sends dir=/data/aria2/<uuid>, but this keeps direct Aria2 tasks sane.
	upsert_conf "$conf" "dir" "/data"

	# RPC.
	upsert_conf "$conf" "enable-rpc" "true"
	upsert_conf "$conf" "rpc-listen-all" "true"
	upsert_conf "$conf" "rpc-listen-port" "$ARIA2_RPC_PORT"
	upsert_conf "$conf" "rpc-secret" "$ARIA2_SECRET"

	# BitTorrent / DHT.
	upsert_conf "$conf" "listen-port" "$ARIA2_BT_PORT"
	upsert_conf "$conf" "dht-listen-port" "$ARIA2_BT_PORT"
	upsert_conf "$conf" "enable-dht" "true"
	upsert_conf "$conf" "enable-dht6" "false"
	upsert_conf "$conf" "enable-peer-exchange" "true"
	upsert_conf "$conf" "bt-enable-lpd" "true"

	# Resume/restart safety.
	upsert_conf "$conf" "continue" "true"
	upsert_conf "$conf" "always-resume" "true"
	upsert_conf "$conf" "auto-save-interval" "30"
	upsert_conf "$conf" "input-file" "/config/aria2.session"
	upsert_conf "$conf" "save-session" "/config/aria2.session"
	upsert_conf "$conf" "save-session-interval" "30"
	upsert_conf "$conf" "force-save" "true"
	upsert_conf "$conf" "keep-unfinished-download-result" "true"

	# Magnet metadata.
	upsert_conf "$conf" "bt-save-metadata" "true"
	upsert_conf "$conf" "bt-load-saved-metadata" "true"
	upsert_conf "$conf" "rpc-save-upload-metadata" "true"

	# File allocation tends to be safer on small VPS disks than falloc.
	upsert_conf "$conf" "file-allocation" "none"

	log "Ensured Aria2 config at $conf"
}

detect_cloudreve_uid_gid() {
	local uid="" gid=""

	if docker inspect cloudreve >/dev/null 2>&1; then
		uid="$(docker exec cloudreve sh -lc 'id -u' 2>/dev/null || true)"
		gid="$(docker exec cloudreve sh -lc 'id -g' 2>/dev/null || true)"
	fi

	uid="${uid:-1000}"
	gid="${gid:-1000}"
	echo "${uid}:${gid}"
}

write_compose() {
	local shared_uid="$1"
	local shared_gid="$2"

	cat >"$COMPOSE_FILE" <<EOF
services:
  redis:
    container_name: redis
    image: redis:latest
    restart: unless-stopped
    volumes:
      - ./redis/data:/data

  cloudreve:
    container_name: cloudreve
    image: cloudreve/cloudreve:latest
    restart: unless-stopped
    ports:
      - "${CLOUDREVE_PORT}:5212"
    environment:
      - TZ=${TZ_VALUE}
    volumes:
      # Cloudreve v4 persistent runtime data/config/database.
      # This prevents users/settings from disappearing after docker compose down/up.
      - ./cloudreve/data:/cloudreve/data

      # Shared download/temp directory.
      # In Cloudreve admin node settings, set Temporary download directory to: /data
      - ./data:/data
    depends_on:
      - redis
      - aria2

  aria2:
    container_name: aria2
    image: p3terx/aria2-pro
    restart: unless-stopped
    ports:
      # Aria2 RPC.
      - "${ARIA2_RPC_HOST_PORT}:${ARIA2_RPC_PORT}"

      # BitTorrent / DHT. Open these in GCP firewall too.
      - "${ARIA2_BT_PORT}:${ARIA2_BT_PORT}"
      - "${ARIA2_BT_PORT}:${ARIA2_BT_PORT}/udp"
    environment:
      # Keep Aria2 file ownership compatible with Cloudreve-created task dirs.
      - PUID=${shared_uid}
      - PGID=${shared_gid}
      - UMASK_SET=000
      - UMASK=000

      - RPC_SECRET=${ARIA2_SECRET}
      - RPC_PORT=${ARIA2_RPC_PORT}
      - LISTEN_PORT=${ARIA2_BT_PORT}
      - DISK_CACHE=64M
      - IPV6_MODE=false
      - UPDATE_TRACKERS=true
      - TZ=${TZ_VALUE}
    volumes:
      # Persistent Aria2 config/session/progress metadata.
      - ./aria2/config:/config

      # Cloudreve uses /data. Aria2-Pro commonly uses /downloads.
      # Mount the same host directory to both to avoid path mismatch.
      - ./data:/data
      - ./data:/downloads
EOF
}

fix_permissions() {
	local shared_uid="$1"
	local shared_gid="$2"

	mkdir -p \
		"$DEST/cloudreve/data/temp/aria2" \
		"$DEST/data/aria2" \
		"$DEST/aria2/config" \
		"$DEST/redis/data"

	touch "$DEST/aria2/config/aria2.session"

	# Cloudreve private runtime data.
	chown -R "$shared_uid:$shared_gid" "$DEST/cloudreve/data" || true
	chmod -R u+rwX,g+rwX "$DEST/cloudreve/data" || true

	# Shared dirs: intentionally permissive because Cloudreve creates task dirs and Aria2 writes inside them.
	chown -R "$shared_uid:$shared_gid" "$DEST/data" "$DEST/aria2/config" || true
	find "$DEST/data" "$DEST/aria2/config" -type d -exec chmod 2777 {} \; 2>/dev/null || true
	find "$DEST/data" "$DEST/aria2/config" -type f -exec chmod 666 {} \; 2>/dev/null || true

	log "Fixed permissions for /cloudreve/data, shared /data, and Aria2 /config"
}

preserve_existing_data() {
	mkdir -p "$BACKUP_DIR"

	[ -f "$COMPOSE_FILE" ] && cp -a "$COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml.bak"
	[ -f "$DEST/install_cloudreve.sh" ] && cp -a "$DEST/install_cloudreve.sh" "$BACKUP_DIR/install_cloudreve.sh.bak"
	[ -f "$DEST/install_cloudreve_v4_fixed.sh" ] && cp -a "$DEST/install_cloudreve_v4_fixed.sh" "$BACKUP_DIR/install_cloudreve_v4_fixed.sh.bak"
	[ -f "$DEST/install_cloudreve_v4_fixed_v2_resume.sh" ] && cp -a "$DEST/install_cloudreve_v4_fixed_v2_resume.sh" "$BACKUP_DIR/install_cloudreve_v4_fixed_v2_resume.sh.bak"
	[ -d "$DEST/aria2/config" ] && cp -a "$DEST/aria2/config" "$BACKUP_DIR/aria2-config.bak" || true
	[ -d "$DEST/cloudreve/data" ] && cp -a "$DEST/cloudreve/data" "$BACKUP_DIR/cloudreve-data.bak" || true

	# Old compose may have stored /cloudreve/data only inside the live container.
	if docker inspect cloudreve >/dev/null 2>&1; then
		mkdir -p "$DEST/cloudreve/data"
		info "Copying current container /cloudreve/data to host..."
		if docker cp cloudreve:/cloudreve/data/. "$DEST/cloudreve/data/" 2>/tmp/cloudreve_cp_err.log; then
			log "Preserved Cloudreve data at $DEST/cloudreve/data"
		else
			warn "Could not copy /cloudreve/data from Cloudreve container:"
			sed 's/^/  /' /tmp/cloudreve_cp_err.log || true
		fi
	else
		warn "No existing cloudreve container found."
	fi

	if docker inspect aria2 >/dev/null 2>&1; then
		mkdir -p "$DEST/aria2/config"
		info "Copying current container /config to host..."
		docker cp aria2:/config/. "$DEST/aria2/config/" 2>/tmp/aria2_cp_err.log || {
			warn "Could not copy /config from Aria2 container:"
			sed 's/^/  /' /tmp/aria2_cp_err.log || true
		}
	fi
}

reset_aria2_session_if_requested() {
	local session="$DEST/aria2/config/aria2.session"

	if [ "$RESET_ARIA2_SESSION" = "true" ]; then
		warn "RESET_ARIA2_SESSION=true: backing up and emptying aria2.session"
		mkdir -p "$BACKUP_DIR"
		[ -f "$session" ] && cp -a "$session" "$BACKUP_DIR/aria2.session.before-reset.bak"
		: >"$session"
		chmod 666 "$session" || true
	fi
}

fetch_aria2_lists() {
	mkdir -p "$TMP_DIR"

	local keys='["gid","status","totalLength","completedLength","downloadSpeed","numSeeders","connections","errorCode","errorMessage","bittorrent","files"]'

	rpc_raw "{\"jsonrpc\":\"2.0\",\"id\":\"active\",\"method\":\"aria2.tellActive\",\"params\":[\"token:${ARIA2_SECRET}\",${keys}]}" >"$TMP_DIR/active.json" || true
	rpc_raw "{\"jsonrpc\":\"2.0\",\"id\":\"waiting\",\"method\":\"aria2.tellWaiting\",\"params\":[\"token:${ARIA2_SECRET}\",0,1000,${keys}]}" >"$TMP_DIR/waiting.json" || true
	rpc_raw "{\"jsonrpc\":\"2.0\",\"id\":\"stopped\",\"method\":\"aria2.tellStopped\",\"params\":[\"token:${ARIA2_SECRET}\",0,1000,${keys}]}" >"$TMP_DIR/stopped.json" || true
}

cleanup_aria2_orphans() {
	if [ "$CLEAN_ALL_ARIA2_TASKS" != "true" ] && [ "$CLEAN_ORPHANED_METADATA" != "true" ]; then
		info "Aria2 cleanup disabled."
		return 0
	fi

	info "Inspecting Aria2 tasks for stale metadata/orphan magnets..."
	fetch_aria2_lists

	python3 - "$TMP_DIR" "$CLEAN_ALL_ARIA2_TASKS" >"$TMP_DIR/gids_to_clean.txt" <<'PY'
import json
import os
import sys

tmp = sys.argv[1]
clean_all = sys.argv[2].lower() == "true"

def load(name):
    path = os.path.join(tmp, name + ".json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        result = data.get("result")
        return result if isinstance(result, list) else []
    except Exception:
        return []

def file_paths(item):
    out = []
    for f in item.get("files") or []:
        p = f.get("path")
        if p:
            out.append(p)
        for u in f.get("uris") or []:
            uri = u.get("uri")
            if uri:
                out.append(uri)
    return out

def is_metadata_orphan(item):
    gid = item.get("gid", "")
    status = item.get("status", "")
    total = str(item.get("totalLength", ""))
    completed = str(item.get("completedLength", ""))
    paths = file_paths(item)
    has_bt = isinstance(item.get("bittorrent"), dict)
    has_metadata_path = any("[METADATA]" in p for p in paths)
    has_magnet_uri = any(p.startswith("magnet:?") for p in paths)

    # The duplicate InfoHash bug is usually caused by a registered zero-byte magnet metadata task.
    zero_size_bt = has_bt and total in ("", "0") and completed in ("", "0")
    no_real_files = has_bt and len(item.get("files") or []) == 0

    # Also clean failed metadata-ish records from stopped list.
    has_error = bool(item.get("errorCode") or item.get("errorMessage"))

    return bool(
        gid and (
            has_metadata_path or
            has_magnet_uri or
            zero_size_bt or
            no_real_files or
            (has_bt and has_error and total in ("", "0"))
        )
    )

for bucket in ("active", "waiting", "stopped"):
    for item in load(bucket):
        gid = item.get("gid")
        if not gid:
            continue
        if clean_all or is_metadata_orphan(item):
            print(bucket, gid)
PY

	if [ ! -s "$TMP_DIR/gids_to_clean.txt" ]; then
		log "No stale Aria2 metadata/orphan tasks found."
		return 0
	fi

	warn "Cleaning these Aria2 tasks/results:"
	sed 's/^/  /' "$TMP_DIR/gids_to_clean.txt"

	while read -r bucket gid; do
		[ -z "${gid:-}" ] && continue

		case "$bucket" in
		active | waiting)
			aria2_rpc "aria2.remove" "\"${gid}\"" >/dev/null || true
			# If it already moved to stopped, remove its result too.
			aria2_rpc "aria2.removeDownloadResult" "\"${gid}\"" >/dev/null || true
			;;
		stopped)
			aria2_rpc "aria2.removeDownloadResult" "\"${gid}\"" >/dev/null || true
			;;
		esac
	done <"$TMP_DIR/gids_to_clean.txt"

	aria2_rpc "aria2.saveSession" >/dev/null || true
	log "Cleaned Aria2 metadata/orphan tasks and saved session."
}

write_report() {
	local shared_uid="$1"
	local shared_gid="$2"
	local server_ip rpc_result ports ps_output session_preview active_preview

	server_ip="$(get_public_ip)"
	rpc_result="$(aria2_rpc "aria2.getVersion")"
	ports="$(docker port aria2 2>/dev/null || true)"
	ps_output="$(docker compose ps 2>/dev/null || true)"
	session_preview="$(ls -l "$DEST/aria2/config/aria2.session" 2>/dev/null || true)"
	active_preview="$(aria2_rpc "aria2.tellActive" '["gid","status","totalLength","completedLength","downloadSpeed","numSeeders","connections","files","bittorrent"]' || true)"

	cat >"$REPORT_FILE" <<EOF
Cloudreve / Aria2 Deployment Info
Generated: $(date -Is)

Cloudreve URL:
  http://${server_ip}:${CLOUDREVE_PORT}

What v5 fixed:
  1. Cloudreve users/settings persistence:
     host:      ${DEST}/cloudreve/data
     container: /cloudreve/data

  2. Shared remote download path:
     host:      ${DEST}/data
     container: /data
     Cloudreve admin "Temporary download directory" must be: /data

  3. Aria2 session persistence:
     host:      ${DEST}/aria2/config
     container: /config
     session:   /config/aria2.session

  4. Duplicate magnet / InfoHash cleanup:
     CLEAN_ORPHANED_METADATA=${CLEAN_ORPHANED_METADATA}
     CLEAN_ALL_ARIA2_TASKS=${CLEAN_ALL_ARIA2_TASKS}
     RESET_ARIA2_SESSION=${RESET_ARIA2_SESSION}

Important:
  If Cloudreve already has failed workflow rows like "GID is not found",
  delete those failed tasks in Cloudreve UI once.
  v5 cleans the Aria2 side so the same magnet can be submitted again.

Cloudreve admin node settings:
  Downloader: aria2
  RPC Server: http://aria2:${ARIA2_RPC_PORT}/
  RPC Token: ${ARIA2_SECRET}
  Temporary download directory: /data
  Downloader job options: leave blank or use {}

Aria2 config highlights:
  input-file=/config/aria2.session
  save-session=/config/aria2.session
  save-session-interval=30
  force-save=true
  continue=true
  always-resume=true
  bt-save-metadata=true
  bt-load-saved-metadata=true

Shared UID:GID:
  ${shared_uid}:${shared_gid}

Firewall / GCP:
  Required:
    tcp:${CLOUDREVE_PORT}
    tcp:${ARIA2_BT_PORT}
    udp:${ARIA2_BT_PORT}
  Optional:
    tcp:${ARIA2_RPC_HOST_PORT}

Safe restart while downloads are active:
  curl -sS http://127.0.0.1:${ARIA2_RPC_HOST_PORT}/jsonrpc \\
    -H 'Content-Type: application/json' \\
    -d '{"jsonrpc":"2.0","id":"save","method":"aria2.saveSession","params":["token:${ARIA2_SECRET}"]}'
  cd ${DEST}
  docker compose stop
  docker compose up -d

Avoid:
  docker compose down -v
  deleting ${DEST}/cloudreve/data
  deleting ${DEST}/data
  deleting ${DEST}/aria2/config/aria2.session

Emergency duplicate-infohash cleanup only:
  cd ${DEST}
  CLEAN_ORPHANED_METADATA=true bash install_cloudreve_v5_fixed.sh

Dangerous full Aria2 task cleanup:
  cd ${DEST}
  CLEAN_ALL_ARIA2_TASKS=true bash install_cloudreve_v5_fixed.sh

Aria2 RPC test:
  ${rpc_result}

Aria2 published ports:
${ports}

Aria2 session file:
  ${session_preview}

Current active Aria2 tasks:
  ${active_preview}

Docker compose status:
${ps_output}

Backups:
  ${BACKUP_DIR}
EOF

	echo ""
	echo "========================================"
	echo " Cloudreve + Aria2 v5 Fixed"
	echo "========================================"
	echo ""
	echo "Cloudreve URL:"
	echo "  http://${server_ip}:${CLOUDREVE_PORT}"
	echo ""
	echo "Cloudreve node settings:"
	echo "  RPC Server: http://aria2:${ARIA2_RPC_PORT}/"
	echo "  RPC Token:  ${ARIA2_SECRET}"
	echo "  Temporary download directory: /data"
	echo "  Downloader job options: blank or {}"
	echo ""
	echo "What to do now:"
	echo "  1. Delete failed Cloudreve workflow tasks in the web UI once."
	echo "  2. Re-add the magnet."
	echo ""
	echo "Info saved to:"
	echo "  ${REPORT_FILE}"
	echo ""
	echo "Backups:"
	echo "  ${BACKUP_DIR}"
	echo ""
	echo "========================================"
}

main() {
	require_cmd docker
	require_cmd curl
	require_cmd python3

	if ! docker compose version >/dev/null 2>&1; then
		err "'docker compose' is not available. Install Docker Compose plugin first."
		exit 1
	fi

	mkdir -p "$DEST" "$TMP_DIR"
	cd "$DEST"

	info "Install directory: $DEST"
	info "Backup directory:  $BACKUP_DIR"

	save_aria2_session_if_running
	preserve_existing_data

	uid_gid="$(detect_cloudreve_uid_gid)"
	shared_uid="${uid_gid%%:*}"
	shared_gid="${uid_gid##*:}"
	info "Selected shared UID:GID = ${shared_uid}:${shared_gid}"

	ensure_aria2_conf
	reset_aria2_session_if_requested

	write_compose "$shared_uid" "$shared_gid"
	fix_permissions "$shared_uid" "$shared_gid"

	info "Starting/reconciling containers without deleting bind-mounted data..."
	docker compose up -d

	sleep 4

	# Re-detect Cloudreve UID/GID after start and align Aria2.
	detected="$(detect_cloudreve_uid_gid)"
	detected_uid="${detected%%:*}"
	detected_gid="${detected##*:}"

	if [ "$detected_uid:$detected_gid" != "$shared_uid:$shared_gid" ]; then
		warn "Cloudreve actual UID:GID is ${detected_uid}:${detected_gid}; updating Aria2 PUID/PGID..."
		shared_uid="$detected_uid"
		shared_gid="$detected_gid"
		write_compose "$shared_uid" "$shared_gid"
		fix_permissions "$shared_uid" "$shared_gid"
		docker compose up -d --force-recreate aria2
		sleep 4
		docker compose up -d
	fi

	# Final permission tests.
	if docker exec cloudreve sh -lc 'mkdir -p /cloudreve/data/temp/aria2/test && touch /cloudreve/data/temp/aria2/test/ok && mkdir -p /data/aria2/cloudreve-test && touch /data/aria2/cloudreve-test/ok' >/dev/null 2>&1; then
		log "Cloudreve can write /cloudreve/data/temp/aria2 and /data/aria2"
	else
		warn "Cloudreve write test failed; applying emergency permissions..."
		chmod -R 777 "$DEST/cloudreve/data" "$DEST/data"
		docker compose restart cloudreve
	fi

	if docker exec aria2 sh -lc 'mkdir -p /data/aria2/aria2-test && touch /data/aria2/aria2-test/ok && touch /config/aria2.session' >/dev/null 2>&1; then
		log "Aria2 can write /data/aria2 and /config/aria2.session"
	else
		warn "Aria2 write test failed; applying emergency permissions..."
		chmod -R 777 "$DEST/data" "$DEST/aria2/config"
		docker compose restart aria2
		sleep 3
	fi

	# Clean stale metadata/orphan tasks AFTER Aria2 is running with fixed config.
	cleanup_aria2_orphans

	# Persist the cleaned/current session.
	aria2_rpc "aria2.saveSession" >/dev/null || true

	write_report "$shared_uid" "$shared_gid"
}

main "$@"
