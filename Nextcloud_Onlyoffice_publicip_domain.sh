#!/usr/bin/env bash
#===============================================================================
#  Nextcloud + ONLYOFFICE Docs Manager
#  -----------------------------------
#  Lightweight Docker Compose manager for:
#    - Nextcloud official Docker image
#    - MariaDB
#    - Redis
#    - ONLYOFFICE Docs Community Edition
#    - Nginx TLS reverse proxy on host port 7443 only
#
#  Default base directory : /data/Nextcloud_Onlyoffice_D
#  Compose file           : /data/Nextcloud_Onlyoffice_D/docker-compose.yml
#  Environment file       : /data/Nextcloud_Onlyoffice_D/.env
#  Public URL             : https://PUBLIC_IP_OR_DOMAIN:7443
#
#  Design goals:
#    - No host port 80 and no host port 443.
#    - Self-generated TLS certificate stored under BASE_DIR/proxy/certs.
#    - Every stack data path is under BASE_DIR for easier migration.
#    - ONLYOFFICE Docs is not published separately; it is proxied at /editors/.
#    - Running the script without arguments opens an interactive menu.
#===============================================================================

set -Eeuo pipefail

#--- Constants -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/data/Nextcloud_Onlyoffice_D}"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
ENV_FILE="${BASE_DIR}/.env"
LOG_DIR="${BASE_DIR}/logs"
BACKUP_DIR="${BASE_DIR}/backups"

NEXTCLOUD_DIR="${BASE_DIR}/nextcloud"
NEXTCLOUD_HTML_DIR="${NEXTCLOUD_DIR}/html"
NEXTCLOUD_PHP_DIR="${NEXTCLOUD_DIR}/php"

DB_DIR="${BASE_DIR}/mariadb"
REDIS_DIR="${BASE_DIR}/redis"
ONLYOFFICE_DIR="${BASE_DIR}/onlyoffice"
PROXY_DIR="${BASE_DIR}/proxy"
CERT_DIR="${PROXY_DIR}/certs"
NGINX_DIR="${PROXY_DIR}/conf.d"

HTTPS_PORT="${HTTPS_PORT:-7443}"
TZ_DEFAULT="Asia/Tokyo"

# Prompt for HTTPS_PORT with 7s timeout, default 7443
read -t 7 -p "Enter HTTPS_PORT [default: 7443]: " INPUT_PORT
HTTPS_PORT="${INPUT_PORT:-7443}"

# Auto-detect current system timezone (skip unreliable /etc/timezone)
TZ_DEFAULT="$(timedatectl show --property=Timezone --value 2>/dev/null ||
	readlink -f /etc/localtime | sed 's|.*/zoneinfo/||' ||
	echo 'UTC')"

PROJECT_NAME="nextcloud_onlyoffice"
NC_CONTAINER="nextcloud-onlyoffice-nextcloud"
DB_CONTAINER="nextcloud-onlyoffice-mariadb"
REDIS_CONTAINER="nextcloud-onlyoffice-redis"
OO_CONTAINER="nextcloud-onlyoffice-onlyoffice"
PROXY_CONTAINER="nextcloud-onlyoffice-proxy"

SCRIPT_VERSION="2026-05-03.3-publicip-domain"
MIN_DOCKER_FREE_GIB="${MIN_DOCKER_FREE_GIB:-10}"
MIN_BASE_FREE_GIB="${MIN_BASE_FREE_GIB:-5}"

#--- Colors --------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	CYAN='\033[0;36m'
	BOLD='\033[1m'
	NC_COLOR='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	BLUE=''
	CYAN=''
	BOLD=''
	NC_COLOR=''
fi

#--- Output helpers ------------------------------------------------------------
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
ensure_log_dir() { mkdir -p "${LOG_DIR}" 2>/dev/null || true; }
log() {
	ensure_log_dir
	printf '[%s] %s\n' "$(timestamp)" "$*" >>"${LOG_DIR}/manager.log" 2>/dev/null || true
}
info() {
	printf '%b\n' "${BLUE}[INFO]${NC_COLOR}    $*"
	log "INFO: $*"
}
success() {
	printf '%b\n' "${GREEN}[OK]${NC_COLOR}      $*"
	log "OK: $*"
}
warn() {
	printf '%b\n' "${YELLOW}[WARN]${NC_COLOR}    $*"
	log "WARN: $*"
}
error() {
	printf '%b\n' "${RED}[ERROR]${NC_COLOR}   $*" >&2
	log "ERROR: $*"
}
header() { printf '\n%b\n\n' "${BOLD}${CYAN}━━━ $* ━━━${NC_COLOR}"; }
fatal() {
	error "$*"
	exit 1
}

on_err() {
	local line="$1"
	local cmd="$2"
	error "Command failed at line ${line}: ${cmd}"
	error "Run: sudo $0 status"
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

#--- Small helpers -------------------------------------------------------------
command_exists() { command -v "$1" >/dev/null 2>&1; }
is_tty() { [[ -t 0 && -t 1 ]]; }
require_root() { [[ ${EUID} -eq 0 ]] || fatal "Run as root: sudo $0 $*"; }

pause_return() {
	is_tty || return 0
	echo ""
	read -r -p "Press Enter to continue..." _ || true
}

confirm() {
	local prompt="${1:-Continue?}"
	local answer=""
	is_tty || return 1
	printf '%b' "${YELLOW}${prompt} [y/N]: ${NC_COLOR}"
	read -r answer || true
	[[ "${answer}" =~ ^[Yy]$ ]]
}

prompt_value() {
	local prompt="$1"
	local default_value="${2:-}"
	local answer=""
	if [[ -n "${default_value}" ]]; then
		read -r -p "${prompt} [${default_value}]: " answer || true
		printf '%s' "${answer:-${default_value}}"
	else
		read -r -p "${prompt}: " answer || true
		printf '%s' "${answer}"
	fi
}

compose_available() {
	docker compose version >/dev/null 2>&1 || command_exists docker-compose
}

compose_cmd() {
	if docker compose version >/dev/null 2>&1; then
		docker compose -f "${COMPOSE_FILE}" "$@"
	else
		docker-compose -f "${COMPOSE_FILE}" "$@"
	fi
}

container_running() {
	docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$1"
}

container_exists() {
	docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq "$1"
}

primary_local_ip() {
	hostname -I 2>/dev/null | awk '{print $1}' | grep -E '^[0-9A-Fa-f:.]+$' || printf '127.0.0.1'
}

normalize_host() {
	local h="${1:-}"
	h="${h#http://}"
	h="${h#https://}"
	h="${h%%/*}"
	# Strip :PORT for IPv4/domain hostnames. IPv6 literals should be supplied without brackets for certificate SAN use.
	if [[ "${h}" =~ ^([^:]+):[0-9]+$ ]]; then
		h="${BASH_REMATCH[1]}"
	fi
	printf '%s' "${h}"
}

valid_host_value() {
	local h="$1"
	[[ -n "${h}" ]] || return 1
	[[ ! "${h}" =~ [[:space:]/] ]] || return 1
}

host_is_ip() {
	local h="$1"
	[[ "${h}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "${h}" =~ ^[0-9A-Fa-f:]+$ ]]
}

host_is_ipv4() {
	local h="$1"
	local o1 o2 o3 o4
	[[ "${h}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
	o1="${BASH_REMATCH[1]}"
	o2="${BASH_REMATCH[2]}"
	o3="${BASH_REMATCH[3]}"
	o4="${BASH_REMATCH[4]}"
	((o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255))
}

fetch_url_quiet() {
	local url="$1"
	if command_exists curl; then
		curl -4 -fsSL --connect-timeout 3 --max-time 6 "${url}" 2>/dev/null ||
			curl -fsSL --connect-timeout 3 --max-time 6 "${url}" 2>/dev/null || true
	elif command_exists wget; then
		wget -4 -qO- --timeout=6 "${url}" 2>/dev/null ||
			wget -qO- --timeout=6 "${url}" 2>/dev/null || true
	else
		return 1
	fi
}

clean_ip_candidate() {
	local value="${1:-}"
	value="$(printf '%s' "${value}" | tr -d '\r\n\t ' | head -c 128)"
	value="$(normalize_host "${value}")"
	printf '%s' "${value}"
}

detect_public_ip() {
	local candidate=""
	local url=""
	local urls=(
		"https://api.ip.sb/ip"
		"https://ip.sb"
		"https://api.ipify.org"
		"https://ipv4.icanhazip.com"
		"https://ifconfig.me/ip"
		"https://checkip.amazonaws.com"
	)

	for url in "${urls[@]}"; do
		candidate="$(clean_ip_candidate "$(fetch_url_quiet "${url}")")"
		if valid_host_value "${candidate}" && host_is_ipv4 "${candidate}"; then
			printf '%s' "${candidate}"
			return 0
		fi
	done

	# Cloudflare trace returns key=value lines; parse the ip= field as an extra fallback.
	candidate="$(fetch_url_quiet "https://1.1.1.1/cdn-cgi/trace" | awk -F= '$1 == "ip" {print $2; exit}')"
	candidate="$(clean_ip_candidate "${candidate}")"
	if valid_host_value "${candidate}" && host_is_ipv4 "${candidate}"; then
		printf '%s' "${candidate}"
		return 0
	fi

	return 1
}

preferred_access_host() {
	local public_ip=""
	public_ip="$(detect_public_ip || true)"
	if [[ -n "${public_ip}" ]]; then
		printf '%s' "${public_ip}"
	else
		primary_local_ip
	fi
}

resolve_domain_ipv4s() {
	local domain="$1"
	local found=""

	# Prefer libc/NSS resolution first, because it matches what most host software uses.
	if command_exists getent; then
		found="$(getent ahostsv4 "${domain}" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u || true)"
		if [[ -n "${found}" ]]; then
			printf '%s\n' "${found}"
			return 0
		fi
	fi

	if command_exists dig; then
		found="$(dig +short A "${domain}" 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u || true)"
		if [[ -n "${found}" ]]; then
			printf '%s\n' "${found}"
			return 0
		fi
	fi

	if command_exists host; then
		found="$(host -t A "${domain}" 2>/dev/null | awk '/ has address / {print $NF}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u || true)"
		if [[ -n "${found}" ]]; then
			printf '%s\n' "${found}"
			return 0
		fi
	fi

	if command_exists nslookup; then
		found="$(nslookup -type=A "${domain}" 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u || true)"
		if [[ -n "${found}" ]]; then
			printf '%s\n' "${found}"
			return 0
		fi
	fi

	return 1
}

valid_domain_name() {
	local domain="$1"
	[[ -n "${domain}" ]] || return 1
	[[ ${#domain} -le 253 ]] || return 1
	[[ "${domain}" == *.* ]] || return 1
	[[ ! "${domain}" =~ [[:space:]/_:] ]] || return 1
	[[ "${domain}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
	[[ ! "${domain}" =~ ^- ]] || return 1
	[[ ! "${domain}" =~ -$ ]] || return 1
	[[ ! "${domain}" =~ \.\. ]] || return 1
}

verify_domain_points_to_public_ip() {
	local domain="$1"
	local public_ip="$2"
	local resolved_ips=""

	[[ -n "${public_ip}" ]] || fatal "Cannot verify domain '${domain}' because public IPv4 detection failed."
	host_is_ipv4 "${public_ip}" || fatal "Detected public IP '${public_ip}' is not a valid IPv4 address."
	valid_domain_name "${domain}" || fatal "Invalid domain '${domain}'. Enter a plain domain like cloud.example.com, without scheme/path/port."

	resolved_ips="$(resolve_domain_ipv4s "${domain}" || true)"
	if [[ -z "${resolved_ips}" ]]; then
		fatal "Domain '${domain}' does not currently resolve to any IPv4 A record. Point it to ${public_ip}, wait for DNS propagation, then rerun."
	fi

	if printf '%s\n' "${resolved_ips}" | grep -Fxq "${public_ip}"; then
		success "DNS check passed: ${domain} resolves to ${public_ip}."
		return 0
	fi

	error "DNS check failed for domain '${domain}'."
	error "Detected server public IP : ${public_ip}"
	error "Domain currently resolves to:"
	printf '%s\n' "${resolved_ips}" | sed 's/^/  - /' >&2
	fatal "Fix the domain A record so it points to ${public_ip}, then rerun."
}

prompt_domain_or_public_ip() {
	local public_ip="$1"
	local fallback_host="$2"
	local answer=""
	local host=""

	# This function is often called inside command substitution so stdout is a pipe.
	# Check stdin only; prompts are printed to stderr and the selected host is printed to stdout.
	if [[ ! -t 0 ]]; then
		printf '%s' "${fallback_host}"
		return 0
	fi

	echo "" >&2
	info "Detected public IPv4: ${public_ip:-<not detected>}" >&2
	printf '%b' "${YELLOW}Optional domain for this server [Enter or 7s timeout = use ${fallback_host}]: ${NC_COLOR}" >&2
	if read -r -t 7 answer; then
		host="${answer}"
	else
		echo "" >&2
		host=""
	fi

	host="$(normalize_host "${host}")"
	if [[ -z "${host}" ]]; then
		host="${fallback_host}"
		info "No domain entered. Using public IP: ${host}" >&2
	else
		info "Domain entered: ${host}" >&2
	fi

	printf '%s' "${host}"
}

random_hex() {
	local bytes="${1:-32}"
	if command_exists openssl; then
		openssl rand -hex "${bytes}"
	else
		tr -dc 'A-Fa-f0-9' </dev/urandom | head -c $((bytes * 2))
	fi
}

set_env_key() {
	local key="$1"
	local value="$2"
	local tmp="${ENV_FILE}.tmp.$$"
	mkdir -p "${BASE_DIR}"
	touch "${ENV_FILE}"
	awk -v k="${key}" -v v="${value}" '
    BEGIN { done=0 }
    $0 ~ "^" k "=" { print k "=" v; done=1; next }
    { print }
    END { if (done == 0) print k "=" v }
  ' "${ENV_FILE}" >"${tmp}"
	mv "${tmp}" "${ENV_FILE}"
}

load_env() {
	[[ -f "${ENV_FILE}" ]] || fatal "Missing ${ENV_FILE}. Run install first."
	set -a
	# shellcheck disable=SC1090
	. "${ENV_FILE}"
	set +a
	HTTPS_PORT="${HTTPS_PORT:-7443}"
}

bytes_to_gib() {
	awk -v b="${1:-0}" 'BEGIN { printf "%.1f", b / 1024 / 1024 / 1024 }'
}

path_avail_bytes() {
	local path="$1"
	mkdir -p "${path}" 2>/dev/null || true
	df -Pk "${path}" 2>/dev/null | awk 'NR==2 {print $4 * 1024}'
}

path_total_bytes() {
	local path="$1"
	mkdir -p "${path}" 2>/dev/null || true
	df -Pk "${path}" 2>/dev/null | awk 'NR==2 {print $2 * 1024}'
}

have_at_least_gib() {
	local path="$1"
	local min_gib="$2"
	local avail=""
	avail="$(path_avail_bytes "${path}" || echo 0)"
	awk -v a="${avail:-0}" -v m="${min_gib}" 'BEGIN { exit !(a >= m * 1024 * 1024 * 1024) }'
}

docker_root_dir() {
	docker info -f '{{.DockerRootDir}}' 2>/dev/null || printf '/var/lib/docker'
}

containerd_root_guess() {
	if [[ -d /var/lib/containerd ]]; then
		printf '/var/lib/containerd'
	else
		printf ''
	fi
}

print_path_space() {
	local label="$1"
	local path="$2"
	local avail="0"
	local total="0"
	mkdir -p "${path}" 2>/dev/null || true
	avail="$(path_avail_bytes "${path}" || echo 0)"
	total="$(path_total_bytes "${path}" || echo 0)"
	printf '  %-24s %-32s total=%6s GiB  free=%6s GiB\n' "${label}:" "${path}" "$(bytes_to_gib "${total}")" "$(bytes_to_gib "${avail}")"
}

docker_space_report() {
	header "Docker / Disk Space Report"
	local docker_root=""
	local containerd_root=""
	docker_root="$(docker_root_dir 2>/dev/null || true)"
	containerd_root="$(containerd_root_guess)"

	echo "${BOLD}Filesystem free space:${NC_COLOR}"
	print_path_space "BASE_DIR" "${BASE_DIR}"
	if [[ -n "${docker_root}" ]]; then
		print_path_space "Docker root" "${docker_root}"
	fi
	if [[ -n "${containerd_root}" ]]; then
		print_path_space "containerd root" "${containerd_root}"
	fi
	echo ""
	echo "${BOLD}Docker disk usage:${NC_COLOR}"
	docker system df 2>/dev/null | sed 's/^/  /' || warn "Could not read docker system df."
	echo ""
	echo "${BOLD}Large directories:${NC_COLOR}"
	du -sh "${BASE_DIR}" 2>/dev/null | sed 's/^/  /' || true
	du -sh "${docker_root}" 2>/dev/null | sed 's/^/  /' || true
	if [[ -n "${containerd_root}" ]]; then
		du -sh "${containerd_root}" 2>/dev/null | sed 's/^/  /' || true
	fi
}

safe_docker_prune() {
	require_root
	header "Docker Cleanup"
	warn "This removes unused containers, networks, images, and build cache. It does not remove Docker volumes."
	confirm "Run docker system prune -af and docker builder prune -af now?" || return 0
	docker system prune -af || true
	docker builder prune -af || true
	success "Docker cleanup finished."
	docker_space_report
}

write_json_key_python() {
	local file="$1"
	local key="$2"
	local value="$3"
	command_exists python3 || return 1
	python3 - "$file" "$key" "$value" <<'PY'
import json
import os
import sys
path, key, value = sys.argv[1:4]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
data[key] = value
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
}

configure_docker_data_root() {
	require_root
	header "Move Docker Data Root Under BASE_DIR"
	local current=""
	local target="${BASE_DIR}/docker-data"
	local daemon_json="/etc/docker/daemon.json"
	current="$(docker_root_dir 2>/dev/null || true)"

	echo "Current DockerRootDir : ${current:-<unknown>}"
	echo "Target DockerRootDir  : ${target}"
	echo ""
	warn "This affects Docker globally on this server, not only Nextcloud. Existing containers will be stopped while Docker restarts."
	warn "This does not move /var/lib/containerd on systems where Docker uses the system containerd root. If your pull error is under /var/lib/containerd, you may still need more root-disk space or containerd reconfiguration."

	[[ -n "${current}" ]] || fatal "Could not detect DockerRootDir."
	if [[ "${current}" == "${target}" ]]; then
		success "Docker already uses ${target}."
		return 0
	fi
	confirm "Continue and configure Docker data-root=${target}?" || return 0

	mkdir -p "${target}"
	if [[ -d "${current}" ]] && [[ -z "$(find "${target}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]]; then
		info "Copying existing Docker data from ${current} to ${target}. This can take time."
		if command_exists rsync; then
			rsync -aHAX --numeric-ids "${current}/" "${target}/"
		else
			cp -a "${current}/." "${target}/"
		fi
	fi

	mkdir -p /etc/docker
	if [[ -f "${daemon_json}" ]]; then
		cp -a "${daemon_json}" "${daemon_json}.bak.$(date '+%Y%m%d-%H%M%S')"
	fi

	if ! write_json_key_python "${daemon_json}" "data-root" "${target}"; then
		if [[ -s "${daemon_json}" ]]; then
			fatal "python3 is required to safely update existing ${daemon_json}. Install python3 or edit it manually."
		fi
		cat >"${daemon_json}" <<EOF
{
  "data-root": "${target}"
}
EOF
	fi

	info "Restarting Docker..."
	systemctl stop docker 2>/dev/null || true
	systemctl stop containerd 2>/dev/null || true
	systemctl start containerd 2>/dev/null || true
	systemctl start docker

	success "Docker restarted. New DockerRootDir: $(docker_root_dir 2>/dev/null || echo '<unknown>')"
	docker_space_report
}

storage_menu() {
	if ! is_tty; then
		docker_space_report
		return 0
	fi
	while true; do
		header "Storage / Pull Failure Helper"
		echo "1) Show Docker and filesystem space"
		echo "2) Clean unused Docker images/containers/build cache, keep volumes"
		echo "3) Configure Docker data-root under ${BASE_DIR}/docker-data"
		echo "0) Back"
		echo ""
		read -r -p "Choice: " choice || true
		case "${choice}" in
		1)
			docker_space_report
			pause_return
			;;
		2)
			safe_docker_prune
			pause_return
			;;
		3)
			configure_docker_data_root
			pause_return
			;;
		0 | q | Q) return 0 ;;
		*)
			warn "Invalid choice."
			pause_return
			;;
		esac
	done
}

check_disk_space_or_fix() {
	local need_docker="${MIN_DOCKER_FREE_GIB}"
	local need_base="${MIN_BASE_FREE_GIB}"
	local docker_root=""
	local containerd_root=""
	local bad="no"

	docker_root="$(docker_root_dir 2>/dev/null || true)"
	containerd_root="$(containerd_root_guess)"

	if ! have_at_least_gib "${BASE_DIR}" "${need_base}"; then
		warn "BASE_DIR filesystem has less than ${need_base} GiB free."
		bad="yes"
	fi
	if [[ -n "${docker_root}" ]] && ! have_at_least_gib "${docker_root}" "${need_docker}"; then
		warn "Docker root filesystem has less than ${need_docker} GiB free: ${docker_root}"
		bad="yes"
	fi
	if [[ -n "${containerd_root}" ]] && ! have_at_least_gib "${containerd_root}" "${need_docker}"; then
		warn "containerd root filesystem has less than ${need_docker} GiB free: ${containerd_root}"
		warn "Your previous failure was exactly this kind of issue: image layer extraction ran out of space."
		bad="yes"
	fi

	if [[ "${bad}" != "yes" ]]; then
		success "Disk-space check passed."
		return 0
	fi

	docker_space_report
	if is_tty; then
		echo ""
		warn "The stack needs space for large image extraction, especially ONLYOFFICE. Free at least ${need_docker} GiB where Docker/containerd stores layers."
		if confirm "Open the storage helper now?"; then
			storage_menu
		fi
		docker_root="$(docker_root_dir 2>/dev/null || true)"
		containerd_root="$(containerd_root_guess)"
		if have_at_least_gib "${BASE_DIR}" "${need_base}" &&
			{ [[ -z "${docker_root}" ]] || have_at_least_gib "${docker_root}" "${need_docker}"; } &&
			{ [[ -z "${containerd_root}" ]] || have_at_least_gib "${containerd_root}" "${need_docker}"; }; then
			success "Disk-space check passed after cleanup/reconfiguration."
			return 0
		fi
	fi

	fatal "Not enough Docker/containerd disk space for image pull. Free space, then rerun install."
}

pull_images() {
	info "Pulling images..."
	if compose_cmd pull; then
		success "Images pulled."
		return 0
	fi

	warn "Image pull failed. Checking for common storage problem..."
	docker_space_report || true
	if is_tty; then
		echo ""
		warn "If you see 'no space left on device', use option 2 to prune unused Docker data, or option 3 to move Docker data-root."
		if confirm "Open storage helper now?"; then
			storage_menu
			info "Retrying image pull..."
			compose_cmd pull
			success "Images pulled after retry."
			return 0
		fi
	fi
	fatal "Image pull failed. Fix Docker/containerd storage and rerun install/update."
}

#--- Initialization ------------------------------------------------------------
init_dirs() {
	mkdir -p \
		"${BASE_DIR}" "${LOG_DIR}" "${BACKUP_DIR}" \
		"${NEXTCLOUD_HTML_DIR}" "${NEXTCLOUD_PHP_DIR}" \
		"${DB_DIR}" "${REDIS_DIR}" \
		"${ONLYOFFICE_DIR}/logs" "${ONLYOFFICE_DIR}/data" "${ONLYOFFICE_DIR}/lib" "${ONLYOFFICE_DIR}/db" \
		"${CERT_DIR}" "${NGINX_DIR}"
	success "Directory structure ready under ${BASE_DIR}"
}

choose_access_host() {
	local supplied_host="${1:-}"
	local host=""
	local public_ip=""
	local fallback_host=""

	supplied_host="$(normalize_host "${supplied_host}")"
	public_ip="$(detect_public_ip || true)"
	fallback_host="${public_ip:-$(primary_local_ip)}"

	if [[ -n "${supplied_host}" ]]; then
		valid_host_value "${supplied_host}" || fatal "Invalid host '${supplied_host}'. Use only an IP/domain, without scheme/path."
		host="${supplied_host}"
	else
		host="$(prompt_domain_or_public_ip "${public_ip}" "${fallback_host}")"
	fi

	host="$(normalize_host "${host}")"
	valid_host_value "${host}" || fatal "Invalid host '${host}'. Use only an IP/domain, without scheme/path."

	if host_is_ip "${host}"; then
		printf '%s' "${host}"
		return 0
	fi

	verify_domain_points_to_public_ip "${host}" "${public_ip}" >&2
	printf '%s' "${host}"
}

config_init() {
	local supplied_host="${1:-}"
	local host=""

	supplied_host="$(normalize_host "${supplied_host}")"
	if [[ -n "${supplied_host}" ]]; then
		valid_host_value "${supplied_host}" || fatal "Invalid host '${supplied_host}'. Use only an IP/domain, without scheme/path."
	fi

	if [[ ! -f "${ENV_FILE}" ]]; then
		host="${supplied_host:-$(preferred_access_host)}"
		cat >"${ENV_FILE}" <<EOF
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
BASE_DIR=${BASE_DIR}
HTTPS_PORT=${HTTPS_PORT}
ACCESS_HOST=${host}
TZ=${TZ_DEFAULT}

NEXTCLOUD_IMAGE=nextcloud:stable-apache
MARIADB_IMAGE=mariadb:10.11
REDIS_IMAGE=redis:7-alpine
ONLYOFFICE_IMAGE=onlyoffice/documentserver:latest
NGINX_IMAGE=nginx:alpine

MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=$(random_hex 24)
MYSQL_ROOT_PASSWORD=$(random_hex 24)
REDIS_PASSWORD=$(random_hex 24)
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=$(random_hex 16)
ONLYOFFICE_JWT_SECRET=$(random_hex 32)
EOF
		chmod 600 "${ENV_FILE}"
		success "Created ${ENV_FILE}"
	else
		chmod 600 "${ENV_FILE}" || true
		if [[ -n "${supplied_host}" ]]; then
			set_env_key "ACCESS_HOST" "${supplied_host}"
			success "Updated ACCESS_HOST=${supplied_host} in ${ENV_FILE}"
		fi
	fi

	load_env
}

write_php_ini() {
	cat >"${NEXTCLOUD_PHP_DIR}/zz-nextcloud.ini" <<'EOF'
upload_max_filesize=16G
post_max_size=16G
memory_limit=1024M
max_execution_time=3600
max_input_time=3600
opcache.enable=1
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.memory_consumption=256
opcache.save_comments=1
opcache.revalidate_freq=60
EOF
	success "Wrote PHP tuning file: ${NEXTCLOUD_PHP_DIR}/zz-nextcloud.ini"
}

generate_tls() {
	local host="${1:-${ACCESS_HOST:-$(preferred_access_host)}}"
	local force="${2:-no}"
	local cert="${CERT_DIR}/fullchain.pem"
	local key="${CERT_DIR}/privkey.pem"
	local conf="${CERT_DIR}/openssl-san.cnf"
	local local_ip=""
	local public_ip=""
	local san=""

	mkdir -p "${CERT_DIR}"

	if [[ -s "${cert}" && -s "${key}" && "${force}" != "yes" ]]; then
		info "TLS certificate already exists: ${cert}"
		return 0
	fi

	command_exists openssl || fatal "openssl is required to generate self-signed TLS files. Install openssl first."

	local_ip="$(primary_local_ip)"
	public_ip="$(detect_public_ip || true)"
	if host_is_ip "${host}"; then
		san="IP:${host},DNS:localhost,IP:127.0.0.1,DNS:proxy"
	else
		san="DNS:${host},DNS:localhost,IP:127.0.0.1,DNS:proxy"
	fi
	if [[ -n "${local_ip}" && "${local_ip}" != "${host}" && "${local_ip}" != "127.0.0.1" ]]; then
		san="${san},IP:${local_ip}"
	fi
	if [[ -n "${public_ip}" && "${public_ip}" != "${host}" && "${public_ip}" != "${local_ip}" ]]; then
		san="${san},IP:${public_ip}"
	fi

	cat >"${conf}" <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = ${host}

[v3_req]
subjectAltName = ${san}
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
basicConstraints = critical, CA:FALSE
EOF

	openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
		-keyout "${key}" \
		-out "${cert}" \
		-config "${conf}" >/dev/null 2>&1

	chmod 600 "${key}"
	chmod 644 "${cert}"
	success "Generated self-signed TLS files for ${host}: ${CERT_DIR}"
}

write_nginx_conf() {
	cat >"${NGINX_DIR}/default.conf" <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream nextcloud_backend {
    server nextcloud:80;
}

upstream onlyoffice_backend {
    server onlyoffice:80;
}

server {
    listen 80;
    server_name _;
    client_max_body_size 0;

    location = /.well-known/carddav { return 301 /remote.php/dav/; }
    location = /.well-known/caldav  { return 301 /remote.php/dav/; }
    location = /editors { return 301 /editors/; }

    location ^~ /editors/ {
        proxy_pass http://onlyoffice_backend/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host/editors;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    location / {
        proxy_pass http://nextcloud_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_request_buffering off;
        proxy_buffering off;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name _;

    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    client_max_body_size 0;
    proxy_max_temp_file_size 0;

    add_header Strict-Transport-Security "max-age=15552000" always;

    location = /.well-known/carddav { return 301 /remote.php/dav/; }
    location = /.well-known/caldav  { return 301 /remote.php/dav/; }
    location = /editors { return 301 /editors/; }

    location ^~ /editors/ {
        proxy_pass http://onlyoffice_backend/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $http_host/editors;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    location / {
        proxy_pass http://nextcloud_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_request_buffering off;
        proxy_buffering off;
    }
}
EOF
	success "Wrote Nginx reverse-proxy config: ${NGINX_DIR}/default.conf"
}

write_compose() {
	load_env
	local local_ip=""
	local public_ip=""
	local trusted_domains=""
	local_ip="$(primary_local_ip)"
	public_ip="$(detect_public_ip || true)"
	trusted_domains="${ACCESS_HOST} ${ACCESS_HOST}:${HTTPS_PORT} ${local_ip} ${local_ip}:${HTTPS_PORT}"
	if [[ -n "${public_ip}" && "${public_ip}" != "${ACCESS_HOST}" && "${public_ip}" != "${local_ip}" ]]; then
		trusted_domains="${trusted_domains} ${public_ip} ${public_ip}:${HTTPS_PORT}"
	fi
	trusted_domains="${trusted_domains} localhost proxy nextcloud"

	cat >"${COMPOSE_FILE}" <<COMPOSE
# Nextcloud + ONLYOFFICE Docs - generated by Nextcloud_Onlyoffice_publicip_domain.sh ${SCRIPT_VERSION}
# All persistent stack paths are under: ${BASE_DIR}
# Public entrypoint: https://${ACCESS_HOST}:${HTTPS_PORT}
# Host ports used: ${HTTPS_PORT}/tcp only. Host 80 and 443 are intentionally unused.

services:
  mariadb:
    image: ${MARIADB_IMAGE}
    container_name: ${DB_CONTAINER}
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
      MYSQL_DATABASE: "${MYSQL_DATABASE}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
      TZ: "${TZ}"
    volumes:
      - "${DB_DIR}:/var/lib/mysql"
    networks:
      - ncnet

  redis:
    image: ${REDIS_IMAGE}
    container_name: ${REDIS_CONTAINER}
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass "${REDIS_PASSWORD}"
    volumes:
      - "${REDIS_DIR}:/data"
    networks:
      - ncnet

  nextcloud:
    image: ${NEXTCLOUD_IMAGE}
    container_name: ${NC_CONTAINER}
    restart: unless-stopped
    depends_on:
      - mariadb
      - redis
    environment:
      MYSQL_DATABASE: "${MYSQL_DATABASE}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
      MYSQL_HOST: "mariadb"
      NEXTCLOUD_ADMIN_USER: "${NEXTCLOUD_ADMIN_USER}"
      NEXTCLOUD_ADMIN_PASSWORD: "${NEXTCLOUD_ADMIN_PASSWORD}"
      NEXTCLOUD_TRUSTED_DOMAINS: "${trusted_domains}"
      TRUSTED_PROXIES: "172.16.0.0/12"
      OVERWRITEHOST: "${ACCESS_HOST}:${HTTPS_PORT}"
      OVERWRITEPROTOCOL: "https"
      OVERWRITECLIURL: "https://${ACCESS_HOST}:${HTTPS_PORT}"
      REDIS_HOST: "redis"
      REDIS_HOST_PASSWORD: "${REDIS_PASSWORD}"
      PHP_UPLOAD_LIMIT: "16G"
      PHP_MEMORY_LIMIT: "1024M"
      APACHE_BODY_LIMIT: "0"
      NEXTCLOUD_INIT_HTACCESS: "true"
      TZ: "${TZ}"
    volumes:
      - "${NEXTCLOUD_HTML_DIR}:/var/www/html"
      - "${NEXTCLOUD_PHP_DIR}/zz-nextcloud.ini:/usr/local/etc/php/conf.d/zz-nextcloud.ini:ro"
    networks:
      - ncnet

  onlyoffice:
    image: ${ONLYOFFICE_IMAGE}
    container_name: ${OO_CONTAINER}
    restart: unless-stopped
    environment:
      JWT_ENABLED: "true"
      JWT_SECRET: "${ONLYOFFICE_JWT_SECRET}"
      JWT_HEADER: "Authorization"
      JWT_IN_BODY: "false"
      USE_UNAUTHORIZED_STORAGE: "true"
      ALLOW_PRIVATE_IP_ADDRESS: "true"
      ALLOW_META_IP_ADDRESS: "true"
      TZ: "${TZ}"
    volumes:
      - "${ONLYOFFICE_DIR}/logs:/var/log/onlyoffice"
      - "${ONLYOFFICE_DIR}/data:/var/www/onlyoffice/Data"
      - "${ONLYOFFICE_DIR}/lib:/var/lib/onlyoffice"
      - "${ONLYOFFICE_DIR}/db:/var/lib/postgresql"
    networks:
      - ncnet

  proxy:
    image: ${NGINX_IMAGE}
    container_name: ${PROXY_CONTAINER}
    restart: unless-stopped
    depends_on:
      - nextcloud
      - onlyoffice
    ports:
      - "${HTTPS_PORT}:443"
    volumes:
      - "${NGINX_DIR}:/etc/nginx/conf.d:ro"
      - "${CERT_DIR}:/etc/nginx/certs:ro"
    networks:
      - ncnet

networks:
  ncnet:
    name: nextcloud_onlyoffice_net
    driver: bridge
COMPOSE

	if compose_available; then
		compose_cmd config -q >/dev/null
	fi
	success "Generated ${COMPOSE_FILE}"
}

#--- Preflight -----------------------------------------------------------------
preflight() {
	local supplied_host="${1:-}"
	local configure_access_host="${2:-no}"
	local chosen_host=""

	header "Pre-flight Checks"
	command_exists docker || fatal "Docker is not installed. Install Docker Engine first."
	docker info >/dev/null 2>&1 || fatal "Docker daemon is not running. Start it with: systemctl start docker"
	compose_available || fatal "Docker Compose is not installed. Install docker-compose-plugin or docker-compose."
	command_exists openssl || fatal "openssl is required. Install openssl first."
	success "Docker found: $(docker --version)"
	if docker compose version >/dev/null 2>&1; then
		success "Docker Compose plugin found: $(docker compose version --short 2>/dev/null || echo OK)"
	else
		success "Legacy docker-compose found: $(docker-compose --version)"
	fi

	# Ask for and validate the optional domain during pre-flight, before any slow image pull.
	if [[ "${configure_access_host}" == "yes" ]]; then
		chosen_host="$(choose_access_host "${supplied_host}")"
		config_init "${chosen_host}"
	fi

	check_disk_space_or_fix
	success "Pre-flight checks passed."
}

#--- OCC wrappers --------------------------------------------------------------
occ() {
	docker exec --user www-data "${NC_CONTAINER}" php occ --no-warnings "$@"
}

occ_maybe() {
	occ "$@" >/dev/null 2>&1 || true
}

wait_for_nextcloud() {
	local max_seconds="${1:-300}"
	local elapsed=0
	info "Waiting for Nextcloud initialization, up to ${max_seconds}s..."
	while [[ ${elapsed} -lt ${max_seconds} ]]; do
		if container_running "${NC_CONTAINER}" && occ status 2>/dev/null | grep -Eq 'installed:[[:space:]]+true'; then
			success "Nextcloud is installed and responding to occ."
			return 0
		fi
		sleep 5
		elapsed=$((elapsed + 5))
	done
	warn "Nextcloud did not finish initialization within ${max_seconds}s. You can rerun: sudo $0 onlyoffice-config"
	return 1
}

configure_nextcloud_system() {
	load_env
	local local_ip=""
	local public_ip=""
	local idx=0

	header "Configure Nextcloud System Settings"
	if ! container_running "${NC_CONTAINER}"; then
		fatal "Nextcloud container is not running. Run: sudo $0 start"
	fi

	local_ip="$(primary_local_ip)"
	public_ip="$(detect_public_ip || true)"

	add_trusted_domain() {
		local value="$1"
		[[ -n "${value}" ]] || return 0
		occ_maybe config:system:set trusted_domains "${idx}" --value="${value}"
		idx=$((idx + 1))
	}

	add_trusted_domain "${ACCESS_HOST}:${HTTPS_PORT}"
	add_trusted_domain "${ACCESS_HOST}"
	add_trusted_domain "${local_ip}:${HTTPS_PORT}"
	add_trusted_domain "${local_ip}"
	if [[ -n "${public_ip}" && "${public_ip}" != "${ACCESS_HOST}" && "${public_ip}" != "${local_ip}" ]]; then
		add_trusted_domain "${public_ip}:${HTTPS_PORT}"
		add_trusted_domain "${public_ip}"
	fi
	add_trusted_domain "localhost"
	add_trusted_domain "proxy"
	add_trusted_domain "nextcloud"

	occ_maybe config:system:set trusted_proxies 0 --value="172.16.0.0/12"
	occ_maybe config:system:set overwritehost --value="${ACCESS_HOST}:${HTTPS_PORT}"
	occ_maybe config:system:set overwriteprotocol --value="https"
	occ_maybe config:system:set overwrite.cli.url --value="https://${ACCESS_HOST}:${HTTPS_PORT}"
	occ_maybe maintenance:update:htaccess

	success "Nextcloud trusted domains and proxy settings applied."
}

configure_onlyoffice_connector() {
	load_env
	header "Configure ONLYOFFICE Connector"

	if ! container_running "${NC_CONTAINER}"; then
		fatal "Nextcloud container is not running. Run: sudo $0 start"
	fi

	info "Installing/enabling Nextcloud ONLYOFFICE connector app if available..."
	if ! occ app:install onlyoffice >/dev/null 2>&1; then
		occ app:enable onlyoffice >/dev/null 2>&1 || warn "Could not install/enable the ONLYOFFICE app automatically. Install it in Nextcloud Apps, then rerun: sudo $0 onlyoffice-config"
	fi

	# App config is used by current connector versions. System config is also set for compatibility with older connector behavior.
	occ_maybe config:app:set onlyoffice DocumentServerUrl --value="/editors/"
	occ_maybe config:app:set onlyoffice DocumentServerInternalUrl --value="http://onlyoffice/"
	occ_maybe config:app:set onlyoffice StorageUrl --value="http://proxy/"
	occ_maybe config:app:set onlyoffice jwt_secret --value="${ONLYOFFICE_JWT_SECRET}"
	occ_maybe config:app:set onlyoffice jwt_header --value="Authorization"
	occ_maybe config:app:set onlyoffice verify_peer_off --value="true"

	occ_maybe config:system:set onlyoffice DocumentServerUrl --value="/editors/"
	occ_maybe config:system:set onlyoffice DocumentServerInternalUrl --value="http://onlyoffice/"
	occ_maybe config:system:set onlyoffice StorageUrl --value="http://proxy/"
	occ_maybe config:system:set onlyoffice jwt_secret --value="${ONLYOFFICE_JWT_SECRET}"
	occ_maybe config:system:set onlyoffice jwt_header --value="Authorization"
	occ_maybe config:system:set onlyoffice verify_peer_off --type=boolean --value=true

	success "ONLYOFFICE connector configured. DocumentServerUrl=/editors/ Internal=http://onlyoffice/ Storage=http://proxy/"
}

show_access() {
	load_env
	local local_ip=""
	local public_ip=""
	local_ip="$(primary_local_ip)"
	public_ip="$(detect_public_ip || true)"
	echo ""
	echo "${BOLD}Access:${NC_COLOR}"
	echo "  Nextcloud URL          : https://${ACCESS_HOST}:${HTTPS_PORT}"
	if [[ -n "${public_ip}" ]]; then
		echo "  Public-IP URL          : https://${public_ip}:${HTTPS_PORT}"
	fi
	echo "  Local-IP URL           : https://${local_ip}:${HTTPS_PORT}"
	echo "  ONLYOFFICE health URL  : https://${ACCESS_HOST}:${HTTPS_PORT}/editors/healthcheck"
	echo ""
	echo "${BOLD}Files:${NC_COLOR}"
	echo "  Compose file           : ${COMPOSE_FILE}"
	echo "  Environment/secrets    : ${ENV_FILE}"
	echo "  TLS cert/key           : ${CERT_DIR}"
	echo "  Nextcloud files/data   : ${NEXTCLOUD_HTML_DIR}"
	echo "  MariaDB data           : ${DB_DIR}"
	echo "  ONLYOFFICE data        : ${ONLYOFFICE_DIR}"
	echo ""
	echo "${BOLD}Initial Nextcloud login:${NC_COLOR}"
	echo "  Admin user             : ${NEXTCLOUD_ADMIN_USER}"
	echo "  Admin password         : ${NEXTCLOUD_ADMIN_PASSWORD}"
	echo ""
	warn "The TLS certificate is self-signed. Your browser will show a warning on first access."
}

#--- Main actions --------------------------------------------------------------
do_install() {
	local host="${1:-}"
	header "Install Nextcloud + ONLYOFFICE Docs"
	require_root
	init_dirs
	preflight "${host}" "yes"
	write_php_ini
	generate_tls "${ACCESS_HOST}" "no"
	write_nginx_conf
	write_compose
	pull_images

	info "Starting stack..."
	compose_cmd up -d

	wait_for_nextcloud 420 || true
	configure_nextcloud_system || true
	configure_onlyoffice_connector || true
	show_access
}

do_start() {
	header "Start Stack"
	require_root
	init_dirs
	config_init ""
	preflight
	write_php_ini
	generate_tls "${ACCESS_HOST}" "no"
	write_nginx_conf
	write_compose
	compose_cmd up -d
	wait_for_nextcloud 300 || true
	configure_nextcloud_system || true
	success "Stack started."
	show_access
}

do_stop() {
	header "Stop Stack"
	require_root
	load_env
	compose_cmd down
	success "Stack stopped. Data remains under ${BASE_DIR}."
}

do_restart() {
	header "Restart Stack"
	require_root
	load_env
	compose_cmd down
	compose_cmd up -d
	wait_for_nextcloud 300 || true
	configure_nextcloud_system || true
	success "Stack restarted."
}

do_update() {
	header "Update Stack Images"
	require_root
	load_env
	preflight
	write_compose
	pull_images
	compose_cmd up -d
	wait_for_nextcloud 420 || true
	configure_nextcloud_system || true
	configure_onlyoffice_connector || true
	success "Update completed."
}

do_status() {
	header "Stack Status"
	if [[ -f "${ENV_FILE}" ]]; then load_env; fi
	docker ps -a --filter "name=nextcloud-onlyoffice" --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | column -t -s $'\t' || true
	echo ""
	if [[ -f "${ENV_FILE}" ]]; then
		show_access
	fi
	echo "${BOLD}Disk usage under BASE_DIR:${NC_COLOR}"
	du -sh "${BASE_DIR}"/* 2>/dev/null | sed 's/^/  /' || true
	echo ""
	docker_space_report || true
}

do_logs() {
	load_env
	local target="${1:-all}"
	shift || true
	if [[ -z "${target}" || "${target}" == "all" ]]; then
		compose_cmd logs --tail=150 -f "$@"
	else
		compose_cmd logs --tail=150 -f "${target}" "$@"
	fi
}

do_occ() {
	load_env
	[[ $# -gt 0 ]] || fatal "Usage: sudo $0 occ <occ-command>"
	if [[ -t 0 && -t 1 ]]; then
		docker exec -it --user www-data "${NC_CONTAINER}" php occ "$@"
	else
		docker exec --user www-data "${NC_CONTAINER}" php occ "$@"
	fi
}

do_onlyoffice_config() {
	require_root
	load_env
	wait_for_nextcloud 300 || true
	configure_nextcloud_system
	configure_onlyoffice_connector
	show_access
}

do_cert() {
	local host="${1:-}"
	require_root
	init_dirs
	host="$(choose_access_host "${host}")"
	config_init "${host}"
	generate_tls "${ACCESS_HOST}" "yes"
	write_nginx_conf
	write_compose
	if container_running "${PROXY_CONTAINER}"; then
		docker restart "${PROXY_CONTAINER}" >/dev/null
		success "Proxy restarted with regenerated certificate."
	fi
	show_access
}

do_set_host() {
	local host="${1:-}"
	require_root
	init_dirs
	host="$(choose_access_host "${host}")"
	config_init "${host}"
	generate_tls "${ACCESS_HOST}" "yes"
	write_nginx_conf
	write_compose
	compose_cmd up -d
	wait_for_nextcloud 300 || true
	configure_nextcloud_system || true
	configure_onlyoffice_connector || true
	show_access
}

do_backup_db() {
	require_root
	load_env
	mkdir -p "${BACKUP_DIR}"
	local out="${BACKUP_DIR}/nextcloud-db-$(date '+%Y%m%d-%H%M%S').sql.gz"
	if ! container_running "${DB_CONTAINER}"; then
		fatal "MariaDB container is not running. Run: sudo $0 start"
	fi
	info "Creating database dump: ${out}"
	docker exec "${DB_CONTAINER}" sh -c 'mariadb-dump --single-transaction --quick --lock-tables=false -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' | gzip -9 >"${out}"
	success "Database backup written: ${out}"
}

do_healthcheck() {
	header "HTTP Health Checks"
	load_env
	if command_exists curl; then
		echo "Nextcloud status.php:"
		curl -k -I --connect-timeout 5 --max-time 15 "https://127.0.0.1:${HTTPS_PORT}/status.php" 2>/dev/null | sed -n '1,8p' | sed 's/^/  /' || warn "Could not reach Nextcloud through proxy."
		echo ""
		echo "ONLYOFFICE healthcheck:"
		curl -k -sS --connect-timeout 5 --max-time 20 "https://127.0.0.1:${HTTPS_PORT}/editors/healthcheck" 2>/dev/null | sed 's/^/  /' || warn "Could not reach ONLYOFFICE through proxy."
		echo ""
	else
		warn "curl is not installed; skipping HTTP probes."
	fi
	do_status
}

do_migrate_info() {
	load_env
	header "Migration Guide"
	cat <<EOF
All persistent stack data is under:
  ${BASE_DIR}

Recommended migration:
  1) Stop the stack on the old server:
     sudo ${BASE_DIR}/Nextcloud_Onlyoffice.sh stop

  2) Copy the entire directory, preserving numeric ownership:
     rsync -aHAX --numeric-ids --info=progress2 ${BASE_DIR}/ root@NEW_SERVER:${BASE_DIR}/

  3) On the new server, start it:
     cd ${BASE_DIR}
     sudo ./Nextcloud_Onlyoffice.sh start

  4) If the IP/domain changed, update host, regenerate TLS SAN, and rewrite Nextcloud settings:
     sudo ./Nextcloud_Onlyoffice.sh set-host NEW_IP_OR_DOMAIN

Important files to preserve:
  ${ENV_FILE}
  ${COMPOSE_FILE}
  ${NEXTCLOUD_HTML_DIR}
  ${DB_DIR}
  ${ONLYOFFICE_DIR}
  ${CERT_DIR}

Note:
  Docker image layers live in Docker/containerd storage, not inside this compose directory unless you explicitly move Docker data-root.
EOF
}

do_print_config() {
	load_env
	header "Current Config"
	sed -E 's/^(.*PASSWORD|.*SECRET)=.*/\1=<hidden>/' "${ENV_FILE}"
}

usage() {
	cat <<EOF
Nextcloud + ONLYOFFICE Docs Manager ${SCRIPT_VERSION}

Usage:
  sudo $0 install [ip-or-domain]       Generate compose/TLS and start everything
                                       If omitted, the script asks for a domain for 7 seconds.
                                       Empty/timeout uses the detected public IP, then falls back to LAN IP.
  sudo $0 start                        Start stack
  sudo $0 stop                         Stop stack, keep data
  sudo $0 restart                      Restart stack
  sudo $0 update                       Pull newer images and recreate containers
  sudo $0 status                       Show container status and paths
  sudo $0 logs [service|all]           Follow logs. Services: proxy nextcloud mariadb redis onlyoffice
  sudo $0 occ <command>                Run Nextcloud occ command
  sudo $0 onlyoffice-config            Reinstall/reapply ONLYOFFICE connector settings
  sudo $0 cert [ip-or-domain]          Regenerate self-signed TLS files and restart proxy
  sudo $0 set-host [ip-or-domain]      Change access host, regenerate cert, rewrite settings
  sudo $0 backup-db                    Dump MariaDB to BASE_DIR/backups
  sudo $0 healthcheck                  Probe Nextcloud and ONLYOFFICE through https://127.0.0.1:7443
  sudo $0 storage                      Diagnose/clean Docker pull storage
  sudo $0 config                       Print non-secret config summary
  sudo $0 migrate-info                 Show migration steps

Interactive:
  sudo $0
  bash $0

Default BASE_DIR:
  ${BASE_DIR}

Public URL after install:
  https://ip-or-domain:${HTTPS_PORT}
EOF
}

interactive_menu() {
	if ! is_tty; then
		usage
		return 0
	fi
	local choice=""
	while true; do
		header "Nextcloud + ONLYOFFICE Docs Manager ${SCRIPT_VERSION}"
		echo "Base dir: ${BASE_DIR}"
		if [[ -f "${ENV_FILE}" ]]; then
			local host=""
			local port=""
			host="$(grep -E '^ACCESS_HOST=' "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- || true)"
			port="$(grep -E '^HTTPS_PORT=' "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- || true)"
			echo "URL     : https://${host:-ip-or-domain}:${port:-${HTTPS_PORT}}"
		else
			echo "URL     : not installed yet"
		fi
		echo ""
		echo "1) Install / generate compose / start"
		echo "2) Start stack"
		echo "3) Stop stack"
		echo "4) Restart stack"
		echo "5) Status"
		echo "6) Logs"
		echo "7) Healthcheck"
		echo "8) Reapply ONLYOFFICE connector config"
		echo "9) Change access host + regenerate self-signed TLS"
		echo "10) Update images"
		echo "11) Backup database"
		echo "12) Storage / fix Docker pull no-space problem"
		echo "13) Show config"
		echo "14) Migration guide"
		echo "0) Exit"
		echo ""
		read -r -p "Choice: " choice || true

		case "${choice}" in
		1)
			do_install ""
			pause_return
			;;
		2)
			do_start
			pause_return
			;;
		3)
			do_stop
			pause_return
			;;
		4)
			do_restart
			pause_return
			;;
		5)
			do_status
			pause_return
			;;
		6)
			local service=""
			service="$(prompt_value "Logs service: all/proxy/nextcloud/mariadb/redis/onlyoffice" "all")"
			do_logs "${service}"
			;;
		7)
			do_healthcheck
			pause_return
			;;
		8)
			do_onlyoffice_config
			pause_return
			;;
		9)
			do_set_host ""
			pause_return
			;;
		10)
			do_update
			pause_return
			;;
		11)
			do_backup_db
			pause_return
			;;
		12) storage_menu ;;
		13)
			do_print_config
			pause_return
			;;
		14)
			do_migrate_info
			pause_return
			;;
		0 | q | Q | exit) exit 0 ;;
		h | help | ?)
			usage
			pause_return
			;;
		*)
			warn "Invalid choice."
			pause_return
			;;
		esac
	done
}

main() {
	local cmd="${1:-}"
	if [[ -z "${cmd}" ]]; then
		interactive_menu
		exit 0
	fi
	shift || true

	case "${cmd}" in
	install) do_install "${1:-}" ;;
	start) do_start ;;
	stop) do_stop ;;
	restart) do_restart ;;
	update) do_update ;;
	status) do_status ;;
	logs) do_logs "${1:-all}" "${@:2}" ;;
	occ) do_occ "$@" ;;
	onlyoffice-config | configure-onlyoffice) do_onlyoffice_config ;;
	cert | regenerate-cert) do_cert "${1:-}" ;;
	set-host | domain | host) do_set_host "${1:-}" ;;
	backup-db | backup) do_backup_db ;;
	healthcheck | health) do_healthcheck ;;
	storage | disk | space | prune) storage_menu ;;
	migrate-info | migration) do_migrate_info ;;
	config | show-config) do_print_config ;;
	help | -h | --help) usage ;;
	*)
		error "Unknown command: ${cmd}"
		usage
		exit 1
		;;
	esac
}

main "$@"
