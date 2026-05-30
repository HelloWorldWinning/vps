#!/usr/bin/env bash
#==============================================================================
# anytls_maneger.sh — AnyTLS node manager for Debian (mihomo backend)
#------------------------------------------------------------------------------
# Commands:
#   install | info | start/stop/restart/status | logs | reconfigure | update |
#   repair | sync-cert | uninstall
#
# Main fix in this build:
#   mihomo only allows certificate/key paths under its home/safe directory.
#   Existing Let's Encrypt/acme.sh certs are now copied or installed into
#   /etc/anytls/cert.crt and /etc/anytls/cert.key before config is written.
#==============================================================================

set -o pipefail

#------------------------------- constants ------------------------------------
DIR="/etc/anytls"
BIN="$DIR/mihomo"
CONF="$DIR/config.yaml"
META="$DIR/anytls.conf"
PADDING="$DIR/padding.txt"
SAFE_CRT="$DIR/cert.crt"
SAFE_KEY="$DIR/cert.key"
SERVICE_NAME="anytls"
SERVICE="/etc/systemd/system/${SERVICE_NAME}.service"
SELF_CMD="/usr/local/bin/anytls"
CERTBOT_HOOK="/etc/letsencrypt/renewal-hooks/deploy/anytls.sh"

MIHOMO_REPO="MetaCubeX/mihomo"
ANYTLS_REPO="anytls/anytls-go"

DEFAULT_PORT="344"
DEFAULT_PASSWORD="344"

#------------------------------- colors ---------------------------------------
if [ -t 1 ]; then
	R=$'\e[31m'
	G=$'\e[32m'
	Y=$'\e[33m'
	B=$'\e[36m'
	W=$'\e[1m'
	N=$'\e[0m'
else
	R=''
	G=''
	Y=''
	B=''
	W=''
	N=''
fi
ok() { echo "${G}[ok]${N} $*"; }
inf() { echo "${B}[*]${N} $*"; }
warn() { echo "${Y}[!]${N} $*"; }
err() { echo "${R}[x]${N} $*" >&2; }
die() {
	err "$*"
	exit 1
}
hr() { echo "${W}------------------------------------------------------------${N}"; }

#------------------------------- guards ---------------------------------------
need_root() { [ "$(id -u)" -eq 0 ] || die "Please run as root (sudo)."; }

ensure_deps() {
	local miss=()
	for c in curl openssl gzip systemctl sed awk grep ss; do
		command -v "$c" >/dev/null 2>&1 || miss+=("$c")
	done

	if [ "${#miss[@]}" -gt 0 ]; then
		command -v apt-get >/dev/null 2>&1 || die "Missing dependencies: ${miss[*]}; apt-get was not found."
		inf "Installing dependencies: ${miss[*]}"
		apt-get update -y >/dev/null 2>&1
		apt-get install -y curl openssl gzip ca-certificates coreutils procps iproute2 >/dev/null 2>&1 ||
			die "Failed to install dependencies."
	fi
}

#------------------------------- helpers --------------------------------------
arch_tag() {
	case "$(uname -m)" in
	x86_64 | amd64)
		if grep -qm1 avx2 /proc/cpuinfo 2>/dev/null; then echo "amd64"; else echo "amd64-compatible"; fi
		;;
	aarch64 | arm64) echo "arm64" ;;
	armv7l | armv7 | armhf) echo "armv7" ;;
	i386 | i686) echo "386" ;;
	*) die "Unsupported architecture: $(uname -m)" ;;
	esac
}

latest_mihomo_tag() {
	local url
	url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
		"https://github.com/${MIHOMO_REPO}/releases/latest" 2>/dev/null) || return 1
	basename "$url" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

installed_mihomo_ver() {
	[ -x "$BIN" ] || {
		echo "none"
		return
	}
	"$BIN" -v 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

get_ip4() {
	local ip u
	for u in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me; do
		ip=$(curl -fsS4 --max-time 6 "$u" 2>/dev/null | tr -d '[:space:]')
		[ -n "$ip" ] && {
			echo "$ip"
			return
		}
	done
	ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}'
}

get_ip6() {
	local ip u
	for u in https://api64.ipify.org https://ipv6.icanhazip.com; do
		ip=$(curl -fsS6 --max-time 6 "$u" 2>/dev/null | tr -d '[:space:]')
		[ -n "$ip" ] && [[ "$ip" == *:* ]] && {
			echo "$ip"
			return
		}
	done
}

ipv6_enabled() {
	[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ] &&
		[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" = "0" ]
}

urlencode() {
	local s="$1" out='' i c
	for ((i = 0; i < ${#s}; i++)); do
		c=${s:i:1}
		case "$c" in
		[a-zA-Z0-9.~_-]) out+="$c" ;;
		*) out+=$(printf '%%%02X' "'$c") ;;
		esac
	done
	printf '%s' "$out"
}

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

valid_domain() {
	local d="$1"
	[[ "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

lower_domain() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g'; }

acme_auto_email() {
	# No prompt. This avoids acme.sh falling back to forbidden example.com.
	printf 'admin@%s' "$1"
}

open_firewall() {
	local p="$1"
	if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
		ufw allow "${p}/tcp" >/dev/null 2>&1 && inf "ufw: opened ${p}/tcp"
	fi
}

copy_self_command() {
	if [ "$0" != "$SELF_CMD" ] || [ ! -x "$SELF_CMD" ]; then
		cp -f "$0" "$SELF_CMD" 2>/dev/null && chmod 0755 "$SELF_CMD" 2>/dev/null &&
			inf "Manager installed as 'anytls' — run it anytime with: anytls"
	fi
}

#------------------------------- meta i/o -------------------------------------
load_meta() {
	if [ -f "$META" ]; then
		# shellcheck source=/dev/null
		. "$META"
	fi
	PORT="${PORT:-$DEFAULT_PORT}"
	PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
	TLS_MODE="${TLS_MODE:-}"
	DOMAIN="${DOMAIN:-}"
	SNI="${SNI:-}"
	INSECURE="${INSECURE:-0}"
	CERT_PATH="${CERT_PATH:-}"
	KEY_PATH="${KEY_PATH:-}"
	CERT_SRC_CRT="${CERT_SRC_CRT:-}"
	CERT_SRC_KEY="${CERT_SRC_KEY:-}"
	ACME_ECC="${ACME_ECC:-0}"
	LISTEN="${LISTEN:-0.0.0.0}"
}

save_meta() {
	mkdir -p "$DIR"
	{
		printf 'PORT=%q\n' "$PORT"
		printf 'PASSWORD=%q\n' "$PASSWORD"
		printf 'TLS_MODE=%q\n' "$TLS_MODE"
		printf 'DOMAIN=%q\n' "$DOMAIN"
		printf 'SNI=%q\n' "$SNI"
		printf 'INSECURE=%q\n' "$INSECURE"
		printf 'CERT_PATH=%q\n' "$CERT_PATH"
		printf 'KEY_PATH=%q\n' "$KEY_PATH"
		printf 'CERT_SRC_CRT=%q\n' "$CERT_SRC_CRT"
		printf 'CERT_SRC_KEY=%q\n' "$CERT_SRC_KEY"
		printf 'ACME_ECC=%q\n' "$ACME_ECC"
		printf 'LISTEN=%q\n' "$LISTEN"
	} >"$META"
	chmod 600 "$META"
}

is_installed() { [ -x "$BIN" ] && [ -f "$META" ] && [ -f "$SERVICE" ]; }

#------------------------------- certificate safe-path handling ----------------
validate_cert_file() { openssl x509 -in "$1" -noout >/dev/null 2>&1; }
validate_key_file() { openssl pkey -in "$1" -noout >/dev/null 2>&1; }

cert_key_match() {
	local crt="$1" key="$2" crt_pub key_pub
	crt_pub=$(openssl x509 -in "$crt" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}') || return 1
	key_pub=$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}') || return 1
	[ -n "$crt_pub" ] && [ "$crt_pub" = "$key_pub" ]
}

install_cert_to_safe_paths() {
	local src_crt="$1" src_key="$2"
	[ -f "$src_crt" ] || {
		err "Certificate file not found: $src_crt"
		return 1
	}
	[ -f "$src_key" ] || {
		err "Private key file not found: $src_key"
		return 1
	}
	validate_cert_file "$src_crt" || {
		err "Invalid certificate PEM: $src_crt"
		return 1
	}
	validate_key_file "$src_key" || {
		err "Invalid private key PEM: $src_key"
		return 1
	}
	cert_key_match "$src_crt" "$src_key" || {
		err "Certificate and private key do not match."
		return 1
	}

	mkdir -p "$DIR"
	install -m 0644 "$src_crt" "${SAFE_CRT}.tmp" || return 1
	install -m 0600 "$src_key" "${SAFE_KEY}.tmp" || return 1
	mv -f "${SAFE_CRT}.tmp" "$SAFE_CRT"
	mv -f "${SAFE_KEY}.tmp" "$SAFE_KEY"
	chmod 0644 "$SAFE_CRT"
	chmod 0600 "$SAFE_KEY"

	CERT_PATH="$SAFE_CRT"
	KEY_PATH="$SAFE_KEY"
	return 0
}

ensure_cert_safe_paths() {
	[ -n "${CERT_PATH:-}" ] && [ -n "${KEY_PATH:-}" ] || return 0

	if [ "$CERT_PATH" = "$SAFE_CRT" ] && [ "$KEY_PATH" = "$SAFE_KEY" ]; then
		[ -f "$SAFE_CRT" ] && [ -f "$SAFE_KEY" ] || return 1
		validate_cert_file "$SAFE_CRT" || return 1
		validate_key_file "$SAFE_KEY" || return 1
		return 0
	fi

	warn "Certificate/key paths are outside ${DIR}; copying them into mihomo's safe path."
	CERT_SRC_CRT="$CERT_PATH"
	CERT_SRC_KEY="$KEY_PATH"
	install_cert_to_safe_paths "$CERT_SRC_CRT" "$CERT_SRC_KEY"
}

sync_cert_from_meta() {
	load_meta
	if [ -z "${CERT_SRC_CRT:-}" ] || [ -z "${CERT_SRC_KEY:-}" ]; then
		[ -f "$SAFE_CRT" ] && [ -f "$SAFE_KEY" ] && return 0
		err "No source certificate paths are stored in $META."
		return 1
	fi
	install_cert_to_safe_paths "$CERT_SRC_CRT" "$CERT_SRC_KEY" || return 1
	save_meta
}

find_acme_bin() {
	if [ -x "${HOME:-/root}/.acme.sh/acme.sh" ]; then
		echo "${HOME:-/root}/.acme.sh/acme.sh"
	elif [ -x "/root/.acme.sh/acme.sh" ]; then
		echo "/root/.acme.sh/acme.sh"
	else
		command -v acme.sh 2>/dev/null || true
	fi
}

acme_install_to_safe_paths() {
	local domain="$1" ecc="$2" acme args=()
	acme=$(find_acme_bin)
	[ -n "$acme" ] && [ -x "$acme" ] || return 1
	[ "$ecc" = "1" ] && args+=(--ecc)
	"$acme" --install-cert -d "$domain" "${args[@]}" \
		--key-file "$SAFE_KEY" \
		--fullchain-file "$SAFE_CRT" \
		--reloadcmd "systemctl restart ${SERVICE_NAME}" >/dev/null 2>&1
}

write_certbot_hook() {
	[ -d /etc/letsencrypt ] || return 0
	mkdir -p /etc/letsencrypt/renewal-hooks/deploy
	cat >"$CERTBOT_HOOK" <<EOF_HOOK
#!/bin/sh
# Generated by anytls_maneger.sh. Keep mihomo-safe cert copies fresh.
if [ -x "$SELF_CMD" ]; then
  "$SELF_CMD" sync-cert --quiet >/dev/null 2>&1 || true
fi
systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true
EOF_HOOK
	chmod +x "$CERTBOT_HOOK"
}

#------------------------------- padding --------------------------------------
write_upstream_default_padding_tmp() {
	local f="$1"
	cat >"$f" <<'EOF_DEFAULT_PADDING'
stop=8
0=30-30
1=100-400
2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000
3=9-9,500-1000
4=500-1000
5=500-1000
6=500-1000
7=500-1000
EOF_DEFAULT_PADDING
}

padding_is_upstream_default() {
	[ -f "$PADDING" ] || return 1
	local tmp
	tmp=$(mktemp)
	write_upstream_default_padding_tmp "$tmp"
	if cmp -s "$PADDING" "$tmp"; then
		rm -f "$tmp"
		return 0
	fi
	rm -f "$tmp"
	return 1
}

write_custom_padding() {
	mkdir -p "$DIR"
	cat >"$PADDING" <<'EOF_PADDING'
stop=10
0=80-160
1=160-520,c,90-260
2=360-760,c,600-1180,c,300-820,c,520-980
3=128-384,c,700-1200
4=256-768,c,300-900
5=640-1280
6=144-512,c,512-1024
7=900-1400,c,120-360
8=300-700
9=64-256,c,400-900
EOF_PADDING
	chmod 600 "$PADDING"
}

ensure_padding() {
	mkdir -p "$DIR"
	if [ ! -f "$PADDING" ]; then
		write_custom_padding
		return
	fi
	if padding_is_upstream_default; then
		warn "Old upstream default padding-scheme detected; replacing it with the bundled custom scheme."
		write_custom_padding
	fi
}

#------------------------------- config write ---------------------------------
write_config() {
	ensure_padding
	ensure_cert_safe_paths || die "Certificate setup failed. Run '$0 repair' or redo TLS."

	# YAML single-quoted scalar escaping: ' becomes ''.
	local pw_yaml="${PASSWORD//\'/\'\'}"
	local pad_indented
	pad_indented=$(sed 's/^/      /' "$PADDING")

	cat >"$CONF" <<EOF_CONFIG
# Generated by anytls_maneger.sh — do not edit by hand unless you know why.
log-level: warning
mode: rule
ipv6: $([ "$LISTEN" = "::" ] && echo true || echo false)
listeners:
  - name: anytls-in
    type: anytls
    listen: "$LISTEN"
    port: $PORT
    users:
      anytls: '$pw_yaml'
    certificate: "$CERT_PATH"
    private-key: "$KEY_PATH"
    padding-scheme: |
$pad_indented
rules:
  - MATCH,DIRECT
EOF_CONFIG
	chmod 600 "$CONF"
}

#------------------------------- systemd --------------------------------------
write_service() {
	cat >"$SERVICE" <<EOF_SERVICE
[Unit]
Description=AnyTLS service (mihomo core)
Documentation=https://github.com/${ANYTLS_REPO}
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DIR
ExecStart=$BIN -d $DIR -f $CONF
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF_SERVICE
	systemctl daemon-reload
}

#------------------------------- binary install -------------------------------
install_mihomo() {
	local tag="$1"
	[ -n "$tag" ] || tag=$(latest_mihomo_tag) || die "Could not resolve latest mihomo version."
	local march asset url tmp
	march=$(arch_tag)
	asset="mihomo-linux-${march}-${tag}.gz"
	url="https://github.com/${MIHOMO_REPO}/releases/download/${tag}/${asset}"
	tmp=$(mktemp -d)
	inf "Downloading mihomo ${tag} (${march}) ..."
	if ! curl -fSL --retry 3 --connect-timeout 15 -o "$tmp/m.gz" "$url"; then
		rm -rf "$tmp"
		die "Download failed: $url"
	fi
	gzip -dc "$tmp/m.gz" >"$tmp/mihomo" || {
		rm -rf "$tmp"
		die "Decompress failed."
	}
	install -m 0755 "$tmp/mihomo" "$BIN"
	rm -rf "$tmp"
	ok "mihomo $("$BIN" -v 2>/dev/null | head -n1)"
}

#------------------------------- TLS handling ---------------------------------
collect_certs() {
	C_NAME=()
	C_CRT=()
	C_KEY=()
	C_TYPE=()
	C_ECC=()
	local d name base

	if [ -d /etc/letsencrypt/live ]; then
		for d in /etc/letsencrypt/live/*/; do
			[ -f "${d}fullchain.pem" ] && [ -f "${d}privkey.pem" ] || continue
			name=$(basename "$d")
			C_NAME+=("$name")
			C_CRT+=("${d}fullchain.pem")
			C_KEY+=("${d}privkey.pem")
			C_TYPE+=("certbot")
			C_ECC+=("0")
		done
	fi

	local bases=("/root/.acme.sh")
	[ "${HOME:-/root}/.acme.sh" != "/root/.acme.sh" ] && bases+=("${HOME}/.acme.sh")
	for base in "${bases[@]}"; do
		[ -d "$base" ] || continue
		for d in "$base"/*/; do
			[ -d "$d" ] || continue
			name=$(basename "$d")
			local ecc=0
			case "$name" in *_ecc)
				name=${name%_ecc}
				ecc=1
				;;
			esac
			[[ "$name" == *.* ]] || continue
			if [ -f "${d}fullchain.cer" ] && [ -f "${d}${name}.key" ]; then
				C_NAME+=("$name")
				C_CRT+=("${d}fullchain.cer")
				C_KEY+=("${d}${name}.key")
				C_TYPE+=("acme.sh")
				C_ECC+=("$ecc")
			fi
		done
	done
}

tls_use_existing() {
	collect_certs
	if [ "${#C_NAME[@]}" -eq 0 ]; then
		warn "No existing Let's Encrypt / acme.sh certificates were found."
		return 1
	fi

	echo "Existing certificates:"
	local i
	for i in "${!C_NAME[@]}"; do
		printf "  %2d) %-30s [%s]\n      crt: %s\n" "$((i + 1))" "${C_NAME[$i]}" "${C_TYPE[$i]}" "${C_CRT[$i]}"
	done

	local sel
	read -rp "Pick a domain [1-${#C_NAME[@]}]: " sel
	[[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#C_NAME[@]}" ] || {
		err "Invalid choice."
		return 1
	}
	sel=$((sel - 1))

	DOMAIN="${C_NAME[$sel]}"
	SNI="$DOMAIN"
	INSECURE=0
	TLS_MODE="le-existing"
	CERT_SRC_CRT="${C_CRT[$sel]}"
	CERT_SRC_KEY="${C_KEY[$sel]}"
	ACME_ECC="${C_ECC[$sel]}"

	if [ "${C_TYPE[$sel]}" = "acme.sh" ]; then
		if acme_install_to_safe_paths "$DOMAIN" "$ACME_ECC"; then
			ok "acme.sh install-cert now writes renewed certs directly into ${DIR}."
		else
			warn "Could not update acme.sh install-cert target; using a safe-path copy now."
			install_cert_to_safe_paths "$CERT_SRC_CRT" "$CERT_SRC_KEY" || return 1
		fi
	else
		install_cert_to_safe_paths "$CERT_SRC_CRT" "$CERT_SRC_KEY" || return 1
		write_certbot_hook
	fi

	CERT_PATH="$SAFE_CRT"
	KEY_PATH="$SAFE_KEY"
	ok "Using certificate for ${DOMAIN}; mihomo-safe copy: ${SAFE_CRT}"
}

tls_self_signed() {
	local cn
	read -rp "SNI/CN for the self-signed cert (use a real big-site name) [www.bing.com]: " cn
	cn="${cn:-www.bing.com}"
	inf "Generating EC self-signed certificate (36500 days, CN=${cn}) ..."
	mkdir -p "$DIR"
	openssl ecparam -name prime256v1 -genkey -noout -out "$SAFE_KEY" 2>/dev/null ||
		die "openssl key generation failed."
	openssl req -x509 -new -key "$SAFE_KEY" -out "$SAFE_CRT" -days 36500 -nodes \
		-subj "/CN=${cn}" -addext "subjectAltName=DNS:${cn}" 2>/dev/null ||
		die "openssl certificate generation failed."
	chmod 0644 "$SAFE_CRT"
	chmod 0600 "$SAFE_KEY"
	CERT_PATH="$SAFE_CRT"
	KEY_PATH="$SAFE_KEY"
	CERT_SRC_CRT=""
	CERT_SRC_KEY=""
	ACME_ECC="0"
	DOMAIN=""
	SNI="$cn"
	INSECURE=1
	TLS_MODE="self"
	ok "Self-signed certificate created inside ${DIR}."
}

tls_letsencrypt_new() {
	local domain account_email acme
	read -rp "Domain (must already point to THIS server's IP): " domain
	domain=$(lower_domain "$domain")
	[ -n "$domain" ] || {
		err "Domain required."
		return 1
	}
	valid_domain "$domain" || {
		err "Invalid domain: $domain"
		return 1
	}

	account_email=$(acme_auto_email "$domain")
	inf "Using automatic Let's Encrypt account email: ${account_email}"
	warn "Port 80 must be free for the HTTP-01 challenge. The script will start acme.sh standalone mode on port 80."

	if ! command -v socat >/dev/null 2>&1; then
		inf "Installing socat (needed by acme.sh --standalone) ..."
		apt-get update -y >/dev/null 2>&1
		apt-get install -y socat >/dev/null 2>&1 || die "Failed to install socat."
	fi

	acme="${HOME:-/root}/.acme.sh/acme.sh"
	if [ ! -x "$acme" ]; then
		inf "Installing acme.sh ..."
		curl -fsSL https://get.acme.sh | sh -s email="$account_email" >/dev/null 2>&1
		acme="${HOME:-/root}/.acme.sh/acme.sh"
		[ -x "$acme" ] || die "acme.sh installation failed."
	fi

	"$acme" --set-default-ca --server letsencrypt >/dev/null 2>&1 || return 1

	if ! "$acme" --register-account -m "$account_email" --server letsencrypt --accountemail "$account_email" >/dev/null 2>&1; then
		warn "ACME account register did not succeed; trying account update with ${account_email}."
		"$acme" --update-account -m "$account_email" --server letsencrypt --accountemail "$account_email" >/dev/null 2>&1 ||
			{
				err "ACME account setup failed. Try: ${acme} --register-account -m ${account_email} --server letsencrypt --debug"
				return 1
			}
	fi

	open_firewall 80
	inf "Issuing certificate for ${domain} (standalone HTTP-01, port 80) ..."
	if ! "$acme" --issue -d "$domain" --standalone --httpport 80 \
		--keylength ec-256 --server letsencrypt --accountemail "$account_email"; then
		err "Certificate issuance failed. Check DNS A/AAAA records, firewall, and that port 80 is not occupied."
		return 1
	fi

	inf "Installing certificate into mihomo-safe paths under ${DIR} ..."
	"$acme" --install-cert -d "$domain" --ecc \
		--key-file "$SAFE_KEY" \
		--fullchain-file "$SAFE_CRT" \
		--reloadcmd "systemctl restart ${SERVICE_NAME}" >/dev/null 2>&1 ||
		die "acme.sh install-cert failed."

	chmod 0644 "$SAFE_CRT"
	chmod 0600 "$SAFE_KEY"
	validate_cert_file "$SAFE_CRT" || die "Installed certificate is invalid."
	validate_key_file "$SAFE_KEY" || die "Installed private key is invalid."
	cert_key_match "$SAFE_CRT" "$SAFE_KEY" || die "Installed certificate/key do not match."

	CERT_PATH="$SAFE_CRT"
	KEY_PATH="$SAFE_KEY"
	CERT_SRC_CRT="$SAFE_CRT"
	CERT_SRC_KEY="$SAFE_KEY"
	ACME_ECC="1"
	DOMAIN="$domain"
	SNI="$domain"
	INSECURE=0
	TLS_MODE="le-new"
	ok "Let's Encrypt certificate issued for ${domain}; renewed certs will stay under ${DIR}."
}

choose_tls() {
	while :; do
		hr
		echo "${W}TLS certificate — choose how the server presents itself:${N}"
		echo "  1) Use an EXISTING domain certificate (Let's Encrypt / acme.sh on this box)"
		echo "  2) Generate a self-signed certificate (36500 days)"
		echo "  3) Issue a NEW Let's Encrypt certificate now (needs port 80 free; no email input)"
		hr
		local c
		read -rp "Select [1-3]: " c
		case "$c" in
		1) tls_use_existing && return 0 ;;
		2) tls_self_signed && return 0 ;;
		3) tls_letsencrypt_new && return 0 ;;
		*) err "Invalid choice." ;;
		esac
		warn "Let's try the TLS step again."
	done
}

#------------------------------- URI + info -----------------------------------
build_uri() {
	load_meta
	local host pw_enc uri
	pw_enc=$(urlencode "$PASSWORD")
	if [ -n "$DOMAIN" ]; then
		host="$DOMAIN"
	else
		local ip4 ip6
		ip4=$(get_ip4)
		ip6=$(get_ip6)
		if [ -n "$ip4" ]; then
			host="$ip4"
		elif [ -n "$ip6" ]; then
			host="[$ip6]"
		else host="SERVER_IP"; fi
	fi
	uri="anytls://${pw_enc}@${host}:${PORT}/?"
	[ -n "$SNI" ] && [[ "$SNI" == *.* ]] && uri+="sni=${SNI}&"
	uri+="insecure=${INSECURE}"
	echo "$uri"
}

port_listening() {
	local p="$1"
	ss -ltnH 2>/dev/null | awk -v p=":${p}" '{ if ($4 ~ p"$") found=1 } END { exit found ? 0 : 1 }'
}

service_state() { systemctl is-active "$SERVICE_NAME" 2>/dev/null || true; }

show_info() {
	is_installed || die "AnyTLS is not installed yet. Run: $0 install"
	load_meta
	local ip4 ip6 status listen_status
	ip4=$(get_ip4)
	ip6=$(get_ip6)
	status=$(service_state)
	if port_listening "$PORT"; then listen_status="${G}yes${N}"; else listen_status="${R}no${N}"; fi

	hr
	echo "${W}AnyTLS connection info${N}"
	hr
	printf "  %-14s %s\n" "Service:" "$([ "$status" = active ] && echo "${G}running${N}" || echo "${R}${status:-stopped}${N}")"
	printf "  %-14s %s\n" "Listening:" "$listen_status on TCP/${PORT}"
	printf "  %-14s %s\n" "Core:" "mihomo $(installed_mihomo_ver)"
	printf "  %-14s %s\n" "Server IP:" "${ip4:-n/a}${ip6:+ / [$ip6]}"
	printf "  %-14s %s\n" "Port:" "$PORT"
	printf "  %-14s %s\n" "Password:" "$PASSWORD"
	case "$TLS_MODE" in
	le-existing) printf "  %-14s %s\n" "TLS:" "Existing LE/acme cert (${DOMAIN}) — verified, no insecure" ;;
	le-new) printf "  %-14s %s\n" "TLS:" "New LE cert (${DOMAIN}) — verified, no insecure" ;;
	self) printf "  %-14s %s\n" "TLS:" "Self-signed (SNI ${SNI}) — client must allow insecure" ;;
	*) printf "  %-14s %s\n" "TLS:" "unknown" ;;
	esac
	[ -n "$DOMAIN" ] && printf "  %-14s %s\n" "Domain/SNI:" "$DOMAIN"
	printf "  %-14s %s\n" "Cert path:" "${CERT_PATH:-n/a}"
	printf "  %-14s %s\n" "Key path:" "${KEY_PATH:-n/a}"
	[ -f "$PADDING" ] && printf "  %-14s %s\n" "Padding:" "$PADDING"
	hr
	echo "${W}Share URI (Shadowrocket / NekoBox / sing-box / mihomo):${N}"
	echo "${G}$(build_uri)${N}"
	if [ "$INSECURE" = 1 ]; then
		warn "Self-signed: enable 'Allow insecure' on the client."
	fi
	if [ -n "$DOMAIN" ] && [ -n "$ip4" ]; then
		echo
		echo "If your client connects by IP instead of domain, use:"
		echo "  ${B}anytls://$(urlencode "$PASSWORD")@${ip4}:${PORT}/?sni=${DOMAIN}&insecure=0${N}"
	fi
	hr
}

#------------------------------- service ops ----------------------------------
svc() {
	case "$1" in
	start)
		systemctl start "$SERVICE_NAME"
		verify_running
		;;
	stop)
		systemctl stop "$SERVICE_NAME"
		ok "stopped"
		;;
	restart)
		systemctl restart "$SERVICE_NAME"
		verify_running
		;;
	status) systemctl status "$SERVICE_NAME" --no-pager ;;
	esac
}

show_logs() { journalctl -u "$SERVICE_NAME" -n 80 --no-pager --output=short-iso; }

verify_running() {
	load_meta 2>/dev/null || true
	sleep 1
	if ! systemctl is-active --quiet "$SERVICE_NAME"; then
		err "Service failed to start. Recent logs:"
		journalctl -u "$SERVICE_NAME" -n 40 --no-pager
		return 1
	fi
	if ! port_listening "$PORT"; then
		err "Service process is active, but nothing is listening on TCP/${PORT}. Recent logs:"
		journalctl -u "$SERVICE_NAME" -n 40 --no-pager
		return 1
	fi
	ok "Service is active and listening on TCP/${PORT}."
}

#------------------------------- install / repair -----------------------------
do_repair() {
	need_root
	is_installed || die "Not installed yet."
	load_meta

	if [ -n "${CERT_SRC_CRT:-}" ] && [ -n "${CERT_SRC_KEY:-}" ]; then
		inf "Refreshing safe certificate copy from stored source paths."
		sync_cert_from_meta || die "Certificate sync failed."
	elif [ -n "${CERT_PATH:-}" ] && [ -n "${KEY_PATH:-}" ]; then
		inf "Migrating configured certificate/key into ${DIR}."
		ensure_cert_safe_paths || die "Certificate migration failed."
	else
		die "No certificate paths found in ${META}. Redo TLS via: $0 reconfigure"
	fi

	CERT_PATH="$SAFE_CRT"
	KEY_PATH="$SAFE_KEY"
	write_config
	write_service
	save_meta
	systemctl restart "$SERVICE_NAME"
	verify_running
}

do_install() {
	need_root
	ensure_deps
	mkdir -p "$DIR"

	if is_installed; then
		warn "AnyTLS is already installed."
		read -rp "Reinstall / reconfigure? [y/N]: " yn
		[[ "$yn" =~ ^[Yy]$ ]] || return 0
		load_meta
	fi

	[ -x "$BIN" ] || install_mihomo ""

	local p
	read -rp "Listen port [${PORT:-$DEFAULT_PORT}]: " p
	PORT="${p:-${PORT:-$DEFAULT_PORT}}"
	valid_port "$PORT" || die "Invalid port: $PORT"

	read -rp "Password [${PASSWORD:-$DEFAULT_PASSWORD}]: " p
	PASSWORD="${p:-${PASSWORD:-$DEFAULT_PASSWORD}}"

	if ipv6_enabled; then LISTEN="::"; else LISTEN="0.0.0.0"; fi

	choose_tls
	ensure_padding
	write_config
	write_service
	save_meta
	open_firewall "$PORT"
	copy_self_command
	write_certbot_hook

	systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
	systemctl restart "$SERVICE_NAME"
	verify_running

	echo
	show_info
}

#------------------------------- reconfigure ----------------------------------
reconfigure() {
	need_root
	is_installed || die "Not installed yet."
	load_meta
	while :; do
		hr
		echo "${W}Reconfigure${N} (current: port ${PORT}, TLS ${TLS_MODE}${DOMAIN:+ / $DOMAIN})"
		echo "  1) Change port"
		echo "  2) Change password"
		echo "  3) Redo TLS certificate"
		echo "  4) Edit padding scheme"
		echo "  5) Reset to bundled custom padding scheme"
		echo "  6) Repair/migrate cert paths into ${DIR}"
		echo "  7) Back"
		hr
		local c
		read -rp "Select: " c
		case "$c" in
		1)
			local np
			read -rp "New port [$PORT]: " np
			np="${np:-$PORT}"
			valid_port "$np" || {
				err "Invalid port."
				continue
			}
			PORT="$np"
			write_config
			save_meta
			open_firewall "$PORT"
			svc restart
			;;
		2)
			local npw
			read -rp "New password [keep current]: " npw
			[ -n "$npw" ] && PASSWORD="$npw"
			write_config
			save_meta
			svc restart
			;;
		3)
			choose_tls
			write_config
			save_meta
			svc restart
			;;
		4)
			${EDITOR:-nano} "$PADDING" 2>/dev/null || vi "$PADDING"
			write_config
			svc restart
			;;
		5)
			write_custom_padding
			write_config
			svc restart
			;;
		6) do_repair ;;
		7) break ;;
		*) err "Invalid choice." ;;
		esac
		ok "Applied."
	done
	show_info
}

#------------------------------- update ---------------------------------------
do_update() {
	need_root
	is_installed || die "Not installed yet."
	local cur new
	cur=$(installed_mihomo_ver)
	inf "Checking latest mihomo release ..."
	new=$(latest_mihomo_tag) || die "Could not reach GitHub."
	hr
	echo "  Installed core : mihomo ${cur}"
	echo "  Latest release : mihomo ${new}"
	echo "  Protocol ref   : https://github.com/${ANYTLS_REPO}"
	hr
	if [ "v${cur#v}" = "v${new#v}" ]; then
		ok "Already on the latest version."
		read -rp "Force re-download anyway? [y/N]: " yn
		[[ "$yn" =~ ^[Yy]$ ]] || return 0
	fi
	read -rp "Update mihomo core to ${new}? [Y/n]: " yn
	[[ "$yn" =~ ^[Nn]$ ]] && return 0
	install_mihomo "$new"
	svc restart
}

#------------------------------- uninstall ------------------------------------
do_uninstall() {
	need_root
	is_installed || die "Not installed."
	read -rp "Remove AnyTLS, its config and certs from $DIR? [y/N]: " yn
	[[ "$yn" =~ ^[Yy]$ ]] || return 0
	systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1
	rm -f "$SERVICE"
	systemctl daemon-reload
	rm -rf "$DIR"
	rm -f "$CERTBOT_HOOK" 2>/dev/null
	[ "$0" != "$SELF_CMD" ] && rm -f "$SELF_CMD" 2>/dev/null
	ok "AnyTLS removed. acme.sh / certbot themselves were left untouched."
}

#------------------------------- menu / cli -----------------------------------
about() {
	hr
	echo "${W}AnyTLS manager${N} — core: mihomo (${MIHOMO_REPO})"
	echo "AnyTLS protocol reference: https://github.com/${ANYTLS_REPO}"
	echo "Compatible clients: Shadowrocket, NekoBox, sing-box, mihomo."
	echo "Install defaults: port ${DEFAULT_PORT}, password ${DEFAULT_PASSWORD}."
	echo "Cert safe-path fix: config always uses ${SAFE_CRT} and ${SAFE_KEY}."
	hr
}

menu() {
	while :; do
		echo
		echo "${W}===== AnyTLS Manager =====${N}"
		if is_installed; then
			local st lstn
			load_meta
			st=$(service_state)
			if port_listening "$PORT"; then lstn="${G}listening${N}"; else lstn="${R}not-listening${N}"; fi
			echo "  core: mihomo $(installed_mihomo_ver)   service: $([ "$st" = active ] && echo "${G}running${N}" || echo "${R}${st}${N}") / ${lstn}"
		else
			echo "  ${Y}not installed${N}"
		fi
		echo "---------------------------------"
		echo "  1) Install / Reinstall"
		echo "  2) Show connection info (URI)"
		echo "  3) Start          4) Stop"
		echo "  5) Restart        6) Status"
		echo "  7) View logs"
		echo "  8) Reconfigure (port / password / TLS / padding)"
		echo "  9) Update core (mihomo) to latest"
		echo " 10) Repair cert safe-path bug"
		echo " 11) Uninstall"
		echo " 12) About"
		echo "  0) Exit"
		echo "---------------------------------"
		local c
		read -rp "Select: " c
		case "$c" in
		1) do_install ;;
		2) show_info ;;
		3) svc start ;;
		4) svc stop ;;
		5) svc restart ;;
		6) svc status ;;
		7) show_logs ;;
		8) reconfigure ;;
		9) do_update ;;
		10) do_repair ;;
		11) do_uninstall ;;
		12) about ;;
		0) exit 0 ;;
		*) err "Invalid choice." ;;
		esac
	done
}

usage() {
	cat <<EOF_USAGE
Usage: $0 [command]
  (no args)                 interactive menu
  install | setup           install / reconfigure
  info | uri                show connection info + URI
  start|stop|restart|status service control
  logs                      recent service logs
  reconfigure | config      change port / password / TLS / padding
  update | upgrade          update mihomo core to the latest release
  repair | fix              migrate/copy certs into /etc/anytls and restart
  sync-cert                 refresh /etc/anytls cert copy from stored source paths
  uninstall | remove        remove AnyTLS
  about                     show about info
EOF_USAGE
}

#------------------------------- entrypoint -----------------------------------
case "${1:-}" in
"" | menu)
	need_root
	menu
	;;
install | setup) do_install ;;
info | uri) show_info ;;
start | stop | restart | status)
	need_root
	svc "$1"
	;;
logs) show_logs ;;
reconfigure | config) reconfigure ;;
update | upgrade) do_update ;;
repair | fix) do_repair ;;
sync-cert)
	need_root
	sync_cert_from_meta
	[ "${2:-}" = "--quiet" ] || ok "Certificate copy refreshed: ${SAFE_CRT}"
	;;
uninstall | remove) do_uninstall ;;
about) about ;;
-h | --help | help) usage ;;
*)
	err "Unknown command: $1"
	usage
	exit 1
	;;
esac
