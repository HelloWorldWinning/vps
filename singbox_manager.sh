#!/usr/bin/env bash
#
# singbox_manager.sh - interactive Docker Compose manager for superng6/singbox:latest
#
#   bash singbox_manager.sh
#
# TLS policy:
#   Certificates are managed by HOST acme.sh. This script only lets you pick ONE
#   existing acme.sh domain, then uses acme.sh --install-cert to copy/link the
#   selected fullchain/key into /root/singbox/certs. Future acme renewals will
#   restart the sing-box container through the acme.sh reloadcmd.
#
# Default VPS-side inbounds:
#   Trojan                    : 8643, password 8643, TLS cert from selected acme domain
#   VLESS Reality             : 8743, UUID 12345678-1234-1234-1234-123456789012
#   AnyTLS                    : 8143, password 8143, TLS cert from selected acme domain
#   VLESS TCP XTLS Vision     : 8243, UUID 87654321-4321-4321-4321-210987654321,
#                               flow xtls-rprx-vision, TLS cert from selected acme domain
#
set -u

# --------------------------------------------------------------------------- #
# Paths requested by user
# --------------------------------------------------------------------------- #
base_singbox_path=/root/singbox
yml=${base_singbox_path}/docker-compose.yml

config_path=${base_singbox_path}/config.json
conf_path=${base_singbox_path}/singbox.conf
cert_dir=${base_singbox_path}/certs
data_dir=${base_singbox_path}/data

CONTAINER=sing-box
DEFAULT_IMAGE=superng6/singbox:latest

# --------------------------------------------------------------------------- #
# Default deployment values
# --------------------------------------------------------------------------- #
DEFAULT_LISTEN="::"
DEFAULT_USER="user"

DEFAULT_TROJAN_PORT=8643
DEFAULT_TROJAN_PASS="8643"

# Existing VLESS Reality inbound
DEFAULT_VLESS_PORT=8743
DEFAULT_VLESS_UUID="12345678-1234-1234-1234-123456789012"
DEFAULT_VLESS_FLOW=""

# New VLESS TCP XTLS Vision inbound; replaces the old 8243 allocation.
DEFAULT_VLESS_VISION_PORT=8243
DEFAULT_VLESS_VISION_UUID="87654321-4321-4321-4321-210987654321"
DEFAULT_VLESS_VISION_FLOW="xtls-rprx-vision"

DEFAULT_ANYTLS_PORT=8143
DEFAULT_ANYTLS_PASS="8143"

# Reality handshake SNI/target. You can change these from the menu later.
DEFAULT_REALITY_SERVER_NAME="www.cloudflare.com"
DEFAULT_REALITY_HANDSHAKE_SERVER="www.cloudflare.com"
DEFAULT_REALITY_HANDSHAKE_PORT=443

DEFAULT_REALITY_PRIVATE_KEY="6LLF0kjbOb_6dou65js7xOF2lMCW-cQqU64i5ijINl4"
DEFAULT_REALITY_PUBLIC_KEY="YXHtQCYA6URyxvvopWnrO6e17Ya9L3EtDvoEbEkSnkA"
DEFAULT_REALITY_SHORT_ID="01234567"

# --------------------------------------------------------------------------- #
# Pretty output
# --------------------------------------------------------------------------- #
if [ -t 1 ]; then
	C_R=$'\033[31m'
	C_G=$'\033[32m'
	C_Y=$'\033[33m'
	C_B=$'\033[36m'
	C_0=$'\033[0m'
else
	C_R=
	C_G=
	C_Y=
	C_B=
	C_0=
fi
info() { printf '%s[*]%s %s\n' "$C_B" "$C_0" "$*"; }
ok() { printf '%s[+]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
err() { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
hr() { printf '%s\n' "------------------------------------------------------------"; }
pause() { read -rp "Press Enter to continue..." _ || true; }

# --------------------------------------------------------------------------- #
# Environment detection
# --------------------------------------------------------------------------- #
DC=()        # docker compose command as array
ACME_BIN=""  # path to acme.sh
ACME_HOME="" # acme.sh data dir

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		err "Please run as root. This script uses ${base_singbox_path} and host acme.sh certs."
		exit 1
	fi
}

install_docker_auto() {
	if ! command -v curl >/dev/null 2>&1; then
		err "docker is missing, and curl is also missing. Install docker manually and retry."
		exit 1
	fi
	warn "docker not found; installing Docker via get.docker.com ..."
	curl -fsSL https://get.docker.com | sh || {
		err "docker install failed"
		exit 1
	}
	systemctl enable --now docker 2>/dev/null || true
}

detect_docker() {
	if ! command -v docker >/dev/null 2>&1; then
		install_docker_auto
	fi

	if docker compose version >/dev/null 2>&1; then
		DC=(docker compose)
	elif command -v docker-compose >/dev/null 2>&1; then
		DC=(docker-compose)
	else
		err "docker compose plugin not found. Install docker compose and retry."
		exit 1
	fi
}

detect_acme() {
	if command -v acme.sh >/dev/null 2>&1; then
		ACME_BIN="$(command -v acme.sh)"
	elif [ -x "/root/.acme.sh/acme.sh" ]; then
		ACME_BIN="/root/.acme.sh/acme.sh"
	elif [ -x "${HOME}/.acme.sh/acme.sh" ]; then
		ACME_BIN="${HOME}/.acme.sh/acme.sh"
	fi

	if [ -d "/root/.acme.sh" ]; then
		ACME_HOME="/root/.acme.sh"
	else
		ACME_HOME="${HOME}/.acme.sh"
	fi
}

# --------------------------------------------------------------------------- #
# Generic helpers
# --------------------------------------------------------------------------- #
is_installed() { [ -f "$conf_path" ] && [ -f "$config_path" ] && [ -f "$yml" ]; }

valid_port() {
	local p="${1:-}"
	[[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

json_escape() {
	local s="${1-}"
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	s=${s//$'\n'/\\n}
	s=${s//$'\r'/\\r}
	s=${s//$'\t'/\\t}
	printf '%s' "$s"
}

rand_hex8() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -hex 4
	else
		od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
	fi
}

compose() { "${DC[@]}" -f "$yml" "$@"; }

pull_image() {
	info "Pulling ${IMAGE} ..."
	docker pull "$IMAGE"
}

apply_defaults() {
	IMAGE="${IMAGE:-$DEFAULT_IMAGE}"
	LISTEN="${LISTEN:-$DEFAULT_LISTEN}"
	PROTOCOL_USER="${PROTOCOL_USER:-$DEFAULT_USER}"

	TROJAN_PORT="${TROJAN_PORT:-$DEFAULT_TROJAN_PORT}"
	TROJAN_PASS="${TROJAN_PASS:-$DEFAULT_TROJAN_PASS}"

	VLESS_PORT="${VLESS_PORT:-$DEFAULT_VLESS_PORT}"
	VLESS_UUID="${VLESS_UUID:-$DEFAULT_VLESS_UUID}"
	VLESS_FLOW="${VLESS_FLOW:-$DEFAULT_VLESS_FLOW}"

	VLESS_VISION_PORT="${VLESS_VISION_PORT:-$DEFAULT_VLESS_VISION_PORT}"
	VLESS_VISION_UUID="${VLESS_VISION_UUID:-$DEFAULT_VLESS_VISION_UUID}"
	VLESS_VISION_FLOW="${VLESS_VISION_FLOW:-$DEFAULT_VLESS_VISION_FLOW}"

	ANYTLS_PORT="${ANYTLS_PORT:-$DEFAULT_ANYTLS_PORT}"
	ANYTLS_PASS="${ANYTLS_PASS:-$DEFAULT_ANYTLS_PASS}"

	REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-$DEFAULT_REALITY_SERVER_NAME}"
	REALITY_HANDSHAKE_SERVER="${REALITY_HANDSHAKE_SERVER:-$DEFAULT_REALITY_HANDSHAKE_SERVER}"
	REALITY_HANDSHAKE_PORT="${REALITY_HANDSHAKE_PORT:-$DEFAULT_REALITY_HANDSHAKE_PORT}"

	REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-$DEFAULT_REALITY_PRIVATE_KEY}"
	REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-$DEFAULT_REALITY_PUBLIC_KEY}"
	REALITY_SHORT_ID="${REALITY_SHORT_ID:-$DEFAULT_REALITY_SHORT_ID}"

	ECC="${ECC:-}"
}

load_conf() {
	if [ ! -f "$conf_path" ]; then
		err "Not installed yet. Run install first."
		return 1
	fi
	# shellcheck disable=SC1090
	. "$conf_path"
	apply_defaults
}

save_conf() {
	mkdir -p "$base_singbox_path"
	{
		echo "# Generated by singbox_manager.sh"
		printf 'DOMAIN=%q\n' "${DOMAIN:-}"
		printf 'ECC=%q\n' "${ECC:-}"
		printf 'IMAGE=%q\n' "${IMAGE:-$DEFAULT_IMAGE}"
		printf 'LISTEN=%q\n' "${LISTEN:-$DEFAULT_LISTEN}"
		printf 'PROTOCOL_USER=%q\n' "${PROTOCOL_USER:-$DEFAULT_USER}"
		printf 'TROJAN_PORT=%q\n' "${TROJAN_PORT:-$DEFAULT_TROJAN_PORT}"
		printf 'TROJAN_PASS=%q\n' "${TROJAN_PASS:-$DEFAULT_TROJAN_PASS}"
		printf 'VLESS_PORT=%q\n' "${VLESS_PORT:-$DEFAULT_VLESS_PORT}"
		printf 'VLESS_UUID=%q\n' "${VLESS_UUID:-$DEFAULT_VLESS_UUID}"
		printf 'VLESS_FLOW=%q\n' "${VLESS_FLOW:-$DEFAULT_VLESS_FLOW}"
		printf 'VLESS_VISION_PORT=%q\n' "${VLESS_VISION_PORT:-$DEFAULT_VLESS_VISION_PORT}"
		printf 'VLESS_VISION_UUID=%q\n' "${VLESS_VISION_UUID:-$DEFAULT_VLESS_VISION_UUID}"
		printf 'VLESS_VISION_FLOW=%q\n' "${VLESS_VISION_FLOW:-$DEFAULT_VLESS_VISION_FLOW}"
		printf 'ANYTLS_PORT=%q\n' "${ANYTLS_PORT:-$DEFAULT_ANYTLS_PORT}"
		printf 'ANYTLS_PASS=%q\n' "${ANYTLS_PASS:-$DEFAULT_ANYTLS_PASS}"
		printf 'REALITY_SERVER_NAME=%q\n' "${REALITY_SERVER_NAME:-$DEFAULT_REALITY_SERVER_NAME}"
		printf 'REALITY_HANDSHAKE_SERVER=%q\n' "${REALITY_HANDSHAKE_SERVER:-$DEFAULT_REALITY_HANDSHAKE_SERVER}"
		printf 'REALITY_HANDSHAKE_PORT=%q\n' "${REALITY_HANDSHAKE_PORT:-$DEFAULT_REALITY_HANDSHAKE_PORT}"
		printf 'REALITY_PRIVATE_KEY=%q\n' "${REALITY_PRIVATE_KEY:-}"
		printf 'REALITY_PUBLIC_KEY=%q\n' "${REALITY_PUBLIC_KEY:-}"
		printf 'REALITY_SHORT_ID=%q\n' "${REALITY_SHORT_ID:-}"
	} >"$conf_path"
	chmod 600 "$conf_path"
}

# --------------------------------------------------------------------------- #
# acme.sh: pick ONE host-managed domain and copy/link cert/key
# --------------------------------------------------------------------------- #
pick_domain() {
	if [ -z "$ACME_BIN" ]; then
		err "acme.sh not found. Issue/manage certs on the HOST with acme.sh first."
		return 1
	fi

	local domains=()
	mapfile -t domains < <("$ACME_BIN" --list 2>/dev/null | awk 'NR>1 && NF>0 {print $1}')
	if [ "${#domains[@]}" -eq 0 ]; then
		err "No certificates registered in acme.sh ($ACME_BIN --list is empty)."
		return 1
	fi

	echo "acme.sh domains:"
	local i=1 d
	for d in "${domains[@]}"; do
		printf '  %d) %s\n' "$i" "$d"
		i=$((i + 1))
	done

	local choice
	while :; do
		read -rp "Pick the domain to use [1-${#domains[@]}]: " choice
		if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#domains[@]}" ]; then
			DOMAIN="${domains[$((choice - 1))]}"
			break
		fi
		warn "Invalid choice."
	done

	if [ -d "${ACME_HOME}/${DOMAIN}_ecc" ]; then
		ECC="--ecc"
	else
		ECC=""
	fi
	ok "Selected: ${DOMAIN} (${ECC:-rsa})"
}

install_cert() {
	if [ -z "${DOMAIN:-}" ]; then
		err "DOMAIN is empty."
		return 1
	fi
	if [ -z "$ACME_BIN" ]; then
		err "acme.sh not found."
		return 1
	fi

	mkdir -p "$cert_dir"
	info "Copying/linking HOST acme cert for ${DOMAIN} into ${cert_dir} ..."
	"$ACME_BIN" --install-cert -d "$DOMAIN" ${ECC:-} \
		--fullchain-file "${cert_dir}/fullchain.cer" \
		--key-file "${cert_dir}/private.key" \
		--reloadcmd "docker restart ${CONTAINER} >/dev/null 2>&1 || true"

	if [ ! -s "${cert_dir}/fullchain.cer" ] || [ ! -s "${cert_dir}/private.key" ]; then
		err "Cert install did not produce ${cert_dir}/fullchain.cer and ${cert_dir}/private.key."
		return 1
	fi
	chmod 600 "${cert_dir}/private.key" 2>/dev/null || true
	ok "Cert mapped into ${cert_dir}; acme renewals will restart ${CONTAINER}."
}

# --------------------------------------------------------------------------- #
# Reality key generation
# --------------------------------------------------------------------------- #
generate_reality_keypair() {
	local out=""

	if command -v sing-box >/dev/null 2>&1; then
		out="$(sing-box generate reality-keypair 2>/dev/null || true)"
	fi

	if [ -z "$out" ]; then
		out="$(docker run --rm "$IMAGE" generate reality-keypair 2>/dev/null || true)"
	fi

	REALITY_PRIVATE_KEY="$(printf '%s\n' "$out" | awk -F': *' '/PrivateKey/ {print $2; exit}')"
	REALITY_PUBLIC_KEY="$(printf '%s\n' "$out" | awk -F': *' '/PublicKey/ {print $2; exit}')"
	REALITY_SHORT_ID="$(rand_hex8)"

	if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ] || [ -z "$REALITY_SHORT_ID" ]; then
		err "Failed to generate Reality keypair. Raw output was:"
		printf '%s\n' "$out" >&2
		return 1
	fi

	ok "Generated VLESS Reality keypair and short_id."
}

# --------------------------------------------------------------------------- #
# File generators
# --------------------------------------------------------------------------- #
gen_compose() {
	local quiet="${1:-}"
	mkdir -p "$base_singbox_path" "$cert_dir" "$data_dir"
	cat >"$yml" <<EOF2
services:
  sing-box:
    image: ${IMAGE}
    container_name: ${CONTAINER}
    restart: always
    network_mode: host
    volumes:
      - ${base_singbox_path}:/etc/sing-box:ro
      - ${data_dir}:/var/lib/sing-box
    command: -D /var/lib/sing-box -C /etc/sing-box run
EOF2
	if [ "$quiet" != "quiet" ]; then
		ok "Wrote ${yml}"
	fi
}

gen_config() {
	mkdir -p "$base_singbox_path" "$cert_dir" "$data_dir"

	local j_domain j_listen j_user j_trojan_pass j_vless_uuid j_vless_flow
	local j_anytls_pass j_reality_name j_reality_server
	local j_reality_private j_reality_short
	local j_vless_vision_uuid j_vless_vision_flow

	j_domain="$(json_escape "$DOMAIN")"
	j_listen="$(json_escape "$LISTEN")"
	j_user="$(json_escape "$PROTOCOL_USER")"
	j_trojan_pass="$(json_escape "$TROJAN_PASS")"
	j_vless_uuid="$(json_escape "$VLESS_UUID")"
	j_vless_flow="$(json_escape "$VLESS_FLOW")"
	j_vless_vision_uuid="$(json_escape "$VLESS_VISION_UUID")"
	j_vless_vision_flow="$(json_escape "$VLESS_VISION_FLOW")"
	j_anytls_pass="$(json_escape "$ANYTLS_PASS")"
	j_reality_name="$(json_escape "$REALITY_SERVER_NAME")"
	j_reality_server="$(json_escape "$REALITY_HANDSHAKE_SERVER")"
	j_reality_private="$(json_escape "$REALITY_PRIVATE_KEY")"
	j_reality_short="$(json_escape "$REALITY_SHORT_ID")"

	cat >"$config_path" <<EOF2
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "${j_listen}",
      "listen_port": ${TROJAN_PORT},
      "users": [
        {
          "name": "${j_user}",
          "password": "${j_trojan_pass}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${j_domain}",
        "certificate_path": "/etc/sing-box/certs/fullchain.cer",
        "key_path": "/etc/sing-box/certs/private.key"
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "${j_listen}",
      "listen_port": ${VLESS_PORT},
      "users": [
        {
          "name": "${j_user}",
          "uuid": "${j_vless_uuid}",
          "flow": "${j_vless_flow}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${j_reality_name}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${j_reality_server}",
            "server_port": ${REALITY_HANDSHAKE_PORT}
          },
          "private_key": "${j_reality_private}",
          "short_id": [
            "${j_reality_short}"
          ]
        }
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "${j_listen}",
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "name": "${j_user}",
          "password": "${j_anytls_pass}"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "server_name": "${j_domain}",
        "certificate_path": "/etc/sing-box/certs/fullchain.cer",
        "key_path": "/etc/sing-box/certs/private.key"
      }
    },
    {
      "type": "vless",
      "tag": "vless-vision-in",
      "listen": "${j_listen}",
      "listen_port": ${VLESS_VISION_PORT},
      "users": [
        {
          "name": "${j_user}",
          "uuid": "${j_vless_vision_uuid}",
          "flow": "${j_vless_vision_flow}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${j_domain}",
        "certificate_path": "/etc/sing-box/certs/fullchain.cer",
        "key_path": "/etc/sing-box/certs/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF2
	chmod 600 "$config_path"
	ok "Wrote ${config_path}"
}

check_config() {
	info "Checking sing-box config with ${IMAGE} ..."
	docker run --rm \
		-v "${base_singbox_path}:/etc/sing-box:ro" \
		-v "${data_dir}:/var/lib/sing-box" \
		"$IMAGE" -D /var/lib/sing-box -C /etc/sing-box check
}

# --------------------------------------------------------------------------- #
# Display helpers
# --------------------------------------------------------------------------- #
show_link() {
	load_conf || return 1
	hr
	printf '%sSing-box VPS inbound info%s\n' "$C_G" "$C_0"
	hr
	printf 'Domain / cert SNI     : %s\n' "$DOMAIN"
	printf 'Config path           : %s\n' "$config_path"
	printf 'Compose path          : %s\n' "$yml"
	printf 'Cert dir              : %s\n' "$cert_dir"
	echo

	printf '%sTrojan TLS%s\n' "$C_B" "$C_0"
	printf '  server: %s\n  port  : %s\n  user  : %s\n  pass  : %s\n' "$DOMAIN" "$TROJAN_PORT" "$PROTOCOL_USER" "$TROJAN_PASS"
	printf '  link  : trojan://%s@%s:%s?security=tls&sni=%s&type=tcp#%s-trojan\n' \
		"$TROJAN_PASS" "$DOMAIN" "$TROJAN_PORT" "$DOMAIN" "$DOMAIN"
	echo

	printf '%sVLESS Reality%s\n' "$C_B" "$C_0"
	printf '  server address      : %s\n' "$DOMAIN"
	printf '  port                : %s\n' "$VLESS_PORT"
	printf '  uuid                : %s\n' "$VLESS_UUID"
	printf '  flow                : %s\n' "${VLESS_FLOW:-<empty>}"
	printf '  reality sni         : %s\n' "$REALITY_SERVER_NAME"
	printf '  reality public_key  : %s\n' "$REALITY_PUBLIC_KEY"
	printf '  reality short_id    : %s\n' "$REALITY_SHORT_ID"
	if [ -n "${VLESS_FLOW:-}" ]; then
		printf '  link                : vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&flow=%s#%s-vless-reality\n' \
			"$VLESS_UUID" "$DOMAIN" "$VLESS_PORT" "$REALITY_SERVER_NAME" "$REALITY_PUBLIC_KEY" "$REALITY_SHORT_ID" "$VLESS_FLOW" "$DOMAIN"
	else
		printf '  link                : vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s-vless-reality\n' \
			"$VLESS_UUID" "$DOMAIN" "$VLESS_PORT" "$REALITY_SERVER_NAME" "$REALITY_PUBLIC_KEY" "$REALITY_SHORT_ID" "$DOMAIN"
	fi
	echo

	printf '%sAnyTLS%s\n' "$C_B" "$C_0"
	printf '  server: %s\n  port  : %s\n  user  : %s\n  pass  : %s\n' "$DOMAIN" "$ANYTLS_PORT" "$PROTOCOL_USER" "$ANYTLS_PASS"
	cat <<EOF2
  sing-box outbound snippet:
  {
    "type": "anytls",
    "tag": "anytls-out",
    "server": "${DOMAIN}",
    "server_port": ${ANYTLS_PORT},
    "password": "${ANYTLS_PASS}",
    "tls": { "enabled": true, "server_name": "${DOMAIN}" }
  }
EOF2
	echo

	printf '%sVLESS TCP XTLS Vision%s\n' "$C_B" "$C_0"
	printf '  server: %s\n  port  : %s\n  user  : %s\n  uuid  : %s\n  flow  : %s\n' \
		"$DOMAIN" "$VLESS_VISION_PORT" "$PROTOCOL_USER" "$VLESS_VISION_UUID" "$VLESS_VISION_FLOW"
	printf '  link  : vless://%s@%s:%s?encryption=none&security=tls&sni=%s&fp=chrome&type=tcp&flow=%s#%s-vless-vision\n' \
		"$VLESS_VISION_UUID" "$DOMAIN" "$VLESS_VISION_PORT" "$DOMAIN" "$VLESS_VISION_FLOW" "$DOMAIN"
	cat <<EOF2
  sing-box outbound snippet:
  {
    "type": "vless",
    "tag": "vless-vision-out",
    "server": "${DOMAIN}",
    "server_port": ${VLESS_VISION_PORT},
    "uuid": "${VLESS_VISION_UUID}",
    "flow": "${VLESS_VISION_FLOW}",
    "tls": {
      "enabled": true,
      "server_name": "${DOMAIN}",
      "utls": { "enabled": true, "fingerprint": "chrome" }
    }
  }
EOF2
	hr
}

# --------------------------------------------------------------------------- #
# Prompt helpers for change menu only
# --------------------------------------------------------------------------- #
prompt_keep() {
	local label="$1" current="$2" out_var="$3" p
	read -rp "${label} [${current}]: " p
	printf -v "$out_var" '%s' "${p:-$current}"
}

prompt_keep_port() {
	local label="$1" current="$2" out_var="$3" p
	while :; do
		read -rp "${label} [${current}]: " p
		p="${p:-$current}"
		if valid_port "$p"; then
			printf -v "$out_var" '%s' "$p"
			return 0
		fi
		warn "Port must be 1-65535."
	done
}

# --------------------------------------------------------------------------- #
# Menu actions
# --------------------------------------------------------------------------- #
do_install() {
	# Per request: install only asks for the acme domain choice. Everything else
	# deploys with defaults and can be changed later from the menu.
	IMAGE="$DEFAULT_IMAGE"
	LISTEN="$DEFAULT_LISTEN"
	PROTOCOL_USER="$DEFAULT_USER"

	TROJAN_PORT="$DEFAULT_TROJAN_PORT"
	TROJAN_PASS="$DEFAULT_TROJAN_PASS"

	VLESS_PORT="$DEFAULT_VLESS_PORT"
	VLESS_UUID="$DEFAULT_VLESS_UUID"
	VLESS_FLOW="$DEFAULT_VLESS_FLOW"

	VLESS_VISION_PORT="$DEFAULT_VLESS_VISION_PORT"
	VLESS_VISION_UUID="$DEFAULT_VLESS_VISION_UUID"
	VLESS_VISION_FLOW="$DEFAULT_VLESS_VISION_FLOW"

	ANYTLS_PORT="$DEFAULT_ANYTLS_PORT"
	ANYTLS_PASS="$DEFAULT_ANYTLS_PASS"

	REALITY_SERVER_NAME="$DEFAULT_REALITY_SERVER_NAME"
	REALITY_HANDSHAKE_SERVER="$DEFAULT_REALITY_HANDSHAKE_SERVER"
	REALITY_HANDSHAKE_PORT="$DEFAULT_REALITY_HANDSHAKE_PORT"

	pick_domain || {
		pause
		return 1
	}

	mkdir -p "$base_singbox_path" "$cert_dir" "$data_dir"
	install_cert || {
		pause
		return 1
	}
	pull_image || {
		pause
		return 1
	}
	generate_reality_keypair || {
		########	pause
		########	return 1
		REALITY_PRIVATE_KEY="$DEFAULT_REALITY_PRIVATE_KEY"
		REALITY_PUBLIC_KEY="$DEFAULT_REALITY_PUBLIC_KEY"
		REALITY_SHORT_ID="$DEFAULT_REALITY_SHORT_ID"
	}

	save_conf
	gen_config
	gen_compose
	check_config || {
		err "Config check failed; not starting container."
		pause
		return 1
	}

	info "Starting ${CONTAINER} ..."
	compose up -d --force-recreate
	ok "sing-box is up."
	show_link
	pause
}

do_update() {
	load_conf || {
		pause
		return 1
	}
	pull_image || {
		pause
		return 1
	}
	save_conf
	gen_config
	gen_compose quiet
	check_config || {
		err "Config check failed; not recreating container."
		pause
		return 1
	}
	compose up -d --force-recreate
	docker image prune -f >/dev/null 2>&1 || true
	ok "Updated config, pulled image, and recreated."
	pause
}

do_show() {
	show_link
	pause
}

do_restart() {
	load_conf || {
		pause
		return 1
	}
	gen_compose quiet
	compose restart
	ok "Restarted."
	pause
}

do_stop() {
	load_conf || {
		pause
		return 1
	}
	gen_compose quiet
	compose stop
	ok "Stopped."
	pause
}

do_start() {
	load_conf || {
		pause
		return 1
	}
	gen_compose quiet
	compose up -d
	ok "Started."
	pause
}

do_logs() {
	load_conf || {
		pause
		return 1
	}
	gen_compose quiet
	info "Following logs; Ctrl-C to exit."
	compose logs -f --tail=150 || true
}

do_settings() {
	load_conf || {
		pause
		return 1
	}
	echo "Leave blank to keep current value."
	echo

	prompt_keep "Listen address" "$LISTEN" LISTEN
	prompt_keep "Protocol username/name" "$PROTOCOL_USER" PROTOCOL_USER
	echo

	prompt_keep_port "Trojan port" "$TROJAN_PORT" TROJAN_PORT
	prompt_keep "Trojan password" "$TROJAN_PASS" TROJAN_PASS
	echo

	prompt_keep_port "VLESS Reality port" "$VLESS_PORT" VLESS_PORT
	prompt_keep "VLESS Reality UUID" "$VLESS_UUID" VLESS_UUID
	prompt_keep "VLESS Reality flow (empty is OK; xtls-rprx-vision optional)" "$VLESS_FLOW" VLESS_FLOW
	echo

	prompt_keep_port "AnyTLS port" "$ANYTLS_PORT" ANYTLS_PORT
	prompt_keep "AnyTLS password" "$ANYTLS_PASS" ANYTLS_PASS
	echo

	prompt_keep_port "VLESS TCP XTLS Vision port" "$VLESS_VISION_PORT" VLESS_VISION_PORT
	prompt_keep "VLESS TCP XTLS Vision UUID" "$VLESS_VISION_UUID" VLESS_VISION_UUID
	prompt_keep "VLESS TCP XTLS Vision flow" "$VLESS_VISION_FLOW" VLESS_VISION_FLOW
	echo

	prompt_keep "Reality server_name/SNI" "$REALITY_SERVER_NAME" REALITY_SERVER_NAME
	prompt_keep "Reality handshake server" "$REALITY_HANDSHAKE_SERVER" REALITY_HANDSHAKE_SERVER
	prompt_keep_port "Reality handshake port" "$REALITY_HANDSHAKE_PORT" REALITY_HANDSHAKE_PORT

	save_conf
	gen_config
	gen_compose
	check_config || {
		err "Config check failed; keeping files but not recreating container."
		pause
		return 1
	}
	compose up -d --force-recreate
	ok "Settings applied."
	show_link
	pause
}

do_change_domain() {
	load_conf || {
		pause
		return 1
	}
	pick_domain || {
		pause
		return 1
	}
	install_cert || {
		pause
		return 1
	}
	save_conf
	gen_config
	gen_compose
	check_config || {
		err "Config check failed; not recreating container."
		pause
		return 1
	}
	compose up -d --force-recreate
	ok "Domain/cert applied."
	show_link
	pause
}

do_reality_keys() {
	load_conf || {
		pause
		return 1
	}
	pull_image || {
		pause
		return 1
	}
	generate_reality_keypair || {
		pause
		return 1
	}
	save_conf
	gen_config
	gen_compose quiet
	check_config || {
		err "Config check failed; not recreating container."
		pause
		return 1
	}
	compose up -d --force-recreate
	ok "Reality keys regenerated. Update all VLESS Reality clients with the new public_key and short_id."
	show_link
	pause
}

do_cert() {
	load_conf || {
		pause
		return 1
	}
	if [ -z "$ACME_BIN" ]; then
		err "acme.sh not found."
		pause
		return 1
	fi
	info "Forcing acme.sh renew + reinstall for ${DOMAIN} ..."
	"$ACME_BIN" --renew -d "$DOMAIN" ${ECC:-} --force 2>/dev/null || warn "Renew skipped/failed; trying install-cert anyway."
	install_cert || {
		pause
		return 1
	}
	gen_config
	gen_compose quiet
	check_config || {
		err "Config check failed; not restarting container."
		pause
		return 1
	}
	compose restart
	ok "Cert refreshed and container restarted."
	pause
}

do_status() {
	load_conf || {
		pause
		return 1
	}
	gen_compose quiet
	compose ps
	echo
	info "Listening sockets for configured ports:"
	if command -v ss >/dev/null 2>&1; then
		ss -lntup 2>/dev/null | grep -E ":(${TROJAN_PORT}|${VLESS_PORT}|${ANYTLS_PORT}|${VLESS_VISION_PORT})\b" || warn "No matching listening sockets found by ss."
	else
		warn "ss command not found."
	fi
	echo
	info "Cert expiry:"
	if command -v openssl >/dev/null 2>&1 && [ -s "${cert_dir}/fullchain.cer" ]; then
		openssl x509 -enddate -noout -in "${cert_dir}/fullchain.cer" 2>/dev/null || true
	else
		warn "openssl or cert file not found."
	fi
	echo
	info "acme.sh auto-renew hook for ${DOMAIN}:"
	if [ -n "$ACME_BIN" ]; then
		"$ACME_BIN" --info -d "$DOMAIN" ${ECC:-} 2>/dev/null | grep -E 'Le_Real|Le_ReloadCmd' || warn "No install-cert hook shown. Run renew/reinstall cert."
		if crontab -l 2>/dev/null | grep -q acme.sh; then
			ok "acme.sh renewal cron is present."
		else
			warn "No acme.sh cron found. Run: $ACME_BIN --install-cronjob"
		fi
	fi
	pause
}

do_uninstall() {
	load_conf || {
		pause
		return 1
	}
	gen_compose quiet
	warn "This stops the container and removes ${base_singbox_path}."
	read -rp "Type 'yes' to confirm: " a
	if [ "$a" != "yes" ]; then
		info "Cancelled."
		pause
		return 0
	fi
	compose down 2>/dev/null || true
	rm -rf "$base_singbox_path"
	ok "Removed ${base_singbox_path}. HOST acme.sh certificates are left intact."
	pause
}

# --------------------------------------------------------------------------- #
# Menu
# --------------------------------------------------------------------------- #
menu() {
	while :; do
		clear 2>/dev/null || true
		hr
		printf '  %sSing-box Manager%s   (%s)\n' "$C_G" "$C_0" "$base_singbox_path"
		hr
		if is_installed; then
			# shellcheck disable=SC1090
			. "$conf_path"
			apply_defaults
			printf '  status: %sinstalled%s  domain: %s\n' "$C_G" "$C_0" "${DOMAIN:-unknown}"
			printf '  ports : trojan=%s  vless-reality=%s  anytls=%s  vless-vision=%s\n' \
				"${TROJAN_PORT:-?}" "${VLESS_PORT:-?}" "${ANYTLS_PORT:-?}" "${VLESS_VISION_PORT:-?}"
		else
			printf '  status: %snot installed%s\n' "$C_Y" "$C_0"
			printf '  default ports: trojan=%s  vless-reality=%s  anytls=%s  vless-vision=%s\n' \
				"$DEFAULT_TROJAN_PORT" "$DEFAULT_VLESS_PORT" "$DEFAULT_ANYTLS_PORT" "$DEFAULT_VLESS_VISION_PORT"
		fi
		hr
		cat <<MENU2
  1) Install / overwrite with defaults (only asks for acme domain)
  2) Update image + regenerate compose/config
  3) Show config & connection info
  4) Restart
  5) Stop
  6) Start
  7) Logs (follow)
  8) Change ports/passwords/user/VLESS/Reality handshake
  9) Change acme domain / reinstall cert
 10) Regenerate VLESS Reality keypair
 11) Renew / reinstall TLS cert
 12) Status
 13) Uninstall
  0) Exit
MENU2
		hr
		read -rp "Choose: " c
		case "$c" in
		1) do_install ;;
		2) do_update ;;
		3) do_show ;;
		4) do_restart ;;
		5) do_stop ;;
		6) do_start ;;
		7) do_logs ;;
		8) do_settings ;;
		9) do_change_domain ;;
		10) do_reality_keys ;;
		11) do_cert ;;
		12) do_status ;;
		13) do_uninstall ;;
		0) exit 0 ;;
		*)
			warn "Invalid option."
			sleep 1
			;;
		esac
	done
}

main() {
	require_root
	detect_docker
	detect_acme
	menu
}
main "$@"
