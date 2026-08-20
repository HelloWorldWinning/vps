#!/usr/bin/env bash
# Install or update SearXNG + Valkey + Caddy behind one published HTTP port.
#
# Default route:
#   host:899 -> caddy:899 -> searxng:8080 -> valkey:6379
#
# Only port 899 is PUBLISHED. Ports shown by `docker compose ps` as 80/tcp,
# 443/tcp, 8080/tcp, or 6379/tcp are image metadata/internal ports and are not
# reachable from the host unless they have a HOST:PORT mapping.
#
# Usage:
#   chmod +x setup_install_899.sh
#   sudo ./setup_install_899.sh
#
# Common overrides:
#   PORT=899 BASE_URL=https://search.example.com/ ./setup_install_899.sh
#   BIND_ADDRESS=127.0.0.1 ./setup_install_899.sh   # local proxy/tunnel only
#   STACK_DIR=/opt/searxng GRANIAN_WORKERS=2 ./setup_install_899.sh

set -Eeuo pipefail
umask 027

SCRIPT_NAME="${0##*/}"
STACK_DIR="${STACK_DIR:-/data/google}"
PORT="${PORT:-899}"
BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0}"
BASE_URL="${BASE_URL:-}"
INSTANCE_NAME="${INSTANCE_NAME:-SearXNG}"
GRANIAN_WORKERS="${GRANIAN_WORKERS:-1}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-120}"
SEARXNG_IMAGE="${SEARXNG_IMAGE:-searxng/searxng:latest}"
VALKEY_IMAGE="${VALKEY_IMAGE:-valkey/valkey:8-alpine}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2-alpine}"
SEARXNG_UID="${SEARXNG_UID:-977}"
SEARXNG_GID="${SEARXNG_GID:-977}"

if [[ -t 1 && "${NO_COLOR:-0}" != 1 ]]; then
	C_GREEN=$'\033[1;32m'
	C_YELLOW=$'\033[1;33m'
	C_RED=$'\033[1;31m'
	C_BLUE=$'\033[1;34m'
	C_RESET=$'\033[0m'
else
	C_GREEN=""
	C_YELLOW=""
	C_RED=""
	C_BLUE=""
	C_RESET=""
fi

log() { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '%s[i]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
	printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
	exit 1
}

on_error() {
	local rc=$? line=${BASH_LINENO[0]:-unknown}
	printf '%s[x]%s %s failed at line %s (exit %s).\n' \
		"$C_RED" "$C_RESET" "$SCRIPT_NAME" "$line" "$rc" >&2
	exit "$rc"
}
trap on_error ERR

backup() {
	local source=$1 stamp target n=0
	[[ -f "$source" ]] || return 0
	stamp=$(date -u +%Y%m%dT%H%M%SZ)
	target="${source}.bak.${stamp}"
	while [[ -e "$target" ]]; do
		n=$((n + 1))
		target="${source}.bak.${stamp}.${n}"
	done
	cp -a -- "$source" "$target"
	log "Backup: $target"
}

valid_ipv4() {
	local ip=$1 part
	local -a parts
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
	IFS=. read -r -a parts <<<"$ip"
	for part in "${parts[@]}"; do ((10#$part <= 255)) || return 1; done
}

fetch_public_ipv4() {
	local endpoint ip
	# Independent services keep installation working if one IP endpoint is down.
	local -a endpoints=(
		"https://api.ipify.org"
		"https://ip.sb"
		"https://ifconfig.me/ip"
		"https://icanhazip.com"
		"https://ipinfo.io/ip"
	)
	for endpoint in "${endpoints[@]}"; do
		ip=""
		if command -v curl >/dev/null 2>&1; then
			ip=$(curl -4 -fsS --connect-timeout 2 --max-time 4 "$endpoint" 2>/dev/null || true)
		elif command -v wget >/dev/null 2>&1; then
			ip=$(wget -4 -q -T 4 -O - "$endpoint" 2>/dev/null || true)
		fi
		ip=${ip//$'\r'/}
		ip=${ip//$'\n'/}
		ip=${ip//[[:space:]]/}
		if valid_ipv4 "$ip"; then
			printf '%s' "$ip"
			return 0
		fi
	done
	return 1
}

choose_base_url() {
	local entered="" public_ip="" local_ip=""
	[[ -z "$BASE_URL" ]] || return 0

	if [[ -t 0 ]]; then
		printf 'Public domain for SearXNG (example: search.example.com).\n'
		printf 'Press Enter or wait 4 seconds to use this server public IP: '
		if IFS= read -r -t 4 entered; then :; fi
		printf '\n'
	fi

	# Trim surrounding whitespace without calling an external program.
	entered="${entered#"${entered%%[![:space:]]*}"}"
	entered="${entered%"${entered##*[![:space:]]}"}"
	if [[ -n "$entered" ]]; then
		if [[ "$entered" =~ ^https?:// ]]; then
			BASE_URL=$entered
		elif valid_ipv4 "${entered%/}"; then
			entered=${entered%/}
			BASE_URL="http://${entered}:${PORT}/"
		else
			entered=${entered%/}
			BASE_URL="https://${entered}/"
		fi
		return 0
	fi

	info "No domain supplied; detecting public IPv4 using multiple providers."
	if public_ip=$(fetch_public_ipv4); then
		BASE_URL="http://${public_ip}:${PORT}/"
		log "Detected public IPv4: $public_ip"
		return 0
	fi

	if command -v ip >/dev/null 2>&1; then
		local_ip=$(ip -4 route get 1.1.1.1 2>/dev/null |
			awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
	fi
	if valid_ipv4 "$local_ip"; then
		BASE_URL="http://${local_ip}:${PORT}/"
		warn "Public-IP services were unreachable; using local address $local_ip."
	else
		BASE_URL="http://127.0.0.1:${PORT}/"
		warn "Could not detect a public or local address; using loopback."
	fi
}

compose() { "${COMPOSE[@]}" "$@"; }

service_health() {
	local cid
	cid=$(compose ps -q "$1" 2>/dev/null | head -n1 || true)
	[[ -n "$cid" ]] || {
		printf 'missing'
		return
	}
	docker inspect --format \
		'{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
		"$cid" 2>/dev/null || printf 'unknown'
}

show_host_info() {
	local os="unknown" kernel cpus memory ipv6
	[[ -r /etc/os-release ]] && os=$(
		. /etc/os-release
		printf '%s' "${PRETTY_NAME:-unknown}"
	)
	kernel=$(uname -srmo 2>/dev/null || uname -a)
	cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '?')
	if command -v free >/dev/null 2>&1; then
		memory=$(free -h | awk '/^Mem:/ {print $2}')
	else
		memory="?"
	fi
	ipv6="available"
	[[ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] &&
		[[ $(</proc/sys/net/ipv6/conf/all/disable_ipv6) == 1 ]] && ipv6="disabled"
	info "OS: $os"
	info "Kernel: $kernel"
	info "Resources: ${cpus} CPU(s), ${memory} RAM; host IPv6: ${ipv6}"
	info "Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || printf 'unknown')"
	info "Compose: $(compose version --short 2>/dev/null || compose version 2>/dev/null | head -n1)"
	if [[ "$ipv6" == disabled ]]; then
		info "IPv6 is disabled; Granian will be forced to IPv4 (0.0.0.0)."
	fi
}

diagnostics() {
	local service
	printf '\n%s[diagnostics]%s\n' "$C_YELLOW" "$C_RESET" >&2
	compose ps -a >&2 || true
	for service in searxng redis caddy; do
		printf '\n--- recent %s logs ---\n' "$service" >&2
		compose logs --no-color --tail=80 "$service" >&2 || true
	done
	printf '\n--- published ports ---\n' >&2
	compose ps --format json 2>/dev/null >&2 || compose ps >&2 || true
	printf '\nRun for live logs: cd %q && ' "$STACK_DIR" >&2
	printf '%q ' "${COMPOSE[@]}" >&2
	printf 'logs -f\n' >&2
}

# Validate user-controlled values before touching the existing stack.
[[ "$PORT" =~ ^[0-9]+$ ]] || die "PORT must be an integer (received: $PORT)."
((PORT >= 1 && PORT <= 65535)) || die "PORT must be between 1 and 65535."
[[ "$GRANIAN_WORKERS" =~ ^[1-9][0-9]*$ ]] || die "GRANIAN_WORKERS must be a positive integer."
[[ "$STARTUP_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "STARTUP_TIMEOUT must be a positive integer."
choose_base_url
[[ "$BIND_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
	die "BIND_ADDRESS must be an IPv4 address, such as 0.0.0.0 or 127.0.0.1."
[[ "$BASE_URL" =~ ^https?://[^[:space:]]+$ ]] ||
	die "BASE_URL must be a complete http:// or https:// URL without spaces."
[[ "$BASE_URL" != *'$'* && "$BASE_URL" != *'#'* ]] ||
	die "BASE_URL must not contain '$' or '#'."
[[ "$INSTANCE_NAME" != *$'\n'* && "$INSTANCE_NAME" != *$'\r'* ]] ||
	die "INSTANCE_NAME must be one line."
[[ "$INSTANCE_NAME" != *'"'* && "$INSTANCE_NAME" != *'\\'* ]] ||
	die "INSTANCE_NAME must not contain a double quote or backslash."
[[ "$STACK_DIR" == /* ]] || die "STACK_DIR must be an absolute path."
[[ "$STACK_DIR" != / && "$STACK_DIR" != /etc && "$STACK_DIR" != /usr ]] ||
	die "Refusing unsafe STACK_DIR: $STACK_DIR"
[[ "$BASE_URL" == */ ]] || {
	BASE_URL="${BASE_URL}/"
	warn "Added trailing slash to BASE_URL."
}

command -v docker >/dev/null 2>&1 || die "Docker is not installed."
docker info >/dev/null 2>&1 || die "Docker daemon is unavailable or this user lacks permission."
if docker compose version >/dev/null 2>&1; then
	COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
	COMPOSE=(docker-compose)
else
	die "Docker Compose is not installed."
fi

show_host_info

if command -v ss >/dev/null 2>&1 &&
	ss -H -ltn "sport = :$PORT" 2>/dev/null | grep -q .; then
	# A running copy of this Compose project is allowed to own the port.
	if ! compose ls --format json 2>/dev/null | grep -Fq "$(basename "$STACK_DIR")"; then
		warn "TCP port $PORT is already listening; startup may fail if another process owns it."
	fi
fi

mkdir -p -- "$STACK_DIR/searxng"
cd -- "$STACK_DIR"

# Preserve sessions across reruns by reusing the current SearXNG secret.
SECRET_KEY=""
if [[ -f searxng/settings.yml ]]; then
	SECRET_KEY=$(sed -nE 's/^[[:space:]]*secret_key:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' \
		searxng/settings.yml | head -n1 || true)
fi
if [[ -z "$SECRET_KEY" ]]; then
	if command -v openssl >/dev/null 2>&1; then
		SECRET_KEY=$(openssl rand -hex 32)
	else
		SECRET_KEY=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
	fi
	log "Generated a new SearXNG secret."
else
	log "Reusing the existing SearXNG secret."
fi

backup .env
backup docker-compose.yml
backup Caddyfile
backup searxng/settings.yml

cat >.env <<EOF
# Managed by $SCRIPT_NAME. Re-run the script to apply override changes.
PORT=$PORT
BIND_ADDRESS=$BIND_ADDRESS
BASE_URL=$BASE_URL
GRANIAN_WORKERS=$GRANIAN_WORKERS
SEARXNG_IMAGE=$SEARXNG_IMAGE
VALKEY_IMAGE=$VALKEY_IMAGE
CADDY_IMAGE=$CADDY_IMAGE
EOF

cat >docker-compose.yml <<'YAML'
services:
  redis:
    image: "${VALKEY_IMAGE}"
    restart: unless-stopped
    command: ["valkey-server", "--save", "30", "1", "--loglevel", "warning"]
    expose:
      - "6379"
    volumes:
      - valkey-data:/data
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 10
      start_period: 5s
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - SETGID
      - SETUID
      - DAC_OVERRIDE
    logging: &default-logging
      driver: json-file
      options:
        max-size: "2m"
        max-file: "3"

  searxng:
    image: "${SEARXNG_IMAGE}"
    restart: unless-stopped
    expose:
      - "8080"
    volumes:
      - ./searxng:/etc/searxng:rw
    environment:
      SEARXNG_BASE_URL: "${BASE_URL}"
      # Current SearXNG images use Granian, not uWSGI. Binding explicitly to
      # IPv4 fixes os error 97 on hosts where the IPv6 family is unavailable.
      GRANIAN_HOST: "0.0.0.0"
      GRANIAN_PORT: "8080"
      GRANIAN_WORKERS: "${GRANIAN_WORKERS}"
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "/usr/local/searxng/.venv/bin/python -c 'import socket; s=socket.create_connection((\"127.0.0.1\",8080),3); s.close()'"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 20s
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
      - DAC_OVERRIDE
      - FOWNER
    logging: *default-logging

  caddy:
    image: "${CADDY_IMAGE}"
    restart: unless-stopped
    ports:
      - "${BIND_ADDRESS}:${PORT}:${PORT}/tcp"
    environment:
      CADDY_PORT: "${PORT}"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      searxng:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:$${CADDY_PORT}/ || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 10s
    security_opt:
      - no-new-privileges:true
    logging: *default-logging

volumes:
  valkey-data:
  caddy-data:
  caddy-config:
YAML

cat >Caddyfile <<'CADDY'
{
  auto_https off
  admin off
}

:{$CADDY_PORT:899} {
  encode zstd gzip
  reverse_proxy searxng:8080
}
CADDY

mkdir -p "${STACK_DIR}/searxng" &&
	wget -O "${STACK_DIR}/searxng/settings.yml" \
		"https://raw.githubusercontent.com/HelloWorldWinning/vps/main/searxng_settings.yml"

chmod 600 .env
chmod 640 searxng/settings.yml
if ((EUID == 0)); then
	chown -R "$SEARXNG_UID:$SEARXNG_GID" searxng
	log "Set SearXNG config ownership to $SEARXNG_UID:$SEARXNG_GID."
else
	warn "Not root; skipped config chown. If SearXNG reports permission errors, run:"
	warn "  sudo chown -R $SEARXNG_UID:$SEARXNG_GID '$STACK_DIR/searxng'"
fi

log "Validating Docker Compose configuration."
compose config --quiet
log "Validating Caddy configuration."
compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

log "Pulling container images."
compose pull
log "Starting the stack."
compose up -d --remove-orphans

log "Waiting up to ${STARTUP_TIMEOUT}s for all services to become healthy."
deadline=$((SECONDS + STARTUP_TIMEOUT))
ready=0
while ((SECONDS < deadline)); do
	redis_status=$(service_health redis)
	searxng_status=$(service_health searxng)
	caddy_status=$(service_health caddy)
	if [[ "$redis_status" == healthy && "$searxng_status" == healthy &&
		"$caddy_status" == healthy ]]; then
		ready=1
		break
	fi
	if [[ "$searxng_status" == restarting || "$searxng_status" == exited ||
		"$searxng_status" == dead ]]; then
		break
	fi
	sleep 3
done

if ((ready == 0)); then
	warn "The stack did not become healthy within ${STARTUP_TIMEOUT}s."
	if compose logs --no-color --tail=200 searxng 2>/dev/null |
		grep -q 'Address family not supported by protocol'; then
		warn "Granian still reports os error 97. Confirm the container received GRANIAN_HOST=0.0.0.0:"
		warn "  cd '$STACK_DIR' && $(printf '%q ' "${COMPOSE[@]}")exec searxng env | grep GRANIAN"
	fi
	diagnostics
	exit 1
fi

HTTP_CODE=""
CHECK_HOST=127.0.0.1
[[ "$BIND_ADDRESS" != 0.0.0.0 ]] && CHECK_HOST=$BIND_ADDRESS
if command -v curl >/dev/null 2>&1; then
	HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
		"http://${CHECK_HOST}:${PORT}/" 2>/dev/null || true)
elif command -v wget >/dev/null 2>&1; then
	wget -q -O /dev/null -T 10 "http://${CHECK_HOST}:${PORT}/" && HTTP_CODE=200 || true
fi

printf '\n'
compose ps
printf '\n'
log "Installation completed successfully."
info "Checked endpoint: http://${CHECK_HOST}:$PORT/ (HTTP ${HTTP_CODE:-not tested})"
info "Public URL:      $BASE_URL"
info "Published port:  $BIND_ADDRESS:$PORT/tcp (the only host mapping)"
info "Internal only:   searxng:8080, redis:6379"
info "Stack directory: $STACK_DIR"
info "Granian:         IPv4 0.0.0.0:8080, $GRANIAN_WORKERS worker(s)"
info "Web sources:     defaults + Google, Bing, Mojeek, Qwant, Yahoo, Yep"

cat <<EOF

TLS is not terminated by this stack. Configure your existing tunnel or reverse
proxy to forward to http://<this-host-ip>:$PORT . If it runs on this same host,
rerun with BIND_ADDRESS=127.0.0.1 to avoid exposing the port on every interface.

Useful commands:
  cd "$STACK_DIR"
  $(printf '%q ' "${COMPOSE[@]}")ps
  $(printf '%q ' "${COMPOSE[@]}")logs -f
  $(printf '%q ' "${COMPOSE[@]}")logs --tail=100 searxng
  $(printf '%q ' "${COMPOSE[@]}")restart searxng
  $(printf '%q ' "${COMPOSE[@]}")down
EOF
