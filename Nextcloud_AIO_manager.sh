#!/usr/bin/env bash
#===============================================================================
#  Nextcloud AIO Manager
#  ---------------------
#  Portable management script for Nextcloud All-in-One (Docker).
#
#  Base directory : /data/Nextcloud_D/
#  Compose file   : /data/Nextcloud_D/docker-compose.yml
#  Config file    : /data/Nextcloud_D/config.toml
#
#  Important fixes in this version:
#    - Prompts for the public domain during install and validates DNS against
#      the detected public IP.
#    - Uses the public IP for browser URLs, not the private cloud interface IP.
#    - Enforces one canonical BASE_DIR path. A stale/wrong Docker volume device
#      like /data/Nextcloud_d/... is migrated or recreated, not preserved.
#    - Explains/checks AIO ports: 80/18080/18443/443/3478.
#    - Auto-reads the generated AIO passphrase; no fake/default passphrase.
#    - Diagnoses and interactively helps fix host port 443 conflicts.
#===============================================================================

set -Eeuo pipefail

#--- Constants -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/data/Nextcloud_D}"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
CONFIG_FILE="${BASE_DIR}/config.toml"
LOG_DIR="${BASE_DIR}/logs"
LOG_FILE="${LOG_DIR}/manager.log"
BACKUP_DIR="${BASE_DIR}/backups"
NCDATA_DIR="${BASE_DIR}/ncdata"
VOLUME_ROOT="${BASE_DIR}/volumes"
MASTER_VOLUME_NAME="nextcloud_aio_mastercontainer"
MASTER_VOLUME_DIR="${VOLUME_ROOT}/${MASTER_VOLUME_NAME}"

MASTER_CONTAINER="nextcloud-aio-mastercontainer"
NC_CONTAINER="nextcloud-aio-nextcloud"

AIO_PORT_HTTP=80
AIO_PORT_INTERFACE=18080
AIO_PORT_INTERFACE_TLS=18443
NEXTCLOUD_HTTPS_PORT=443
TALK_PORT=3478

SCRIPT_VERSION="2026-05-02.6"
AIO_CONFIG_JSON_IN_CONTAINER="/mnt/docker-aio-config/data/configuration.json"
PASSPHRASE_PROMPT_TIMEOUT=6
REJECTED_PASSPHRASES=("Nextcloud_AIO" "nextcloud_aio" "changeme" "password" "passphrase")

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

#--- Helpers -------------------------------------------------------------------
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

ensure_log_dir() {
	mkdir -p "${LOG_DIR}" 2>/dev/null || true
}

log() {
	local msg="[$(timestamp)] $*"
	ensure_log_dir
	if [[ -d "${LOG_DIR}" ]]; then
		printf '%s\n' "${msg}" >>"${LOG_FILE}" 2>/dev/null || true
	fi
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

require_root() {
	if [[ ${EUID} -ne 0 ]]; then
		fatal "This script must be run as root. Use: sudo $0 $*"
	fi
}

confirm() {
	local prompt="${1:-Are you sure?}"
	local answer=""
	printf '%b' "${YELLOW}${prompt} [y/N]: ${NC_COLOR}"
	read -r answer || true
	[[ "${answer}" =~ ^[Yy]$ ]]
}

confirm_phrase() {
	local phrase="$1"
	local prompt="$2"
	local answer=""
	printf '%b' "${RED}${prompt}${NC_COLOR}\nType '${phrase}' to continue: "
	read -r answer || true
	[[ "${answer}" == "${phrase}" ]]
}

is_rejected_passphrase() {
	local value="$1"
	local rejected=""
	for rejected in "${REJECTED_PASSPHRASES[@]}"; do
		[[ "${value}" == "${rejected}" ]] && return 0
	done
	return 1
}

cleanup_rejected_passphrase() {
	[[ -f "${CONFIG_FILE}" ]] || return 0
	local current=""
	current="$(config_get aio_passphrase || true)"
	if [[ -n "${current}" ]] && is_rejected_passphrase "${current}"; then
		warn "Removing invalid saved AIO passphrase from manager config: ${current}"
		config_set "aio_passphrase" ""
	fi
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

compose_available() {
	docker compose version >/dev/null 2>&1 || command_exists docker-compose
}

docker_compose() {
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

port_in_use_tcp() {
	local port="$1"
	if command_exists ss; then
		ss -H -tln 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[.:])${port}$"
	elif command_exists netstat; then
		netstat -tln 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[.:])${port}$"
	else
		return 1
	fi
}

port_in_use_udp() {
	local port="$1"
	if command_exists ss; then
		ss -H -uln 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[.:])${port}$"
	elif command_exists netstat; then
		netstat -uln 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[.:])${port}$"
	else
		return 1
	fi
}

primary_local_ip() {
	hostname -I 2>/dev/null | awk '{print $1}' || printf 'LOCAL_SERVER_IP'
}

valid_ip_literal() {
	local value="$1"
	[[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "${value}" =~ ^[0-9A-Fa-f:]+$ ]]
}

is_private_ipv4() {
	local ip="$1"
	[[ "${ip}" =~ ^10\. ]] && return 0
	[[ "${ip}" =~ ^192\.168\. ]] && return 0
	[[ "${ip}" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && return 0
	[[ "${ip}" =~ ^127\. ]] && return 0
	[[ "${ip}" =~ ^169\.254\. ]] && return 0
	[[ "${ip}" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]] && return 0
	return 1
}

public_ip() {
	local ip=""

	if command_exists curl; then
		local services=(
			"https://ip.sb"
			"https://api.ipify.org"
			"https://ifconfig.me/ip"
			"https://icanhazip.com"
		)
		local svc=""
		for svc in "${services[@]}"; do
			ip="$(curl -fsS --connect-timeout 3 --max-time 6 "${svc}" 2>/dev/null | tr -d '[:space:]' | head -c 80 || true)"
			if [[ -n "${ip}" ]] && valid_ip_literal "${ip}"; then
				printf '%s' "${ip}"
				return 0
			fi
		done
	fi

	if command_exists dig; then
		ip="$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | tail -1 | tr -d '[:space:]' || true)"
		if [[ -n "${ip}" ]] && valid_ip_literal "${ip}"; then
			printf '%s' "${ip}"
			return 0
		fi
	fi

	return 1
}

access_ip() {
	local ip=""
	ip="$(public_ip || true)"
	if [[ -n "${ip}" ]]; then
		printf '%s' "${ip}"
		return 0
	fi
	primary_local_ip
}

memory_gib() {
	awk '/MemTotal/ { printf "%.1f", $2 / 1024 / 1024 }' /proc/meminfo 2>/dev/null || printf "unknown"
}

memory_gib_int_floor() {
	awk '/MemTotal/ { print int($2 / 1024 / 1024) }' /proc/meminfo 2>/dev/null || printf "0"
}

cpu_cores() {
	if command_exists nproc; then
		nproc 2>/dev/null || printf "unknown"
	else
		grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf "unknown"
	fi
}

firewall_hint() {
	local ports="80/tcp 443/tcp ${AIO_PORT_INTERFACE}/tcp ${AIO_PORT_INTERFACE_TLS}/tcp"
	echo "  Required before first start: ${ports}"
	echo "  Add ${TALK_PORT}/tcp and ${TALK_PORT}/udp only if enabling Nextcloud Talk."
	if command_exists ufw; then
		echo "  UFW example: ufw allow 80,443,${AIO_PORT_INTERFACE},${AIO_PORT_INTERFACE_TLS}/tcp"
		echo "  Talk example: ufw allow ${TALK_PORT}/tcp && ufw allow ${TALK_PORT}/udp"
	fi
}

valid_domain_name() {
	local domain="$1"
	[[ -n "${domain}" ]] || return 1
	[[ ! "${domain}" =~ [[:space:]/:] ]] || return 1
	[[ "${domain}" == *.* ]] || return 1
	[[ "${domain}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

resolve_domain_ips() {
	local domain="$1"
	[[ -n "${domain}" ]] || return 0

	if command_exists dig; then
		{
			dig +short A "${domain}" 2>/dev/null
			dig +short AAAA "${domain}" 2>/dev/null
		} | awk 'NF' | sort -u
	elif command_exists getent; then
		getent ahosts "${domain}" 2>/dev/null | awk '{print $1}' | sort -u
	fi
}

aio_container_uses_host_port() {
	local host_port="$1"
	local containers=""
	containers="$(docker ps --filter 'name=nextcloud-aio' --format '{{.Names}}' 2>/dev/null || true)"
	while IFS= read -r c; do
		[[ -n "${c}" ]] || continue
		if docker port "${c}" 2>/dev/null | grep -Eq "0\.0\.0\.0:${host_port}$|::+:${host_port}$|:${host_port}$"; then
			return 0
		fi
	done <<<"${containers}"
	return 1
}

show_port_purposes() {
	echo "  ${AIO_PORT_HTTP}/tcp    : AIO/Caddy HTTP listener. Needed publicly for ACME HTTP-01 certificate validation and redirects."
	echo "  ${AIO_PORT_INTERFACE}/tcp : AIO admin interface with self-signed certificate. Use https://PUBLIC_IP:${AIO_PORT_INTERFACE}."
	echo "  ${AIO_PORT_INTERFACE_TLS}/tcp : AIO admin interface with valid certificate. Use https://DOMAIN:${AIO_PORT_INTERFACE_TLS} after DNS and ACME are OK."
	echo "  ${NEXTCLOUD_HTTPS_PORT}/tcp   : Final Nextcloud HTTPS service, normally served by nextcloud-aio-apache after setup."
	echo "  ${TALK_PORT}/tcp+udp : Nextcloud Talk TURN/STUN port."
}

check_domain_dns() {
	local domain="$1"
	local pub="$2"
	[[ -n "${domain}" ]] || return 0

	local resolved=""
	resolved="$(resolve_domain_ips "${domain}" | paste -sd ',' - 2>/dev/null || true)"
	echo "  Domain DNS resolves to    : ${resolved:-<not resolved from this host>}"

	if [[ -z "${pub}" ]]; then
		warn "Could not detect public IP, so DNS match cannot be verified."
	elif [[ -z "${resolved}" ]]; then
		warn "Domain '${domain}' does not currently resolve from this server."
	elif [[ "${resolved}" != *"${pub}"* ]]; then
		warn "Domain '${domain}' does not appear to resolve to this server public IP '${pub}'."
	else
		success "Domain '${domain}' resolves to this server public IP '${pub}'."
	fi
}

prompt_for_domain() {
	local supplied="${1:-}"
	local current=""
	local domain=""
	local pub=""

	config_init
	current="$(config_get domain || true)"
	pub="$(public_ip || true)"

	if [[ -n "${supplied}" ]]; then
		domain="${supplied}"
	elif [[ -n "${current}" ]]; then
		domain="${current}"
		info "Using saved domain: ${domain}"
	elif [[ -t 0 ]]; then
		echo ""
		echo "${BOLD}Domain setup:${NC_COLOR}"
		echo "  Public IP detected: ${pub:-<not detected>}"
		echo "  Enter the domain that points to this VPS, e.g. cloud.example.com."
		echo "  This is needed for the valid-cert AIO URL and the final Nextcloud site."
		printf 'Domain [press Enter to skip for now]: '
		read -r domain || true
	fi

	if [[ -z "${domain}" ]]; then
		warn "No domain saved. You can set it later with: sudo $0 domain your.domain.tld"
		return 0
	fi

	if ! valid_domain_name "${domain}"; then
		fatal "Invalid domain '${domain}'. Use hostname only, e.g. cloud.example.com"
	fi

	config_set "domain" "${domain}"
	success "Domain saved to config: ${domain}"
	check_domain_dns "${domain}" "${pub}"
}

print_access_urls() {
	local domain="${1:-}"
	local pub=""
	local local_ip=""
	pub="$(public_ip || true)"
	local_ip="$(primary_local_ip)"

	echo "  Public IP detected        : ${pub:-<not detected>}"
	echo "  Local/private IP          : ${local_ip}"
	echo "  AIO Interface, self-signed: https://${pub:-${local_ip}}:${AIO_PORT_INTERFACE}"
	echo "  AIO Interface, local only : https://${local_ip}:${AIO_PORT_INTERFACE}"

	if [[ -n "${domain}" ]]; then
		echo "  AIO Interface, valid cert : https://${domain}:${AIO_PORT_INTERFACE_TLS}"
		echo "  Nextcloud                 : https://${domain}"
		check_domain_dns "${domain}" "${pub}"
	else
		echo "  AIO Interface, valid cert : https://<your-domain>:${AIO_PORT_INTERFACE_TLS}"
		echo "  Nextcloud                 : https://<your-domain>"
	fi

	if [[ -n "${pub}" ]] && is_private_ipv4 "${local_ip}"; then
		info "Using public IP '${pub}' for browser URLs instead of private interface IP '${local_ip}'."
	fi
}

#--- Config (TOML-like) --------------------------------------------------------
config_init() {
	mkdir -p "${BASE_DIR}"
	if [[ ! -f "${CONFIG_FILE}" ]]; then
		cat >"${CONFIG_FILE}" <<TOML
# Nextcloud AIO Manager Configuration
# Generated automatically — edit with care.

[install]
installed = false
install_date = ""
domain = ""

[credentials]
# The AIO passphrase is shown on first launch.
# Paste it here so you never lose it.
aio_passphrase = ""
admin_user = ""
admin_password = ""

[ports]
http = ${AIO_PORT_HTTP}
aio_interface = ${AIO_PORT_INTERFACE}
aio_interface_tls = ${AIO_PORT_INTERFACE_TLS}
nextcloud_https = ${NEXTCLOUD_HTTPS_PORT}
talk_tcp = ${TALK_PORT}
talk_udp = ${TALK_PORT}

[paths]
base_dir = "${BASE_DIR}"
data_dir = "${NCDATA_DIR}"
backup_dir = "${BACKUP_DIR}"
master_volume_dir = "${MASTER_VOLUME_DIR}"

[backup]
auto_backup = false
backup_schedule = "0 3 * * *"
TOML
		success "Created config file: ${CONFIG_FILE}"
	fi
}

config_get() {
	local key="$1"
	[[ -f "${CONFIG_FILE}" ]] || return 0
	awk -F '=' -v wanted="${key}" '
        $0 ~ "^[[:space:]]*#" { next }
        {
            k=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
            if (k == wanted) {
                v=$0
                sub(/^[^=]*=/, "", v)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                gsub(/^\"|\"$/, "", v)
                print v
                exit
            }
        }
    ' "${CONFIG_FILE}"
}

config_set() {
	local key="$1"
	local value="$2"
	local tmp="${CONFIG_FILE}.tmp.$$"
	mkdir -p "${BASE_DIR}"
	[[ -f "${CONFIG_FILE}" ]] || config_init

	awk -v wanted="${key}" -v new_value="${value}" '
        BEGIN { done=0 }
        $0 ~ "^[[:space:]]*#" { print; next }
        {
            line=$0
            k=$1
            sub(/=.*/, "", k)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
            if (k == wanted && done == 0) {
                print wanted " = \"" new_value "\""
                done=1
                next
            }
            print line
        }
        END {
            if (done == 0) print wanted " = \"" new_value "\""
        }
    ' "${CONFIG_FILE}" >"${tmp}"
	mv "${tmp}" "${CONFIG_FILE}"
}

#--- Pre-flight checks ---------------------------------------------------------
preflight() {
	header "Pre-flight Checks"

	if ! command_exists docker; then
		error "Docker is not installed."
		if confirm "Install Docker now using Docker's convenience script?"; then
			install_docker
		else
			exit 1
		fi
	else
		success "Docker found: $(docker --version)"
	fi

	if ! docker info >/dev/null 2>&1; then
		fatal "Docker daemon is not running. Start it with: sudo systemctl start docker"
	fi
	success "Docker daemon is running."

	if docker compose version >/dev/null 2>&1; then
		success "Docker Compose plugin found: $(docker compose version --short 2>/dev/null || echo OK)"
	elif command_exists docker-compose; then
		warn "Legacy docker-compose found. The Docker Compose plugin is recommended."
	else
		fatal "Docker Compose not found. Install with: sudo apt install docker-compose-plugin"
	fi

	if docker info 2>/dev/null | grep -q '/var/snap/docker/'; then
		warn "Snap-based Docker detected. Nextcloud AIO does not support the snap Docker package."
		warn "Use the official Docker Engine packages instead."
	fi

	echo ""
	echo "${BOLD}Port purpose:${NC_COLOR}"
	show_port_purposes
	echo ""

	for port in "${AIO_PORT_HTTP}" "${AIO_PORT_INTERFACE}" "${AIO_PORT_INTERFACE_TLS}" "${NEXTCLOUD_HTTPS_PORT}"; do
		if port_in_use_tcp "${port}"; then
			if aio_container_uses_host_port "${port}"; then
				info "TCP port ${port} is already bound by an existing Nextcloud AIO container. This is OK for reinstall/start."
			else
				warn "TCP port ${port} is already in use by another service. AIO may fail to bind or the final Nextcloud Apache container may fail."
			fi
		fi
	done

	if port_in_use_tcp "${TALK_PORT}"; then
		if aio_container_uses_host_port "${TALK_PORT}"; then
			info "TCP port ${TALK_PORT} is already bound by an existing Nextcloud AIO container."
		else
			warn "TCP port ${TALK_PORT} is already in use. Nextcloud Talk may fail to bind."
		fi
	fi
	if port_in_use_udp "${TALK_PORT}"; then
		warn "UDP port ${TALK_PORT} is already in use. Nextcloud Talk may fail to bind unless this is the existing AIO Talk container."
	fi

	success "Pre-flight checks passed."
}

#--- Install Docker ------------------------------------------------------------
install_docker() {
	header "Installing Docker"
	command_exists curl || fatal "curl is required to install Docker. Install curl first."
	curl -fsSL https://get.docker.com | sh
	systemctl enable --now docker
	success "Docker installed and started."
}

#--- Directory and volume handling --------------------------------------------
init_dirs() {
	mkdir -p "${BASE_DIR}" "${LOG_DIR}" "${BACKUP_DIR}" "${NCDATA_DIR}" "${VOLUME_ROOT}" "${MASTER_VOLUME_DIR}"
	success "Directory structure ready at ${BASE_DIR}"
}

master_volume_device() {
	docker volume inspect -f '{{with .Options}}{{index . "device"}}{{end}}' "${MASTER_VOLUME_NAME}" 2>/dev/null | sed 's/<no value>//g' || true
}

master_volume_mountpoint() {
	docker volume inspect -f '{{.Mountpoint}}' "${MASTER_VOLUME_NAME}" 2>/dev/null || true
}

dir_has_files() {
	local dir="$1"
	[[ -d "${dir}" ]] || return 1
	find "${dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .
}

copy_dir_contents() {
	local src="$1"
	local dst="$2"
	[[ -d "${src}" ]] || return 0
	mkdir -p "${dst}"
	if command_exists rsync; then
		rsync -a "${src}/" "${dst}/"
	else
		(
			shopt -s dotglob nullglob
			cp -a "${src}"/* "${dst}/" 2>/dev/null || true
		)
	fi
}

create_canonical_master_volume() {
	mkdir -p "${MASTER_VOLUME_DIR}"
	docker volume create \
		--driver local \
		--opt type=none \
		--opt o=bind \
		--opt device="${MASTER_VOLUME_DIR}" \
		"${MASTER_VOLUME_NAME}" >/dev/null
	success "Docker volume '${MASTER_VOLUME_NAME}' now uses canonical path: ${MASTER_VOLUME_DIR}"
}

recreate_master_volume_canonical() {
	local source_path="${1:-}"
	local reason="${2:-wrong volume path}"

	warn "Recreating Docker volume '${MASTER_VOLUME_NAME}' because: ${reason}"

	if container_running "${MASTER_CONTAINER}"; then
		warn "Stopping ${MASTER_CONTAINER} so its volume can be corrected."
		docker stop "${MASTER_CONTAINER}" >/dev/null 2>&1 || true
	fi
	if container_exists "${MASTER_CONTAINER}"; then
		docker rm "${MASTER_CONTAINER}" >/dev/null 2>&1 || true
	fi

	mkdir -p "${MASTER_VOLUME_DIR}"

	if [[ -n "${source_path}" && "${source_path}" != "${MASTER_VOLUME_DIR}" && -d "${source_path}" ]] && dir_has_files "${source_path}"; then
		local backup_dir="${BASE_DIR}/volume-migration-backups/$(date '+%Y%m%d-%H%M%S')"
		mkdir -p "${backup_dir}"
		info "Copying existing AIO master volume data from '${source_path}' to '${MASTER_VOLUME_DIR}'."
		copy_dir_contents "${source_path}" "${MASTER_VOLUME_DIR}"
		info "Saving a safety copy under: ${backup_dir}"
		copy_dir_contents "${source_path}" "${backup_dir}"
	elif [[ -n "${source_path}" && ! -d "${source_path}" ]]; then
		warn "Old volume device path does not exist: ${source_path}. No data can be copied from it."
	fi

	docker volume rm "${MASTER_VOLUME_NAME}" >/dev/null 2>&1 || true
	create_canonical_master_volume
}

ensure_master_volume_dir() {
	mkdir -p "${VOLUME_ROOT}" "${MASTER_VOLUME_DIR}"

	if ! docker volume inspect "${MASTER_VOLUME_NAME}" >/dev/null 2>&1; then
		create_canonical_master_volume
		return 0
	fi

	local device=""
	local mountpoint=""
	device="$(master_volume_device)"
	mountpoint="$(master_volume_mountpoint)"

	if [[ "${device}" == "${MASTER_VOLUME_DIR}" ]]; then
		[[ -d "${MASTER_VOLUME_DIR}" ]] || mkdir -p "${MASTER_VOLUME_DIR}"
		return 0
	fi

	if [[ -n "${device}" ]]; then
		warn "Existing Docker volume uses non-canonical path: ${device}"
		warn "Canonical BASE_DIR path is: ${MASTER_VOLUME_DIR}"
		recreate_master_volume_canonical "${device}" "volume device is outside BASE_DIR or has wrong case"
		return 0
	fi

	if [[ -n "${mountpoint}" && -d "${mountpoint}" ]]; then
		warn "Existing Docker volume is Docker-managed at: ${mountpoint}"
		warn "Migrating it into BASE_DIR for portability."
		recreate_master_volume_canonical "${mountpoint}" "volume is Docker-managed instead of bind-mounted under BASE_DIR"
		return 0
	fi

	recreate_master_volume_canonical "" "existing volume has no usable device or mountpoint"
}

show_master_volume_status() {
	header "AIO Master Volume Status"
	if docker volume inspect "${MASTER_VOLUME_NAME}" >/dev/null 2>&1; then
		local device=""
		device="$(master_volume_device)"
		echo "  Name       : ${MASTER_VOLUME_NAME}"
		echo "  Mountpoint : $(docker volume inspect -f '{{.Mountpoint}}' "${MASTER_VOLUME_NAME}" 2>/dev/null || echo '<unknown>')"
		echo "  Device     : ${device:-<Docker-managed volume>}"
		echo "  Canonical  : ${MASTER_VOLUME_DIR}"
		if [[ -n "${device}" ]]; then
			if [[ -d "${device}" ]]; then
				echo "  Device OK  : yes"
			else
				echo "  Device OK  : no"
			fi
			if [[ "${device}" == "${MASTER_VOLUME_DIR}" ]]; then
				echo "  In BASE_DIR : yes"
			else
				echo "  In BASE_DIR : no - run: sudo $0 repair-volume"
			fi
		else
			echo "  In BASE_DIR : no - run: sudo $0 repair-volume to migrate"
		fi
	else
		echo "  Volume does not exist yet. It will be created during install/start."
		echo "  Planned bind path: ${MASTER_VOLUME_DIR}"
	fi
}

#--- Generate compose file -----------------------------------------------------
write_compose() {
	cat >"${COMPOSE_FILE}" <<COMPOSE
## Nextcloud AIO - Portable Docker Compose
## Generated by Nextcloud_AIO_manager.sh
## Manager version: ${SCRIPT_VERSION}
## All manager-created host paths live under: ${BASE_DIR}
##
## Mode: integrated HTTPS / no external reverse proxy.
## In this mode, the final Nextcloud site uses host port 443. The host port 443
## must be free before you submit the domain in the AIO web UI.
##
## Port mapping used here:
##   ${AIO_PORT_HTTP}:80       -> AIO ACME HTTP-01 / redirect listener
##   ${AIO_PORT_INTERFACE}:8080 -> AIO admin UI with self-signed cert; use IP URL
##   ${AIO_PORT_INTERFACE_TLS}:8443 -> AIO admin UI with valid cert; use domain:port URL
##   443 is NOT mapped by this mastercontainer. AIO creates nextcloud-aio-apache
##   later and that container binds host 443 for the final Nextcloud site.
##
## Reverse proxy mode note:
##   If another service must own host 443, do not try to use ${AIO_PORT_INTERFACE_TLS}
##   as the Nextcloud port. Instead configure your reverse proxy on 443 and set
##   APACHE_PORT=11000 / APACHE_IP_BINDING=127.0.0.1 for AIO, then proxy to 11000.

services:
  nextcloud-aio-mastercontainer:
    image: ghcr.io/nextcloud-releases/all-in-one:latest
    init: true
    container_name: ${MASTER_CONTAINER}
    restart: always
    ports:
      - "${AIO_PORT_HTTP}:80"
      - "${AIO_PORT_INTERFACE}:8080"
      - "${AIO_PORT_INTERFACE_TLS}:8443"
    environment:
      - NEXTCLOUD_DATADIR=${NCDATA_DIR}
      # Keep APACHE_PORT unset in integrated mode. AIO will create its Apache
      # container for the final Nextcloud HTTPS site on host port 443.
      # For external reverse proxy mode only, use these instead:
      # - APACHE_PORT=11000
      # - APACHE_IP_BINDING=127.0.0.1
      # - SKIP_DOMAIN_VALIDATION=false
      # - NEXTCLOUD_TIMEZONE=Asia/Tokyo
      # - NEXTCLOUD_UPLOAD_LIMIT=16G
      # - NEXTCLOUD_MEMORY_LIMIT=512M
      # - NEXTCLOUD_STARTUP_APPS=deck twofactor_totp tasks calendar contacts notes
    volumes:
      - ${MASTER_VOLUME_NAME}:/mnt/docker-aio-config
      - /var/run/docker.sock:/var/run/docker.sock:ro

volumes:
  ${MASTER_VOLUME_NAME}:
    name: ${MASTER_VOLUME_NAME}
    driver: local
    driver_opts:
      type: none
      o: bind
      device: "${MASTER_VOLUME_DIR}"
COMPOSE
}

init_compose() {
	mkdir -p "${BASE_DIR}"

	if [[ -f "${COMPOSE_FILE}" ]]; then
		if grep -q "Generated by Nextcloud_AIO_manager.sh" "${COMPOSE_FILE}" &&
			grep -q "Manager version: ${SCRIPT_VERSION}" "${COMPOSE_FILE}" &&
			grep -q "device: \"${MASTER_VOLUME_DIR}\"" "${COMPOSE_FILE}"; then
			info "docker-compose.yml already exists and matches this manager."
			return
		fi

		local backup="${COMPOSE_FILE}.bak.$(date '+%Y%m%d-%H%M%S')"
		cp -a "${COMPOSE_FILE}" "${backup}"
		warn "Existing docker-compose.yml backed up to: ${backup}"
		warn "Regenerating compose file with fixed bind-backed AIO master volume."
	fi

	write_compose

	if compose_available; then
		docker_compose config -q >/dev/null
	fi

	success "Generated ${COMPOSE_FILE}"
}

#===============================================================================
#  CORE ACTIONS
#===============================================================================

start_master_container() {
	cd "${BASE_DIR}"
	ensure_master_volume_dir

	if docker_compose up -d; then
		return 0
	fi

	warn "Docker Compose failed. Attempting volume-path repair once, then retrying."
	ensure_master_volume_dir
	docker_compose up -d
}

wait_for_master() {
	local max_seconds="${1:-60}"
	local elapsed=0
	info "Waiting for master container to initialize, up to ${max_seconds}s..."

	while [[ ${elapsed} -lt ${max_seconds} ]]; do
		if container_running "${MASTER_CONTAINER}"; then
			success "Master container is running."
			return 0
		fi
		sleep 5
		elapsed=$((elapsed + 5))
	done

	error "Master container did not start. Last logs:"
	docker logs --tail 80 "${MASTER_CONTAINER}" 2>&1 || true
	return 1
}

extract_password_from_json_stream() {
	sed -nE 's/.*"password"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1
}

read_passphrase_from_aio_config() {
	local passphrase=""

	if container_running "${MASTER_CONTAINER}"; then
		passphrase="$(docker exec "${MASTER_CONTAINER}" sh -c "cat '${AIO_CONFIG_JSON_IN_CONTAINER}' 2>/dev/null" 2>/dev/null |
			extract_password_from_json_stream || true)"
		if [[ -n "${passphrase}" ]]; then
			printf '%s' "${passphrase}"
			return 0
		fi
	fi

	local host_config="${MASTER_VOLUME_DIR}/data/configuration.json"
	if [[ -f "${host_config}" ]]; then
		passphrase="$(extract_password_from_json_stream <"${host_config}" || true)"
		if [[ -n "${passphrase}" ]]; then
			printf '%s' "${passphrase}"
			return 0
		fi
	fi

	local mountpoint=""
	mountpoint="$(master_volume_mountpoint)"
	if [[ -n "${mountpoint}" && -f "${mountpoint}/data/configuration.json" ]]; then
		passphrase="$(extract_password_from_json_stream <"${mountpoint}/data/configuration.json" || true)"
		if [[ -n "${passphrase}" ]]; then
			printf '%s' "${passphrase}"
			return 0
		fi
	fi

	return 1
}

read_passphrase_from_logs() {
	local passphrase=""
	if ! container_exists "${MASTER_CONTAINER}"; then
		return 1
	fi

	passphrase="$({ docker logs "${MASTER_CONTAINER}" 2>&1 || true; } |
		sed -nE 's/.*Nextcloud AIO passphrase:[[:space:]]*//p; s/.*Passphrase[[:space:]]*//p; s/.*passphrase:[[:space:]]*//p' |
		sed -E 's/^[[:space:]]+|[[:space:]]+$//g' |
		tail -1)"

	if [[ -n "${passphrase}" ]]; then
		printf '%s' "${passphrase}"
		return 0
	fi
	return 1
}

print_passphrase_box() {
	local passphrase="$1"
	echo ""
	printf '  %b\n' "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${NC_COLOR}"
	printf '  %b\n' "${BOLD}${GREEN}║  AIO Passphrase: ${passphrase}${NC_COLOR}"
	printf '  %b\n' "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${NC_COLOR}"
	echo ""
}

save_discovered_passphrase() {
	local passphrase="$1"
	local source_label="${2:-AIO}"

	if [[ -z "${passphrase}" ]]; then
		return 1
	fi
	if is_rejected_passphrase "${passphrase}"; then
		warn "Refusing to save '${passphrase}' as the AIO passphrase; it is not the generated AIO secret shown by the mastercontainer."
		return 1
	fi

	config_set "aio_passphrase" "${passphrase}"
	success "AIO passphrase saved to ${CONFIG_FILE} (${source_label})."
	print_passphrase_box "${passphrase}"
	return 0
}

save_passphrase_from_aio() {
	local passphrase=""

	passphrase="$(read_passphrase_from_aio_config || true)"
	if save_discovered_passphrase "${passphrase}" "configuration.json"; then
		return 0
	fi

	passphrase="$(read_passphrase_from_logs || true)"
	if save_discovered_passphrase "${passphrase}" "docker logs"; then
		return 0
	fi

	return 1
}

prompt_for_passphrase_if_needed() {
	warn "Could not auto-read the generated AIO passphrase yet."
	if [[ -t 0 ]]; then
		local manual_pass=""
		printf '%b' "${YELLOW}Paste the real AIO passphrase within ${PASSPHRASE_PROMPT_TIMEOUT}s, or press Enter to skip: ${NC_COLOR}"
		if read -r -t "${PASSPHRASE_PROMPT_TIMEOUT}" manual_pass; then
			echo ""
			manual_pass="$(printf '%s' "${manual_pass}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
			if [[ -n "${manual_pass}" ]]; then
				save_discovered_passphrase "${manual_pass}" "manual entry" && return 0
			fi
		else
			echo ""
			warn "Passphrase prompt timed out after ${PASSPHRASE_PROMPT_TIMEOUT}s. Nothing was saved."
		fi
	fi

	warn "No fake/default passphrase was saved. Use the passphrase shown by AIO, or let this manager auto-read it when the mastercontainer is running."
	return 0
}

save_passphrase_from_logs() {
	# Backward-compatible wrapper name used by do_install.
	save_passphrase_from_aio || prompt_for_passphrase_if_needed
}

signal_aio() {
	local env_name="$1"
	local description="$2"

	if ! container_running "${MASTER_CONTAINER}"; then
		warn "Master container is not running; cannot signal: ${description}"
		return 1
	fi

	info "${description}"
	docker exec --env "${env_name}=1" "${MASTER_CONTAINER}" /daily-backup.sh 2>/dev/null || true
}

#===============================================================================
#  MENU ACTIONS
#===============================================================================

#--- 1. Install ----------------------------------------------------------------
do_install() {
	local install_domain="${1:-}"
	header "Install Nextcloud AIO"
	require_root
	init_dirs
	config_init
	cleanup_rejected_passphrase
	prompt_for_domain "${install_domain}"
	preflight
	init_compose
	ensure_master_volume_dir

	info "Pulling Nextcloud AIO master container image..."
	docker pull ghcr.io/nextcloud-releases/all-in-one:latest

	info "Starting Nextcloud AIO via Docker Compose..."
	start_master_container
	wait_for_master 60

	sleep 5
	save_passphrase_from_logs

	config_set "installed" "true"
	config_set "install_date" "$(timestamp)"

	local domain=""
	domain="$(config_get domain)"

	echo ""
	header "Installation Complete"
	print_access_urls "${domain}"
	echo "  Config file                : ${CONFIG_FILE}"
	echo "  Data directory             : ${NCDATA_DIR}"
	echo "  AIO master volume path     : ${MASTER_VOLUME_DIR}"
	echo "  Logs                       : ${LOG_FILE}"
	echo ""
	info "Open the AIO interface via the public IP URL on port ${AIO_PORT_INTERFACE}, accept the self-signed certificate, and enter your passphrase."
	info "Use the domain TLS URL on port ${AIO_PORT_INTERFACE_TLS} only after DNS points here, firewall allows ${AIO_PORT_HTTP}/${AIO_PORT_INTERFACE_TLS}, and Let's Encrypt is not rate-limited."
}

#--- 2. Start ------------------------------------------------------------------
do_start() {
	header "Start Nextcloud AIO"
	require_root
	init_dirs
	config_init
	cleanup_rejected_passphrase
	init_compose
	ensure_master_volume_dir

	info "Ensuring mastercontainer exists and current compose settings are applied..."
	start_master_container
	wait_for_master 60

	save_passphrase_from_aio >/dev/null 2>&1 || true

	signal_aio "START_CONTAINERS" "Signaling AIO to start all sub-containers..." || true
	success "Start requested. Check status with: sudo $0 status"
}

#--- 3. Stop -------------------------------------------------------------------
do_stop() {
	header "Stop Nextcloud AIO"
	require_root

	if container_running "${MASTER_CONTAINER}"; then
		signal_aio "STOP_CONTAINERS" "Signaling AIO to stop all sub-containers..." || true
		success "Sub-container stop requested."

		if confirm "Also stop the master container?"; then
			docker_compose down
			success "Master container stopped."
		fi
	else
		warn "Master container is not running."
		if [[ -f "${COMPOSE_FILE}" ]] && confirm "Run docker compose down anyway?"; then
			docker_compose down || true
		fi
	fi
}

#--- 4. Restart ----------------------------------------------------------------
do_restart() {
	header "Restart Nextcloud AIO"
	require_root

	if container_running "${MASTER_CONTAINER}"; then
		signal_aio "STOP_CONTAINERS" "Signaling AIO to stop all sub-containers..." || true
		sleep 3
		docker_compose down || true
	fi

	do_start
}

#--- 5. Status -----------------------------------------------------------------
do_status() {
	header "Nextcloud AIO Status"

	echo "${BOLD}AIO Containers:${NC_COLOR}"
	if docker ps -a --filter "name=nextcloud-aio" --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | column -t -s $'\t'; then
		true
	else
		warn "No AIO containers found or Docker is unavailable."
	fi

	echo ""
	echo "${BOLD}Docker Resources:${NC_COLOR}"
	local vol_count="0"
	local net_count="0"
	vol_count="$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -c 'nextcloud_aio' || true)"
	net_count="$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -Ec 'nextcloud[-_]aio|nextcloud_d' || true)"
	echo "  Volumes : ${vol_count}"
	echo "  Networks: ${net_count}"

	echo ""
	show_master_volume_status

	echo ""
	if [[ -f "${CONFIG_FILE}" ]]; then
		local pass=""
		local domain=""
		pass="$(config_get aio_passphrase)"
		if [[ -z "${pass}" ]] || is_rejected_passphrase "${pass}"; then
			save_passphrase_from_aio >/dev/null 2>&1 || true
			pass="$(config_get aio_passphrase)"
		fi
		domain="$(config_get domain)"
		echo "${BOLD}Config (${CONFIG_FILE}):${NC_COLOR}"
		echo "  Installed    : $(config_get installed)"
		echo "  Install date : $(config_get install_date)"
		echo "  Domain       : ${domain:-<not set>}"
		echo "  Passphrase   : ${pass:-<not saved>}"
	fi

	echo ""
	echo "${BOLD}Access URLs:${NC_COLOR}"
	print_access_urls "$(config_get domain || true)"
}

#--- 6. Logs -------------------------------------------------------------------
do_logs() {
	header "Nextcloud AIO Logs"

	local choice="${1:-}"
	local target=""

	if [[ -z "${choice}" && -t 0 ]]; then
		echo "${BOLD}Select container:${NC_COLOR}"
		echo "  1) mastercontainer"
		echo "  2) nextcloud"
		echo "  3) database/postgresql"
		echo "  4) redis"
		echo "  5) apache"
		echo "  6) all AIO containers, brief"
		echo ""
		printf 'Choice [1]: '
		read -r choice || true
	fi

	case "${choice:-1}" in
	1 | master | mastercontainer) target="nextcloud-aio-mastercontainer" ;;
	2 | nextcloud) target="nextcloud-aio-nextcloud" ;;
	3 | database | postgres | postgresql) target="nextcloud-aio-database" ;;
	4 | redis) target="nextcloud-aio-redis" ;;
	5 | apache) target="nextcloud-aio-apache" ;;
	6 | all)
		local containers=""
		containers="$(docker ps -a --filter "name=nextcloud-aio" --format '{{.Names}}' 2>/dev/null || true)"
		if [[ -z "${containers}" ]]; then
			warn "No AIO containers found."
			return 0
		fi
		while IFS= read -r c; do
			[[ -n "${c}" ]] || continue
			printf '\n%b\n' "${CYAN}━━━ ${c} ━━━${NC_COLOR}"
			docker logs --tail 40 "${c}" 2>&1 || true
		done <<<"${containers}"
		return 0
		;;
	*) target="nextcloud-aio-mastercontainer" ;;
	esac

	if container_exists "${target}"; then
		docker logs --tail 150 -f "${target}" 2>&1
	else
		error "Container '${target}' not found."
	fi
}

#--- 7. Update -----------------------------------------------------------------
do_update() {
	header "Update Nextcloud AIO"
	require_root

	if ! container_running "${MASTER_CONTAINER}"; then
		fatal "Master container is not running. Start it first."
	fi

	signal_aio "AUTOMATIC_UPDATES" "Triggering automatic update of all containers..." || true

	info "Waiting for update process to complete..."
	local max_wait=300
	local waited=0
	while docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'nextcloud-aio-watchtower'; do
		sleep 10
		waited=$((waited + 10))
		if [[ ${waited} -ge ${max_wait} ]]; then
			warn "Watchtower is still running after ${max_wait}s. Check manually."
			break
		fi
	done

	sleep 10
	if container_running "${MASTER_CONTAINER}"; then
		signal_aio "AUTOMATIC_UPDATES" "Running a second update pass to ensure completeness..." || true
	fi

	success "Update process completed. Check the AIO interface for details."
}

#--- 8. Backup -----------------------------------------------------------------
do_backup() {
	header "Backup Nextcloud AIO"
	require_root

	if ! container_running "${MASTER_CONTAINER}"; then
		fatal "Master container must be running for backup."
	fi

	signal_aio "DAILY_BACKUP" "Triggering AIO backup. Containers may be stopped temporarily..." || true
	success "Backup requested. Check the AIO interface for backup details."
}

#--- 9. Set domain -------------------------------------------------------------
do_set_domain() {
	header "Set Domain"
	config_init

	local domain="${1:-}"
	if [[ -z "${domain}" && -t 0 ]]; then
		printf 'Enter your public domain, e.g. cloud.example.com: '
		read -r domain || true
	fi

	if [[ -z "${domain}" ]]; then
		warn "No domain entered."
		return 0
	fi

	if ! valid_domain_name "${domain}"; then
		fatal "Domain should be a hostname only, e.g. cloud.example.com"
	fi

	config_set "domain" "${domain}"
	success "Domain saved to config: ${domain}"
	check_domain_dns "${domain}" "$(public_ip || true)"
	info "Open the AIO interface and enter this domain there too."
}

#--- 10. Set passphrase --------------------------------------------------------
do_set_passphrase() {
	header "Save / Refresh AIO Passphrase"
	config_init

	local mode_or_value="${1:-}"
	local current=""
	current="$(config_get aio_passphrase)"
	if [[ -n "${current}" ]]; then
		if is_rejected_passphrase "${current}"; then
			warn "Current saved passphrase is invalid and will be removed: ${current}"
			config_set "aio_passphrase" ""
			current=""
		else
			info "Current saved passphrase in manager config: ${current}"
		fi
	fi

	case "${mode_or_value}" in
	auto | read | detect | get | refresh)
		if save_passphrase_from_aio; then
			return 0
		fi
		warn "Could not read the passphrase automatically. Open the AIO setup page and copy the shown passphrase, then run: sudo $0 passphrase '<passphrase>'"
		return 0
		;;
	show)
		local detected=""
		detected="$(read_passphrase_from_aio_config || true)"
		if [[ -n "${detected}" ]]; then
			print_passphrase_box "${detected}"
		else
			warn "Could not read passphrase from AIO configuration.json."
		fi
		return 0
		;;
	esac

	local passphrase="${mode_or_value}"
	if [[ -z "${passphrase}" ]]; then
		info "Trying to read the generated AIO passphrase automatically..."
		if save_passphrase_from_aio; then
			return 0
		fi
		if [[ -t 0 ]]; then
			printf 'Auto-read failed. Paste the real AIO passphrase shown in the browser, or press Enter to skip: '
			read -r passphrase || true
		fi
	fi

	passphrase="$(printf '%s' "${passphrase}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"

	if [[ -z "${passphrase}" ]]; then
		warn "No passphrase saved."
		return 0
	fi

	if [[ "${passphrase}" == "auto" ]]; then
		save_passphrase_from_aio || warn "Could not auto-read the passphrase."
		return 0
	fi

	save_discovered_passphrase "${passphrase}" "manual entry" || true
}

#--- 11. Run OCC command -------------------------------------------------------
do_occ() {
	header "Run Nextcloud OCC Command"
	require_root

	if ! container_running "${NC_CONTAINER}"; then
		fatal "Nextcloud container is not running."
	fi

	if [[ $# -gt 0 ]]; then
		info "Running: occ $*"
		docker exec --user www-data -it "${NC_CONTAINER}" php occ "$@"
	else
		local occ_cmd=""
		printf "Enter OCC command without 'occ' prefix: "
		read -r occ_cmd || true
		if [[ -n "${occ_cmd}" ]]; then
			info "Running: occ ${occ_cmd}"
			# Intentionally split an interactive OCC command line.
			# shellcheck disable=SC2086
			docker exec --user www-data -it "${NC_CONTAINER}" php occ ${occ_cmd}
		fi
	fi
}

#--- 12. Health check ----------------------------------------------------------
do_healthcheck() {
	header "Health Check"

	echo "${BOLD}Container Health:${NC_COLOR}"
	local all_ok=true
	for c in mastercontainer nextcloud database redis apache; do
		local full_name="nextcloud-aio-${c}"
		if container_running "${full_name}"; then
			echo "  ● ${full_name} — running"
		elif container_exists "${full_name}"; then
			echo "  ○ ${full_name} — stopped"
			all_ok=false
		else
			echo "  ✗ ${full_name} — not found"
			all_ok=false
		fi
	done

	echo ""
	echo "${BOLD}Disk Usage:${NC_COLOR}"
	df -h "${BASE_DIR}" 2>/dev/null | tail -1 | awk '{printf "  Total: %s  Used: %s  Avail: %s  Use%%: %s\n", $2, $3, $4, $5}' || true

	echo ""
	echo "${BOLD}Docker Disk Usage:${NC_COLOR}"
	docker system df 2>/dev/null | sed 's/^/  /' || true

	echo ""
	echo "${BOLD}Memory:${NC_COLOR}"
	free -h 2>/dev/null | head -2 | sed 's/^/  /' || true

	echo ""
	show_master_volume_status

	echo ""
	if ${all_ok}; then
		success "All core containers are running."
	else
		warn "Some containers are not running. Check the AIO interface and logs."
	fi
}

#--- 443 conflict diagnostics / repair ----------------------------------------
container_publishing_host_port() {
	local port="$1"
	docker ps --format '{{.ID}}	{{.Names}}	{{.Ports}}' 2>/dev/null |
		awk -v p=":${port}->" 'index($0,p) {print}'
}

non_aio_containers_publishing_port() {
	local port="$1"
	container_publishing_host_port "${port}" | awk '$2 !~ /^nextcloud-aio/ {print}'
}

systemd_unit_active() {
	command_exists systemctl || return 1
	systemctl is-active --quiet "$1" 2>/dev/null
}

show_443_owners() {
	echo "${BOLD}Host TCP 443 listeners:${NC_COLOR}"
	show_port_listener "${NEXTCLOUD_HTTPS_PORT}"

	echo ""
	echo "${BOLD}Docker containers publishing host 443:${NC_COLOR}"
	local docker_owners=""
	docker_owners="$(container_publishing_host_port "${NEXTCLOUD_HTTPS_PORT}" || true)"
	if [[ -n "${docker_owners}" ]]; then
		printf '%s
' "${docker_owners}" | sed 's/^/  /'
	else
		echo "  <none detected>"
	fi

	echo ""
	echo "${BOLD}Common host web services:${NC_COLOR}"
	local svc=""
	local found=false
	for svc in nginx apache2 httpd caddy traefik haproxy; do
		if systemd_unit_active "${svc}"; then
			echo "  ${svc}: active"
			found=true
		fi
	done
	if ! ${found}; then
		echo "  <none of nginx/apache2/httpd/caddy/traefik/haproxy active via systemd>"
	fi
}

do_443_status() {
	header "Port 443 / Domaincheck Status"
	show_443_owners
	echo ""
	if port_in_use_tcp "${NEXTCLOUD_HTTPS_PORT}" && ! aio_container_uses_host_port "${NEXTCLOUD_HTTPS_PORT}"; then
		warn "Port 443 is already owned by a non-AIO service. AIO domaincheck/apache cannot bind it in integrated mode."
		echo ""
		echo "Use one of these two valid designs:"
		echo "  1) Integrated AIO: free host port 443, then let AIO bind it."
		echo "  2) External reverse proxy: keep your proxy on 443, set AIO Apache to 11000, and proxy DOMAIN -> localhost:11000."
		return 1
	fi
	success "No non-AIO TCP 443 listener detected. AIO should be able to bind 443 when it creates the apache/domaincheck container."
}

do_fix_443() {
	header "Interactive Port 443 Fix"
	require_root
	do_443_status || true

	if ! port_in_use_tcp "${NEXTCLOUD_HTTPS_PORT}" || aio_container_uses_host_port "${NEXTCLOUD_HTTPS_PORT}"; then
		success "No non-AIO service is blocking port 443."
		return 0
	fi

	echo ""
	warn "This helper can stop common host web servers and non-AIO Docker containers that publish host 443. It will not delete data."

	local non_aio=""
	non_aio="$(non_aio_containers_publishing_port "${NEXTCLOUD_HTTPS_PORT}" || true)"
	if [[ -n "${non_aio}" ]]; then
		echo ""
		echo "${BOLD}Non-AIO Docker containers publishing 443:${NC_COLOR}"
		printf '%s
' "${non_aio}" | sed 's/^/  /'
		if confirm "Stop these non-AIO Docker containers now?"; then
			printf '%s
' "${non_aio}" | awk '{print $1}' | while read -r cid; do
				[[ -n "${cid}" ]] || continue
				docker stop "${cid}" || true
			done
		fi
	fi

	if command_exists systemctl; then
		local active_services=()
		local svc=""
		for svc in nginx apache2 httpd caddy traefik haproxy; do
			if systemd_unit_active "${svc}"; then
				active_services+=("${svc}")
			fi
		done
		if [[ ${#active_services[@]} -gt 0 ]]; then
			echo ""
			echo "${BOLD}Active host web services:${NC_COLOR} ${active_services[*]}"
			if confirm "Stop these host web services now?"; then
				for svc in "${active_services[@]}"; do
					systemctl stop "${svc}" || true
				done
				if confirm "Disable these services at boot so they do not retake port 443 after reboot?"; then
					for svc in "${active_services[@]}"; do
						systemctl disable "${svc}" || true
					done
				fi
			fi
		fi
	fi

	echo ""
	do_443_status || true
	if ! port_in_use_tcp "${NEXTCLOUD_HTTPS_PORT}" || aio_container_uses_host_port "${NEXTCLOUD_HTTPS_PORT}"; then
		success "Port 443 is no longer blocked by a non-AIO service. Restart/start AIO, then retry domain validation in the browser."
	else
		warn "Port 443 is still blocked. Review the listener details above."
	fi
}

#--- Access URL / network diagnostics -----------------------------------------
do_ports() {
	header "AIO Port Plan"
	show_port_purposes
	echo ""
	echo "${BOLD}Notes:${NC_COLOR}"
	echo "  - Port ${AIO_PORT_HTTP} must be reachable from the internet for the built-in ACME HTTP-01 certificate flow."
	echo "  - Port ${AIO_PORT_INTERFACE} is the IP-only, self-signed admin interface. Do not use a domain here because HSTS can block later access."
	echo "  - Port ${AIO_PORT_INTERFACE_TLS} is the domain admin interface with a public certificate."
	echo "  - Port ${NEXTCLOUD_HTTPS_PORT} must be free for the final Nextcloud website in integrated mode. ${AIO_PORT_INTERFACE_TLS} does not replace it."
	echo "  - If port ${NEXTCLOUD_HTTPS_PORT} is already used, either free it or switch to a proper external reverse proxy design with AIO Apache on 11000."
}

do_urls() {
	header "Access URLs"
	config_init
	print_access_urls "$(config_get domain || true)"
}

http_probe() {
	local label="$1"
	local url="$2"
	local extra_args=()
	shift 2 || true
	extra_args=("$@")

	if ! command_exists curl; then
		warn "curl not found; cannot probe ${label}."
		return 0
	fi

	local code=""
	code="$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "${extra_args[@]}" "${url}" 2>/dev/null || printf '000')"
	if [[ "${code}" == "000" ]]; then
		warn "${label}: failed to connect (${url})"
	else
		success "${label}: HTTP ${code} (${url})"
	fi
}

show_port_listener() {
	local port="$1"
	if command_exists ss; then
		if ss -H -tlnp 2>/dev/null | awk '{print $4, $6}' | grep -Eq "(^|[.:])${port}[[:space:]]"; then
			echo "  TCP ${port}: listening"
			ss -H -tlnp 2>/dev/null | grep -E "(^|[.:])${port}[[:space:]]" | sed 's/^/    /' || true
		else
			echo "  TCP ${port}: not listening"
		fi
	else
		echo "  TCP ${port}: cannot check; ss not installed"
	fi
}

show_letsencrypt_errors() {
	if ! container_exists "${MASTER_CONTAINER}"; then
		return 0
	fi

	local errors=""
	errors="$(docker logs --tail 500 "${MASTER_CONTAINER}" 2>&1 | grep -Ei 'rateLimited|too many certificates|retry after|could not get certificate|tls\.obtain' | tail -20 || true)"
	if [[ -n "${errors}" ]]; then
		echo ""
		echo "${BOLD}Recent certificate errors:${NC_COLOR}"
		printf '%s\n' "${errors}" | sed 's/^/  /'
		warn "The domain TLS interface will not be reliable until these certificate errors are resolved. Use the IP URL on port ${AIO_PORT_INTERFACE} meanwhile."
	fi
}

do_diagnose() {
	header "Network / Certificate Diagnostics"
	config_init

	local domain=""
	local pub=""
	local local_ip=""
	domain="$(config_get domain || true)"
	pub="$(public_ip || true)"
	local_ip="$(primary_local_ip)"

	print_access_urls "${domain}"

	echo ""
	echo "${BOLD}Docker port mapping:${NC_COLOR}"
	docker ps --filter "name=${MASTER_CONTAINER}" --format '  {{.Names}}  {{.Ports}}' 2>/dev/null || true

	echo ""
	echo "${BOLD}Local TCP listeners:${NC_COLOR}"
	for p in "${AIO_PORT_HTTP}" "${AIO_PORT_INTERFACE}" "${AIO_PORT_INTERFACE_TLS}" "${NEXTCLOUD_HTTPS_PORT}"; do
		show_port_listener "${p}"
	done

	echo ""
	echo "${BOLD}HTTP probes from this server:${NC_COLOR}"
	http_probe "AIO self-signed via localhost" "https://127.0.0.1:${AIO_PORT_INTERFACE}/"
	if [[ -n "${pub}" ]]; then
		http_probe "AIO self-signed via public IP" "https://${pub}:${AIO_PORT_INTERFACE}/"
	fi
	if [[ -n "${domain}" ]]; then
		http_probe "AIO valid-cert port via local SNI" "https://${domain}:${AIO_PORT_INTERFACE_TLS}/" --resolve "${domain}:${AIO_PORT_INTERFACE_TLS}:127.0.0.1"
		http_probe "AIO valid-cert port via public DNS" "https://${domain}:${AIO_PORT_INTERFACE_TLS}/"
	fi

	show_letsencrypt_errors

	echo ""
	show_443_owners

	echo ""
	echo "${BOLD}Interpretation:${NC_COLOR}"
	echo "  - Use https://PUBLIC_IP:${AIO_PORT_INTERFACE} for the first AIO login. Do not use a domain on this self-signed interface."
	echo "  - Use https://DOMAIN:${AIO_PORT_INTERFACE_TLS} only after DNS, cloud firewall, host firewall, port ${AIO_PORT_HTTP}, and Let's Encrypt are OK."
	echo "  - If Let's Encrypt shows HTTP 429 rate limiting, waiting for the retry-after time is required for that domain certificate."
	echo "  - If TCP ${NEXTCLOUD_HTTPS_PORT} is already in use by a non-AIO service, the domaincheck container fails with 'address already in use'. Run: sudo $0 443-status"
	echo "  - ${AIO_PORT_INTERFACE_TLS} is only the AIO admin interface with a valid certificate. It is not a replacement for the final Nextcloud HTTPS port 443."
}

#--- Final Nextcloud HTTPS diagnostics / repair --------------------------------
container_status_one() {
	local name="$1"
	if container_running "${name}"; then
		echo "  ${name}: running"
	elif container_exists "${name}"; then
		echo "  ${name}: exists but not running"
	else
		echo "  ${name}: not found"
	fi
}

print_container_ports() {
	local name="$1"
	if container_exists "${name}"; then
		local ports=""
		ports="$(docker port "${name}" 2>/dev/null || true)"
		if [[ -n "${ports}" ]]; then
			printf '%s\n' "${ports}" | sed "s/^/  ${name}: /"
		else
			echo "  ${name}: <no published host ports>"
		fi
	else
		echo "  ${name}: <container not found>"
	fi
}

curl_probe_detail() {
	local label="$1"
	local url="$2"
	shift 2 || true

	if ! command_exists curl; then
		warn "curl not found; cannot probe ${label}."
		return 2
	fi

	local output=""
	local rc=0
	output="$(curl -k -sS -I --connect-timeout 5 --max-time 12 -w '\nCURL_HTTP_CODE=%{http_code}\nCURL_REMOTE_IP=%{remote_ip}\n' "$@" "${url}" 2>&1)" || rc=$?

	echo "${BOLD}${label}:${NC_COLOR} ${url}"
	if [[ ${rc} -eq 0 ]]; then
		local code=""
		code="$(printf '%s\n' "${output}" | awk -F= '/^CURL_HTTP_CODE=/ {print $2}' | tail -1)"
		if [[ "${code}" =~ ^(200|301|302|303|307|308|401|403)$ ]]; then
			success "${label}: TLS/HTTP path responded with HTTP ${code}."
		else
			warn "${label}: connected but returned HTTP ${code:-unknown}."
		fi
		printf '%s\n' "${output}" | sed -n '1,12p' | sed 's/^/  /'
		return 0
	fi

	warn "${label}: curl failed with exit code ${rc}."
	printf '%s\n' "${output}" | sed -n '1,20p' | sed 's/^/  /'
	return ${rc}
}

probe_plain_http_on_443() {
	if ! command_exists curl; then
		return 0
	fi

	local code=""
	code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 6 "http://127.0.0.1:${NEXTCLOUD_HTTPS_PORT}/" 2>/dev/null || printf '000')"
	if [[ "${code}" != "000" ]]; then
		warn "Host port 443 answered plain HTTP with code ${code}. Browsers using https:// will show ERR_SSL_PROTOCOL_ERROR against a plain-HTTP listener."
	fi
}

probe_tls_handshake_443() {
	local domain="$1"
	if ! command_exists openssl; then
		return 0
	fi

	echo ""
	echo "${BOLD}TLS handshake probe on localhost:443:${NC_COLOR}"
	local out=""
	local rc=0
	out="$(timeout 8 openssl s_client -connect "127.0.0.1:${NEXTCLOUD_HTTPS_PORT}" -servername "${domain}" -brief </dev/null 2>&1)" || rc=$?
	if [[ ${rc} -eq 0 ]] && printf '%s\n' "${out}" | grep -Eiq 'Protocol version|Ciphersuite|Verification'; then
		success "TLS handshake completed on localhost:443 for SNI ${domain}."
		printf '%s\n' "${out}" | sed -n '1,12p' | sed 's/^/  /'
	else
		warn "TLS handshake failed on localhost:443 for SNI ${domain}."
		printf '%s\n' "${out}" | sed -n '1,18p' | sed 's/^/  /'
	fi
}

show_recent_aio_https_logs() {
	echo ""
	echo "${BOLD}Recent relevant AIO logs:${NC_COLOR}"
	for c in nextcloud-aio-apache nextcloud-aio-nextcloud nextcloud-aio-mastercontainer; do
		if container_exists "${c}"; then
			echo "  --- ${c} ---"
			docker logs --tail 120 "${c}" 2>&1 |
				grep -Ei 'error|warn|crit|fail|ssl|tls|cert|acme|domain|apache|listening|AH[0-9]+' |
				tail -30 |
				sed 's/^/    /' || true
		fi
	done
}

final_nextcloud_local_tls_ok() {
	local domain="$1"
	command_exists curl || return 1
	local code=""
	code="$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
		--resolve "${domain}:${NEXTCLOUD_HTTPS_PORT}:127.0.0.1" \
		"https://${domain}/" 2>/dev/null || printf '000')"
	[[ "${code}" =~ ^(200|301|302|303|307|308|401|403)$ ]]
}

do_nextcloud_https_diagnose() {
	local domain_arg="${1:-}"
	header "Final Nextcloud HTTPS Diagnostic"
	config_init

	local domain="${domain_arg}"
	if [[ -z "${domain}" ]]; then
		domain="$(config_get domain || true)"
	fi
	if [[ -z "${domain}" && -t 0 ]]; then
		printf 'Enter the Nextcloud domain, e.g. cloud.example.com: '
		read -r domain || true
	fi
	if [[ -z "${domain}" ]]; then
		fatal "No domain configured. Run: sudo $0 domain your.domain.tld"
	fi

	echo "${BOLD}Target:${NC_COLOR} https://${domain}"
	echo "${BOLD}AIO admin page:${NC_COLOR} https://${domain}:${AIO_PORT_INTERFACE_TLS}/containers"
	echo ""

	local pub=""
	pub="$(public_ip || true)"
	check_domain_dns "${domain}" "${pub}"

	echo ""
	echo "${BOLD}Core container state:${NC_COLOR}"
	container_status_one "${MASTER_CONTAINER}"
	container_status_one "${NC_CONTAINER}"
	container_status_one "nextcloud-aio-apache"
	container_status_one "nextcloud-aio-database"
	container_status_one "nextcloud-aio-redis"

	echo ""
	echo "${BOLD}Published ports:${NC_COLOR}"
	print_container_ports "${MASTER_CONTAINER}"
	print_container_ports "nextcloud-aio-apache"

	echo ""
	show_443_owners
	echo ""
	probe_plain_http_on_443

	echo ""
	echo "${BOLD}Local HTTPS probes:${NC_COLOR}"
	curl_probe_detail "Final Nextcloud via local SNI" "https://${domain}/" --resolve "${domain}:${NEXTCLOUD_HTTPS_PORT}:127.0.0.1" || true
	if [[ -n "${pub}" ]]; then
		curl_probe_detail "Final Nextcloud via public DNS" "https://${domain}/" || true
	fi
	probe_tls_handshake_443 "${domain}"

	show_recent_aio_https_logs

	echo ""
	echo "${BOLD}Interpretation:${NC_COLOR}"
	if ! container_running "nextcloud-aio-apache"; then
		warn "The final Nextcloud HTTPS service is not up because nextcloud-aio-apache is not running. The AIO admin UI can still work on ${AIO_PORT_INTERFACE_TLS}, but the Open Nextcloud button will fail."
		echo "  Next step: open the AIO page, check stopped/failed containers, or run: sudo $0 start"
	elif port_in_use_tcp "${NEXTCLOUD_HTTPS_PORT}" && ! aio_container_uses_host_port "${NEXTCLOUD_HTTPS_PORT}"; then
		warn "Host port 443 is owned by a non-AIO service. This commonly causes ERR_SSL_PROTOCOL_ERROR or AIO domaincheck failures."
		echo "  Next step: run: sudo $0 fix-443"
	elif container_running "nextcloud-aio-apache" && ! aio_container_uses_host_port "${NEXTCLOUD_HTTPS_PORT}"; then
		warn "AIO Apache is running but does not publish host port 443. This usually means reverse-proxy mode/APACHE_PORT was used, or the Apache container was created with unexpected settings."
		echo "  Integrated mode fix: stop AIO containers in the web UI, remove reverse-proxy APACHE_PORT settings from compose, restart the mastercontainer, then start containers again."
		echo "  Reverse-proxy mode fix: make your proxy on 443 forward HTTP to the configured APACHE_PORT, usually http://127.0.0.1:11000."
	elif final_nextcloud_local_tls_ok "${domain}"; then
		success "The final Nextcloud site responds correctly from the host using local SNI. If your browser still fails externally, the likely problem is public DNS, VPS/cloud firewall, upstream proxy/CDN, or local browser cache/HSTS."
	else
		warn "AIO appears to own port 443, but local TLS/HTTP probing failed. Check the Apache logs printed above and try a container restart from the AIO interface."
	fi
}

do_fix_nextcloud_https() {
	local domain="${1:-}"
	header "Interactive Fix: Open Nextcloud HTTPS"
	require_root
	do_nextcloud_https_diagnose "${domain}" || true

	echo ""
	if port_in_use_tcp "${NEXTCLOUD_HTTPS_PORT}" && ! aio_container_uses_host_port "${NEXTCLOUD_HTTPS_PORT}"; then
		if confirm "Run the interactive port-443 fixer now?"; then
			do_fix_443
		fi
		return 0
	fi

	if ! container_running "nextcloud-aio-apache"; then
		if confirm "Signal AIO to start all sub-containers now?"; then
			signal_aio "START_CONTAINERS" "Signaling AIO to start all sub-containers..." || true
			sleep 8
			do_nextcloud_https_diagnose "${domain}" || true
		fi
		return 0
	fi

	if container_running "nextcloud-aio-apache" && ! final_nextcloud_local_tls_ok "${domain:-$(config_get domain || true)}"; then
		if confirm "Restart only the AIO Apache gateway container now?"; then
			docker restart nextcloud-aio-apache >/dev/null 2>&1 || true
			sleep 8
			do_nextcloud_https_diagnose "${domain}" || true
		fi
	else
		success "No automatic local fix is indicated. The host-side HTTPS path looks healthy; check public firewall/DNS/proxy if browser access still fails."
	fi
}

#--- 13. Show config -----------------------------------------------------------
do_show_config() {
	header "Current Configuration"

	if [[ -f "${CONFIG_FILE}" ]]; then
		cat "${CONFIG_FILE}"
	else
		warn "Config file not found at ${CONFIG_FILE}"
		info "Run 'install' to generate it."
	fi
}

#--- 14. Edit compose ----------------------------------------------------------
do_edit_compose() {
	header "Edit docker-compose.yml"

	local editor="${EDITOR:-nano}"
	command_exists "${editor}" || editor="vi"

	if [[ -f "${COMPOSE_FILE}" ]]; then
		"${editor}" "${COMPOSE_FILE}"
		info "If you changed ports or environment, restart with: sudo $0 restart"
	else
		error "Compose file not found. Run 'install' first."
	fi
}

#--- 15. Migration helper ------------------------------------------------------
do_migrate_info() {
	header "Migration Guide"

	cat <<EOF2
To migrate this Nextcloud AIO instance to another VPS:

1. Stop all containers first:
   ${BOLD}sudo $0 stop${NC_COLOR}

2. Copy the whole manager directory to the new VPS:
   ${BOLD}rsync -avzP ${BASE_DIR}/ user@NEW_VPS:${BASE_DIR}/${NC_COLOR}

3. On the new VPS, install Docker if needed, then start AIO:
   ${BOLD}cd ${BASE_DIR} && sudo ./Nextcloud_AIO_manager.sh start${NC_COLOR}

4. The AIO interface will be at:
   ${BOLD}https://NEW_VPS_IP:${AIO_PORT_INTERFACE}${NC_COLOR}

5. Update DNS to point your domain to the new VPS IP.

Notes:
  - Manager config is saved in: ${CONFIG_FILE}
  - Nextcloud data dir is: ${NCDATA_DIR}
  - Manager-created AIO master volume bind path is: ${MASTER_VOLUME_DIR}
  - If this system already had a Docker-managed AIO volume before this fixed
    script was installed, use 'sudo $0 volume-status' to see where it lives.
  - AIO's built-in BorgBackup restore remains the safest migration method for
    production servers.
EOF2
}

#--- 16. Reset instance --------------------------------------------------------
do_reset() {
	header "Reset Nextcloud AIO Instance"
	require_root

	echo "${RED}${BOLD}WARNING: This will delete AIO containers, AIO Docker volumes, and ${NCDATA_DIR}.${NC_COLOR}"
	echo "Backups under ${BACKUP_DIR} are kept."
	echo ""

	if ! confirm_phrase "RESET" "This is destructive and cannot be undone."; then
		info "Aborted."
		return 0
	fi

	info "Stopping all AIO containers..."
	if container_running "${MASTER_CONTAINER}"; then
		docker exec --env STOP_CONTAINERS=1 "${MASTER_CONTAINER}" /daily-backup.sh 2>/dev/null || true
		sleep 5
	fi

	if [[ -f "${COMPOSE_FILE}" ]]; then
		docker_compose down 2>/dev/null || true
	fi

	local containers=""
	containers="$(docker ps -a --filter "name=nextcloud-aio" --format '{{.Names}}' 2>/dev/null || true)"
	while IFS= read -r c; do
		[[ -n "${c}" ]] || continue
		docker stop "${c}" 2>/dev/null || true
		docker rm "${c}" 2>/dev/null || true
	done <<<"${containers}"

	info "Removing AIO Docker volumes..."
	local volumes=""
	volumes="$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '^nextcloud_aio|^nextcloud-aio' || true)"
	while IFS= read -r v; do
		[[ -n "${v}" ]] || continue
		docker volume rm "${v}" 2>/dev/null || true
	done <<<"${volumes}"

	docker network rm nextcloud-aio nextcloud_d_default 2>/dev/null || true

	rm -rf --one-file-system "${NCDATA_DIR}"
	rm -rf --one-file-system "${MASTER_VOLUME_DIR}"
	mkdir -p "${NCDATA_DIR}" "${MASTER_VOLUME_DIR}"

	if [[ -f "${CONFIG_FILE}" ]]; then
		config_set "installed" "false"
		config_set "aio_passphrase" ""
		config_set "admin_user" ""
		config_set "admin_password" ""
	fi

	success "Instance reset complete. Run: sudo $0 install"
}

#--- 17. Volume repair ---------------------------------------------------------
do_repair_volume() {
	header "Repair / Validate AIO Master Volume"
	require_root
	init_dirs
	ensure_master_volume_dir
	show_master_volume_status
	success "Volume path validation complete."
}

#--- 18. AIO web UI next-step guide -------------------------------------------
do_next_steps() {
	header "Next AIO Web UI Steps"
	config_init
	cleanup_rejected_passphrase
	save_passphrase_from_aio >/dev/null 2>&1 || true

	local domain=""
	local pass=""
	local mem=""
	local mem_floor="0"
	local cores=""
	local tz_recommend="Asia/Tokyo"
	domain="$(config_get domain || true)"
	pass="$(config_get aio_passphrase || true)"
	mem="$(memory_gib)"
	mem_floor="$(memory_gib_int_floor)"
	cores="$(cpu_cores)"

	echo "${BOLD}Detected:${NC_COLOR}"
	echo "  Domain saved      : ${domain:-<not set>}"
	echo "  AIO passphrase    : ${pass:-<not saved/readable>}"
	echo "  RAM               : ${mem} GiB"
	echo "  CPU cores         : ${cores}"
	echo "  Suggested timezone: ${tz_recommend}"
	echo ""

	echo "${BOLD}Before clicking the big AIO start/download button:${NC_COLOR}"
	echo "  1) Make sure DNS for ${domain:-your-domain} points to this VPS public IP."
	echo "  2) Make sure host port 443 is free for integrated AIO mode."
	if port_in_use_tcp "${NEXTCLOUD_HTTPS_PORT}" && ! aio_container_uses_host_port "${NEXTCLOUD_HTTPS_PORT}"; then
		warn "Port 443 is currently occupied by a non-AIO service. Do not continue in the browser yet. Run: sudo $0 fix-443"
	else
		success "No non-AIO TCP 443 blocker detected from this host."
	fi
	echo "  3) Make sure the cloud/VPS firewall allows these ports:"
	firewall_hint
	echo ""

	echo "${BOLD}Recommended choices on the AIO screen you are viewing:${NC_COLOR}"
	echo "  - Install current Nextcloud Hub release: enabled."
	echo "  - Office Suite: choose Nextcloud Office for the best integrated default."
	echo "  - Timezone: set ${tz_recommend} if your users are mainly in Japan; keep Asia/Shanghai only if that is your user timezone."
	echo "  - Community Containers: leave disabled for the first boot. Add them later after the core stack is healthy."
	echo ""

	echo "${BOLD}Optional containers - safe first-boot recommendation:${NC_COLOR}"
	echo "  - Imaginary: enable if you want better previews for HEIC/HEIF/PDF/SVG/TIFF/WebP."
	echo "  - Nextcloud Talk: enable only if TCP+UDP ${TALK_PORT} are open/forwarded."
	echo "  - ClamAV: leave disabled unless you have enough RAM and specifically need server-side antivirus scanning."
	echo "  - Fulltextsearch: leave disabled on first boot; enable later if you need content indexing and have spare RAM/CPU."
	echo "  - Talk Recording-server: leave disabled unless Talk is already working and you have extra CPU/RAM."
	echo "  - Docker Socket Proxy: leave disabled; AIO marks it deprecated in favor of HaRP."
	echo "  - HaRP: leave disabled unless you plan to use Nextcloud ExApps/App API."
	echo "  - Whiteboard: optional; enable later after the main install works."
	echo ""

	if [[ "${mem_floor}" -lt 3 ]]; then
		warn "This VPS appears to have less than 3 GiB RAM. Start minimal: Nextcloud Office off or only Office + no ClamAV/Fulltextsearch/Talk Recording."
	elif [[ "${mem_floor}" -lt 5 ]]; then
		warn "This VPS has moderate RAM. Avoid ClamAV, Fulltextsearch, and Talk Recording on first boot."
	else
		success "RAM looks sufficient for a normal AIO install, but still add heavy optional containers gradually."
	fi

	echo ""
	echo "${BOLD}Then in the browser:${NC_COLOR}"
	echo "  1) Click Save changes after choosing optional containers/timezone."
	echo "  2) Click the button to download/start containers."
	echo "  3) Wait until all containers show healthy/running. This can take several minutes."
	echo "  4) Copy the initial Nextcloud admin password shown by AIO. This is different from the AIO passphrase."
	echo "  5) Open Nextcloud at: https://${domain:-<your-domain>}"
	echo "  6) If the browser shows ERR_SSL_PROTOCOL_ERROR, run: sudo $0 nextcloud-status ${domain:-your-domain}"
	echo ""
	echo "${BOLD}After first login:${NC_COLOR}"
	echo "  - Run: sudo $0 status"
	echo "  - Run: sudo $0 health"
	echo "  - Create the first backup from the AIO interface before adding heavy optional containers."
}

#===============================================================================
#  MENU
#===============================================================================
show_menu() {
	echo ""
	printf '%b\n' "${BOLD}${CYAN}╔═══════════════════════════════════════════════╗${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║         Nextcloud AIO Manager                ║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}╠═══════════════════════════════════════════════╣${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}1)${NC_COLOR}  Install Nextcloud AIO                  ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}2)${NC_COLOR}  Start containers                       ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}3)${NC_COLOR}  Stop containers                        ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}4)${NC_COLOR}  Restart containers                     ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}5)${NC_COLOR}  Status                                 ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}6)${NC_COLOR}  View logs                              ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}7)${NC_COLOR}  Update all containers                  ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}8)${NC_COLOR}  Create backup                          ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}9)${NC_COLOR}  Set domain                             ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}10)${NC_COLOR}  Read/save AIO passphrase               ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}11)${NC_COLOR}  Run OCC command                        ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}12)${NC_COLOR}  Health check                           ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}13)${NC_COLOR}  Show access URLs / public IP           ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}14)${NC_COLOR}  Network/certificate diagnostics        ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}15)${NC_COLOR}  Final Nextcloud HTTPS diagnostic       ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}16)${NC_COLOR}  Fix Open Nextcloud HTTPS               ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}17)${NC_COLOR}  Explain/check AIO ports                ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}18)${NC_COLOR}  Next AIO web UI steps                  ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}19)${NC_COLOR}  Port 443/domaincheck status            ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}20)${NC_COLOR}  Fix port 443 blocker                   ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}21)${NC_COLOR}  Show config                            ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}22)${NC_COLOR}  Edit docker-compose.yml                ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}23)${NC_COLOR}  Migration guide                        ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${GREEN}24)${NC_COLOR}  Repair/check AIO volume                ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR} ${RED}25)${NC_COLOR}  Reset instance (DANGER)                ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}║${NC_COLOR}  ${GREEN}0)${NC_COLOR}  Exit                                   ${BOLD}${CYAN}║${NC_COLOR}"
	printf '%b\n' "${BOLD}${CYAN}╚═══════════════════════════════════════════════╝${NC_COLOR}"
	echo ""
}

interactive_menu() {
	while true; do
		show_menu
		printf '%b' "${BOLD}Select option: ${NC_COLOR}"
		local choice=""
		read -r choice || exit 0
		case "${choice}" in
		1) do_install ;;
		2) do_start ;;
		3) do_stop ;;
		4) do_restart ;;
		5) do_status ;;
		6) do_logs ;;
		7) do_update ;;
		8) do_backup ;;
		9) do_set_domain ;;
		10) do_set_passphrase auto || do_set_passphrase ;;
		11) do_occ ;;
		12) do_healthcheck ;;
		13) do_urls ;;
		14) do_diagnose ;;
		15) do_nextcloud_https_diagnose ;;
		16) do_fix_nextcloud_https ;;
		17) do_ports ;;
		18) do_next_steps ;;
		19) do_443_status ;;
		20) do_fix_443 ;;
		21) do_show_config ;;
		22) do_edit_compose ;;
		23) do_migrate_info ;;
		24) do_repair_volume ;;
		25) do_reset ;;
		0 | q | quit | exit)
			echo "Bye!"
			exit 0
			;;
		*) warn "Invalid option: ${choice}" ;;
		esac

		echo ""
		printf '%b' "${YELLOW}Press Enter to continue...${NC_COLOR}"
		read -r _ || true
	done
}

#===============================================================================
#  CLI ENTRY POINT
#===============================================================================
usage() {
	cat <<EOF3
Usage: $(basename "$0") [command] [args...]

Commands:
  install [domain]     Install Nextcloud AIO and optionally save public domain
  start                Start all containers
  stop                 Stop all containers
  restart              Restart all containers
  status               Show container, config, and volume status
  logs [target]         View logs. Targets: master, nextcloud, database, redis, apache, all
  update               Update all AIO containers
  backup               Create an AIO backup
  domain [hostname]     Set your public domain
  passphrase auto       Read generated AIO passphrase from configuration.json
  passphrase [value]    Save/update manager copy of the real AIO passphrase
  passphrase show       Print generated AIO passphrase if readable
  occ [cmd...]          Run Nextcloud OCC command
  health               Run health check
  urls                 Show correct public-IP and domain access URLs
  ports                Explain/check AIO port usage
  next                 Show exactly what to choose on the current AIO web UI screen
  nextcloud-status     Diagnose final Nextcloud HTTPS on https://DOMAIN
  fix-nextcloud        Interactively fix the Open Nextcloud HTTPS path when possible
  443-status           Show what is using host port 443
  fix-443              Interactively stop common non-AIO services using host 443
  diagnose             Run network and certificate diagnostics
  config               Show current config
  edit                 Edit docker-compose.yml
  migrate              Show migration guide
  volume-status        Show AIO master volume status
  repair-volume        Create missing AIO master volume bind paths
  reset                Full reset (DANGER — deletes instance data)
  help                 Show this help

No command launches the interactive menu.

Examples:
  sudo ./Nextcloud_AIO_manager.sh install gcp.zhulei.eu.org
  sudo ./Nextcloud_AIO_manager.sh repair-volume
  sudo ./Nextcloud_AIO_manager.sh passphrase
  sudo ./Nextcloud_AIO_manager.sh 443-status
  sudo ./Nextcloud_AIO_manager.sh nextcloud-status sg.zhulei.eu.org
  sudo ./Nextcloud_AIO_manager.sh fix-nextcloud sg.zhulei.eu.org
  sudo ./Nextcloud_AIO_manager.sh next
  sudo ./Nextcloud_AIO_manager.sh start
  sudo ./Nextcloud_AIO_manager.sh occ files:scan --all
  sudo ./Nextcloud_AIO_manager.sh status
EOF3
}

main() {
	if [[ $# -eq 0 ]]; then
		interactive_menu
		exit 0
	fi

	local cmd="$1"
	shift || true

	case "${cmd}" in
	install) do_install "${1:-}" ;;
	start) do_start ;;
	stop) do_stop ;;
	restart) do_restart ;;
	status) do_status ;;
	logs) do_logs "${1:-}" ;;
	update) do_update ;;
	backup) do_backup ;;
	domain) do_set_domain "${1:-}" ;;
	passphrase) do_set_passphrase "${1:-}" ;;
	occ) do_occ "$@" ;;
	health) do_healthcheck ;;
	urls) do_urls ;;
	ports) do_ports ;;
	next | next-steps | setup-guide | ui-guide) do_next_steps ;;
	nextcloud-status | site-status | check-nextcloud | check-site) do_nextcloud_https_diagnose "${1:-}" ;;
	fix-nextcloud | fix-site | open-nextcloud-fix) do_fix_nextcloud_https "${1:-}" ;;
	443-status | port-443 | domaincheck) do_443_status ;;
	fix-443 | free-443) do_fix_443 ;;
	diagnose) do_diagnose ;;
	config) do_show_config ;;
	edit) do_edit_compose ;;
	migrate) do_migrate_info ;;
	volume-status) show_master_volume_status ;;
	repair-volume) do_repair_volume ;;
	reset) do_reset ;;
	help | -h | --help) usage ;;
	*)
		error "Unknown command: ${cmd}"
		usage
		exit 1
		;;
	esac
}

main "$@"
