#!/usr/bin/env bash
#
# naive_systemctl_maneger.sh - interactive manager for NaiveProxy (Caddy v2) via systemctl
#
# Fixed version:
#   - Keeps Caddy on the configured custom port only (default 8443).
#   - Uses `auto_https off` so Caddy will NOT create :80/:443 redirect/listeners.
#   - Uses the known-good NaiveProxy Caddyfile shape:
#       :PORT, domain {
#         tls ...
#         route { forward_proxy { ... } file_server { ... } }
#       }
#   - Refuses to install empty TLS keys/certs.
#   - Recovers a matching acme.sh key from backup when possible.
#   - If the acme.sh private key is lost/zero-byte, offers a fresh re-issue
#     instead of wasting time on `acme.sh --renew`, which cannot recreate a lost key.
#   - Avoids symlink truncation bugs by deleting install-cert targets first.
#   - Validates Caddyfile before starting/restarting where possible.
#
# Usage:
#   bash naive_systemctl_maneger.sh
#
set -u

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
naive_path=/root/naive_s
conf_path=${naive_path}/naive.conf
caddy_path=${naive_path}/Caddyfile
cert_dir=${naive_path}/certs
www_dir=${naive_path}/www
log_dir=${naive_path}/log

CADDY_BIN=/usr/local/bin/caddy
SERVICE_NAME=naive
SERVICE_FILE=/etc/systemd/system/${SERVICE_NAME}.service

DEFAULT_PORT=8443

# probe_resistance decoy - must be a plain hostname token, not a URL.
PROBE_DECOY="oracle.com"

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
ok()   { printf '%s[+]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
err()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
hr()   { printf '%s\n' "------------------------------------------------------------"; }
pause() { read -rp "Press Enter to continue..." _ || true; }

# --------------------------------------------------------------------------- #
# Environment detection
# --------------------------------------------------------------------------- #
ACME_BIN=""
ACME_HOME=""

# runtime vars stored in naive.conf
DOMAIN=""
PORT="$DEFAULT_PORT"
NAIVE_USER="naive"
NAIVE_PASS="naive_password"
SECRET="$PROBE_DECOY"
ECC="--ecc"

detect_root() {
	if [ "$(id -u)" -ne 0 ]; then
		err "Please run as root."
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

auto_install_go() {
	info "Detecting system architecture ..."
	local arch
	case "$(uname -m)" in
	x86_64)  arch="amd64"  ;;
	aarch64) arch="arm64"  ;;
	armv7l)  arch="armv6l" ;;
	*)
		err "Unsupported arch: $(uname -m)"
		return 1
		;;
	esac
	info "Fetching latest Go version ..."
	local go_ver
	go_ver="$(curl -fsSL https://go.dev/VERSION?m=text | head -1)" || {
		err "Could not fetch Go version. Check network."
		return 1
	}
	local tarball="${go_ver}.linux-${arch}.tar.gz"
	local url="https://dl.google.com/go/${tarball}"
	info "Downloading ${url} ..."
	curl -fsSL "$url" -o "/tmp/${tarball}" || {
		err "Download failed."
		return 1
	}
	info "Installing Go to /usr/local/go ..."
	rm -rf /usr/local/go
	tar -C /usr/local -xzf "/tmp/${tarball}"
	rm -f "/tmp/${tarball}"
	export PATH="/usr/local/go/bin:$PATH"
	go version && ok "Go installed: $(go version)"
}

build_caddy() {
	info "Installing xcaddy ..."
	export PATH="/usr/local/go/bin:${GOPATH:-/root/go}/bin:$PATH"
	go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest || {
		err "xcaddy install failed."
		return 1
	}
	local xcaddy
	xcaddy="$(command -v xcaddy 2>/dev/null)" || xcaddy="${GOPATH:-/root/go}/bin/xcaddy"
	[ -x "$xcaddy" ] || {
		err "xcaddy binary not found."
		return 1
	}

	info "Building caddy with naive forwardproxy ..."
	local tmpdir
	tmpdir="$(mktemp -d)"
	(
		cd "$tmpdir"
		"$xcaddy" build \
			--with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive \
			--output ./caddy
	) || {
		err "caddy build failed."
		rm -rf "$tmpdir"
		return 1
	}

	mv "${tmpdir}/caddy" "$CADDY_BIN"
	chmod +x "$CADDY_BIN"
	setcap cap_net_bind_service=+ep "$CADDY_BIN" 2>/dev/null || true
	rm -rf "$tmpdir"
	ok "caddy built and installed at ${CADDY_BIN}"
}

detect_caddy() {
	if [ ! -x "$CADDY_BIN" ]; then
		warn "Caddy not found at ${CADDY_BIN}."
		read -rp "Auto-build caddy with naive plugin now? [Y/n]: " a
		case "$a" in n | N) err "caddy is required. Aborting."; exit 1 ;; esac

		export PATH="/usr/local/go/bin:$PATH"
		if ! command -v go >/dev/null 2>&1; then
			warn "Go not found. Installing Go automatically ..."
			auto_install_go || { err "Go install failed. Aborting."; exit 1; }
		else
			ok "Go found: $(go version)"
		fi

		build_caddy || { err "caddy build failed. Aborting."; exit 1; }
	fi

	if ! "$CADDY_BIN" list-modules 2>/dev/null | grep -q "http.handlers.forward_proxy"; then
		err "Caddy at ${CADDY_BIN} does not include the naive forward_proxy module."
		read -rp "Rebuild caddy with naive plugin now? [Y/n]: " a
		case "$a" in n | N) err "Aborting."; exit 1 ;; esac
		export PATH="/usr/local/go/bin:${GOPATH:-/root/go}/bin:$PATH"
		build_caddy || { err "caddy rebuild failed. Aborting."; exit 1; }
	fi
}

# --------------------------------------------------------------------------- #
# Config helpers
# --------------------------------------------------------------------------- #
is_installed() { [ -f "$conf_path" ]; }

load_conf() {
	if ! is_installed; then
		err "Not installed yet. Run install (option 1 or 2) first."
		return 1
	fi
	# shellcheck disable=SC1090
	. "$conf_path"
}

save_conf() {
	mkdir -p "$naive_path"
	SECRET="$(printf '%s' "$SECRET" | tr '[:upper:]' '[:lower:]')"
	cat >"$conf_path" <<EOF
# Generated by naive_systemctl_maneger.sh
$(printf 'DOMAIN=%q\n' "$DOMAIN")
$(printf 'PORT=%q\n' "$PORT")
$(printf 'NAIVE_USER=%q\n' "$NAIVE_USER")
$(printf 'NAIVE_PASS=%q\n' "$NAIVE_PASS")
$(printf 'SECRET=%q\n' "$SECRET")
$(printf 'ECC=%q\n' "$ECC")
EOF
	chmod 600 "$conf_path"
}

caddy_escape() {
	# Escape for a Caddyfile double-quoted string.
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# --------------------------------------------------------------------------- #
# Download pre-built Caddy+forwardproxy server binary.
# --------------------------------------------------------------------------- #
_gh_latest_tag() {
	local repo="$1"
	local tag
	tag="$(curl -fsSL \
		-H "Accept: application/vnd.github+json" \
		"https://api.github.com/repos/${repo}/releases/latest" \
		2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')"
	if [ -z "$tag" ]; then
		tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
			"https://github.com/${repo}/releases/latest" 2>/dev/null | sed 's|.*/tag/||')"
	fi
	printf '%s' "$tag"
}

download_naiveproxy() {
	local michaol_arch
	case "$(uname -m)" in
	x86_64)  michaol_arch="amd64" ;;
	aarch64) michaol_arch="arm64" ;;
	armv7l)  michaol_arch=""      ;;
	*)       michaol_arch=""      ;;
	esac

	local tmpdir
	tmpdir="$(mktemp -d)"
	local installed=0

	# PRIMARY: klzgrad/forwardproxy official server Caddy binary, x86_64 only.
	if [ "$(uname -m)" = "x86_64" ]; then
		info "Fetching latest klzgrad/forwardproxy release tag ..."
		local fp_tag
		fp_tag="$(_gh_latest_tag "klzgrad/forwardproxy")"
		if [ -n "$fp_tag" ]; then
			local fp_asset="caddy-forwardproxy-naive.tar.xz"
			local fp_url="https://github.com/klzgrad/forwardproxy/releases/download/${fp_tag}/${fp_asset}"
			info "Downloading caddy from klzgrad/forwardproxy ${fp_tag} ..."
			if curl -fsSL --retry 3 -o "${tmpdir}/${fp_asset}" "$fp_url" 2>/dev/null; then
				info "Extracting ..."
				if tar -C "$tmpdir" -xJf "${tmpdir}/${fp_asset}" 2>/dev/null; then
					local caddy_src
					caddy_src="$(find "$tmpdir" -maxdepth 2 -name "caddy" -type f | head -1)"
					if [ -n "$caddy_src" ] && [ -f "$caddy_src" ]; then
						cp "$caddy_src" "$CADDY_BIN"
						chmod +x "$CADDY_BIN"
						setcap cap_net_bind_service=+ep "$CADDY_BIN" 2>/dev/null || true
						rm -rf "$tmpdir"
						ok "caddy installed from klzgrad/forwardproxy ${fp_tag}"
						installed=1
					else
						warn "caddy not found in klzgrad/forwardproxy archive. Trying fallback ..."
					fi
				else
					warn "Extraction of klzgrad/forwardproxy archive failed. Trying fallback ..."
				fi
			else
				warn "Download from klzgrad/forwardproxy failed. Trying fallback ..."
			fi
		else
			warn "Could not fetch klzgrad/forwardproxy tag. Trying fallback ..."
		fi
	fi

	# FALLBACK: Michaol/caddy-naive, amd64 + arm64.
	if [ "$installed" -eq 0 ]; then
		if [ -z "$michaol_arch" ]; then
			rm -rf "$tmpdir"
			err "No pre-built binary available for $(uname -m)."
			err "Use option 1 (build from source) instead."
			return 1
		fi

		info "Fetching latest Michaol/caddy-naive release tag ..."
		local mn_tag
		mn_tag="$(_gh_latest_tag "Michaol/caddy-naive")"
		if [ -z "$mn_tag" ]; then
			rm -rf "$tmpdir"
			err "Could not determine Michaol/caddy-naive release tag."
			return 1
		fi

		local mn_asset="caddy-linux-${michaol_arch}"
		local mn_url="https://github.com/Michaol/caddy-naive/releases/download/${mn_tag}/${mn_asset}"
		info "Downloading caddy from Michaol/caddy-naive ${mn_tag} (linux-${michaol_arch}) ..."
		if ! curl -fsSL --retry 3 -o "${tmpdir}/caddy" "$mn_url" 2>/dev/null; then
			rm -rf "$tmpdir"
			err "Download failed: ${mn_url}"
			err "Both download sources failed. Use option 1 (build from source)."
			return 1
		fi

		cp "${tmpdir}/caddy" "$CADDY_BIN"
		chmod +x "$CADDY_BIN"
		setcap cap_net_bind_service=+ep "$CADDY_BIN" 2>/dev/null || true
		rm -rf "$tmpdir"
		ok "caddy installed from Michaol/caddy-naive ${mn_tag} (linux-${michaol_arch})"
		installed=1
	fi

	return 0
}

# --------------------------------------------------------------------------- #
# acme.sh: pick a domain and install/map cert
# --------------------------------------------------------------------------- #
pick_domain() {
	if [ -z "$ACME_BIN" ]; then
		err "acme.sh not found. Issue a cert with acme.sh first."
		return 1
	fi
	local domains=()
	mapfile -t domains < <("$ACME_BIN" --list 2>/dev/null | awk 'NR>1 && NF>0 {print $1}')
	if [ "${#domains[@]}" -eq 0 ]; then
		err "No certificates registered in acme.sh (${ACME_BIN} --list is empty)."
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
	if [ -d "${ACME_HOME}/${DOMAIN}_ecc" ]; then ECC="--ecc"; else ECC=""; fi
	ok "Selected: ${DOMAIN}  (${ECC:-rsa})"
}

acme_store_dir() {
	if [ "${ECC:-}" = "--ecc" ]; then
		printf '%s' "${ACME_HOME}/${DOMAIN}_ecc"
	else
		printf '%s' "${ACME_HOME}/${DOMAIN}"
	fi
}

pubkey_hash_cert() {
	openssl x509 -in "$1" -noout -pubkey 2>/dev/null |
		openssl pkey -pubin -outform DER 2>/dev/null |
		openssl sha256 2>/dev/null | awk '{print $NF}'
}

pubkey_hash_key() {
	openssl pkey -in "$1" -pubout -outform DER 2>/dev/null |
		openssl sha256 2>/dev/null | awk '{print $NF}'
}

cert_key_match() {
	local cert="$1" key="$2" ch kh
	[ -s "$cert" ] && [ -s "$key" ] || return 1
	command -v openssl >/dev/null 2>&1 || return 1
	ch="$(pubkey_hash_cert "$cert")"
	kh="$(pubkey_hash_key "$key")"
	[ -n "$ch" ] && [ -n "$kh" ] && [ "$ch" = "$kh" ]
}

acme_source_ok() {
	local store key full leaf cert_for_match
	store="$(acme_store_dir)"
	key="${store}/${DOMAIN}.key"
	full="${store}/fullchain.cer"
	leaf="${store}/${DOMAIN}.cer"
	[ -s "$full" ] && [ -s "$key" ] || return 1
	cert_for_match="$full"
	[ -s "$leaf" ] && cert_for_match="$leaf"
	cert_key_match "$cert_for_match" "$key"
}

recover_key_from_backup() {
	local store cert keyout cert_fp k cand_fp
	store="$(acme_store_dir)"
	cert="${store}/${DOMAIN}.cer"
	keyout="${store}/${DOMAIN}.key"

	[ -s "$cert" ] || return 1
	command -v openssl >/dev/null 2>&1 || return 1

	cert_fp="$(pubkey_hash_cert "$cert")"
	[ -n "$cert_fp" ] || return 1

	shopt -s nullglob
	for k in "${store}/backup/"* "${store}/${DOMAIN}.key"; do
		[ -f "$k" ] && [ -s "$k" ] || continue
		cand_fp="$(pubkey_hash_key "$k")"
		[ -n "$cand_fp" ] || continue
		if [ "$cand_fp" = "$cert_fp" ]; then
			if [ "$k" != "$keyout" ]; then
				cp "$k" "$keyout"
				chmod 600 "$keyout"
				ok "Recovered matching private key from: $k"
			fi
			return 0
		fi
	done
	return 1
}

port80_holders() {
	ss -lntup 2>/dev/null | awk '$5 ~ /:80$/ {print}'
}

issue_fresh_cert() {
	local store bak choice dns_plugin holder
	store="$(acme_store_dir)"

	warn "Could not recover a private key that matches the current certificate."
	warn "A fresh certificate with a NEW private key is required."
	echo
	echo "Re-issue method:"
	echo "  1) standalone HTTP-01  (temporarily needs port 80 free)"
	echo "  2) DNS API             (requires acme.sh dns plugin/env vars)"
	echo "  0) Abort"
	while :; do
		read -rp "Choose re-issue method [1/2/0]: " choice
		case "$choice" in 1 | 2 | 0) break ;; *) warn "Invalid choice." ;; esac
	done
	[ "$choice" != "0" ] || return 1

	if [ -d "$store" ]; then
		bak="${store}.broken.$(date +%Y%m%d-%H%M%S)"
		warn "Moving broken acme.sh store to: $bak"
		mv "$store" "$bak"
	fi

	case "$choice" in
	1)
		holder="$(port80_holders || true)"
		if [ -n "$holder" ]; then
			warn "Port 80 is currently occupied:"
			echo "$holder"
			read -rp "Try to stop common web services on :80 (caddy/nginx/apache2/httpd)? [y/N]: " a
			case "$a" in
			y | Y)
				systemctl stop caddy 2>/dev/null || true
				systemctl stop nginx 2>/dev/null || true
				systemctl stop apache2 2>/dev/null || true
				systemctl stop httpd 2>/dev/null || true
				;;
			*)
				err "Port 80 must be free for standalone validation."
				return 1
				;;
			esac
		fi
		"$ACME_BIN" --issue -d "$DOMAIN" ${ECC} --standalone --force || return 1
		;;
	2)
		read -rp "acme.sh DNS plugin name, e.g. dns_cf / dns_ali / dns_dp: " dns_plugin
		[ -n "$dns_plugin" ] || { err "DNS plugin name is required."; return 1; }
		"$ACME_BIN" --issue -d "$DOMAIN" ${ECC} --dns "$dns_plugin" --force || return 1
		;;
	esac

	if acme_source_ok; then
		ok "Fresh acme.sh source cert/key created and verified."
		return 0
	fi
	err "Fresh issuance finished, but acme.sh source cert/key is still invalid."
	return 1
}

ensure_acme_source() {
	local store cert
	store="$(acme_store_dir)"
	cert="${store}/${DOMAIN}.cer"

	if acme_source_ok; then
		return 0
	fi

	warn "acme.sh store for ${DOMAIN} has a missing/empty/mismatched key or fullchain."

	if [ -s "$cert" ] && recover_key_from_backup; then
		if [ ! -s "${store}/fullchain.cer" ] && [ -s "${store}/ca.cer" ]; then
			cat "$cert" "${store}/ca.cer" >"${store}/fullchain.cer"
		fi
		if acme_source_ok; then
			ok "acme.sh store repaired from backup."
			return 0
		fi
	fi

	issue_fresh_cert
}

install_cert() {
	mkdir -p "$cert_dir"

	# CRITICAL: kill stale targets/symlinks first.
	# If targets are symlinks back into acme.sh, install-cert redirection can
	# truncate the source and create 0-byte cert/key files.
	rm -f "${cert_dir}/fullchain.cer" "${cert_dir}/private.key"

	ensure_acme_source || return 1

	info "Installing/mapping cert for ${DOMAIN} via acme.sh ..."

	# First copy with no-op reload. Service may not exist yet.
	"$ACME_BIN" --install-cert -d "$DOMAIN" ${ECC} \
		--fullchain-file "${cert_dir}/fullchain.cer" \
		--key-file "${cert_dir}/private.key" \
		--reloadcmd "true" || true

	if [ -L "${cert_dir}/fullchain.cer" ] || [ -L "${cert_dir}/private.key" ]; then
		err "Cert targets are symlinks - refusing to avoid source truncation."
		return 1
	fi
	if [ ! -s "${cert_dir}/fullchain.cer" ] || [ ! -s "${cert_dir}/private.key" ]; then
		err "Cert install produced empty files in ${cert_dir}."
		err "acme.sh store dir: $(acme_store_dir)"
		ls -la "$(acme_store_dir)/" 2>/dev/null || true
		err "cert_dir:"
		ls -la "${cert_dir}/" 2>/dev/null || true
		return 1
	fi
	if ! cert_key_match "${cert_dir}/fullchain.cer" "${cert_dir}/private.key"; then
		err "Installed cert and private key do not match."
		return 1
	fi

	# Re-register real restart hook for future renewals.
	"$ACME_BIN" --install-cert -d "$DOMAIN" ${ECC} \
		--fullchain-file "${cert_dir}/fullchain.cer" \
		--key-file "${cert_dir}/private.key" \
		--reloadcmd "systemctl restart ${SERVICE_NAME} >/dev/null 2>&1 || true" \
		>/dev/null 2>&1 || true

	ok "Cert mapped into ${cert_dir} (fullchain=$(stat -c%s "${cert_dir}/fullchain.cer")B, key=$(stat -c%s "${cert_dir}/private.key")B)."
	ok "acme.sh will auto-restart '${SERVICE_NAME}' on every renewal."
}

# --------------------------------------------------------------------------- #
# File generators
# --------------------------------------------------------------------------- #
gen_caddyfile() {
	local u p s
	u="$(caddy_escape "$NAIVE_USER")"
	p="$(caddy_escape "$NAIVE_PASS")"
	s="$(printf '%s' "$SECRET" | tr '[:upper:]' '[:lower:]')"

	cat >"$caddy_path" <<EOF
{
  admin off
  auto_https off

  log {
    output file ${log_dir}/access.log
    level INFO
  }

  servers :${PORT} {
    protocols h1 h2 h3
  }
}

:${PORT}, ${DOMAIN} {
  tls ${cert_dir}/fullchain.cer ${cert_dir}/private.key

  route {
    forward_proxy {
      basic_auth "${u}" "${p}"
      hide_ip
      hide_via
      probe_resistance ${s}
    }

    file_server {
      root ${www_dir}
    }
  }
}
EOF
	ok "Wrote ${caddy_path}"
}

validate_caddyfile() {
	[ -x "$CADDY_BIN" ] || { err "Caddy binary not found: $CADDY_BIN"; return 1; }
	"$CADDY_BIN" validate --config "$caddy_path" --adapter caddyfile || return 1
	"$CADDY_BIN" fmt --overwrite "$caddy_path" >/dev/null 2>&1 || true
}

gen_service() {
	cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=NaiveProxy (Caddy forwardproxy)
Documentation=https://github.com/klzgrad/naiveproxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${CADDY_BIN} run --config ${caddy_path} --adapter caddyfile
Restart=on-failure
RestartSec=5s
TimeoutStopSec=10s
KillMode=mixed
LimitNOFILE=1048576
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	ok "Wrote ${SERVICE_FILE} and reloaded systemd."
}

# --------------------------------------------------------------------------- #
# Service helpers
# --------------------------------------------------------------------------- #
svc_enable()  { systemctl enable "$SERVICE_NAME" 2>/dev/null; }
svc_start()   { systemctl start  "$SERVICE_NAME"; }
svc_stop()    { systemctl stop   "$SERVICE_NAME"; }
svc_restart() { systemctl restart "$SERVICE_NAME"; }
svc_status()  { systemctl status  "$SERVICE_NAME" --no-pager -l; }

maybe_disable_stock_caddy_service() {
	# A separate caddy.service often owns :80/:443 with old configs.
	# naive.service runs its own /usr/local/bin/caddy instance.
	if systemctl is-active --quiet caddy 2>/dev/null; then
		warn "A separate caddy.service is active and may occupy :80/:443."
		read -rp "Stop and disable caddy.service now? [Y/n]: " a
		case "$a" in
		n | N) warn "Leaving caddy.service unchanged." ;;
		*)
			systemctl stop caddy 2>/dev/null || true
			systemctl disable caddy 2>/dev/null || true
			ok "Stopped/disabled caddy.service."
			;;
		esac
	fi
}

# --------------------------------------------------------------------------- #
# Connection info
# --------------------------------------------------------------------------- #
show_link() {
	load_conf || return 1
	hr
	printf '%sNaiveProxy connection info%s\n' "$C_G" "$C_0"
	hr
	printf 'Server   : %s\n' "$DOMAIN"
	printf 'Port     : %s\n' "$PORT"
	printf 'Username : %s\n' "$NAIVE_USER"
	printf 'Password : %s\n' "$NAIVE_PASS"
	printf 'Decoy    : %s  (probe_resistance fake host)\n' "$SECRET"
	echo
	echo "Proxy URL:"
	printf '  %shttps://%s:%s@%s:%s%s\n' "$C_B" "$NAIVE_USER" "$NAIVE_PASS" "$DOMAIN" "$PORT" "$C_0"
	echo
	echo "naive client config.json:"
	cat <<JSON
  {
    "listen": "socks://127.0.0.1:1080",
    "proxy": "https://${NAIVE_USER}:${NAIVE_PASS}@${DOMAIN}:${PORT}"
  }
JSON
	echo
	echo "Share link (SagerNet / NekoBox / sing-box):"
	printf '  naive+https://%s:%s@%s:%s?padding=true#%s\n' "$NAIVE_USER" "$NAIVE_PASS" "$DOMAIN" "$PORT" "$DOMAIN"
	hr
	warn "If user/pass contains special characters, URL-encode them in the link."
}

# --------------------------------------------------------------------------- #
# Prompts
# --------------------------------------------------------------------------- #
prompt_settings() {
	local p
	read -rp "Listen port [${DEFAULT_PORT}]: " p
	PORT="${p:-$DEFAULT_PORT}"
	while ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; do
		warn "Port must be 1-65535."
		read -rp "Listen port [${DEFAULT_PORT}]: " p
		PORT="${p:-$DEFAULT_PORT}"
	done
	read -rp "Username [naive]: " p
	NAIVE_USER="${p:-naive}"
	read -rp "Password [naive_password]: " p
	NAIVE_PASS="${p:-naive_password}"
}

# --------------------------------------------------------------------------- #
# Shared post-binary setup
# --------------------------------------------------------------------------- #
_do_install_common() {
	mkdir -p "$naive_path" "$cert_dir" "$www_dir" "$log_dir"
	[ -f "${www_dir}/index.html" ] || echo "<h1>It works.</h1>" >"${www_dir}/index.html"

	install_cert || return 1
	save_conf
	gen_caddyfile
	validate_caddyfile || return 1
	gen_service
	maybe_disable_stock_caddy_service

	setcap cap_net_bind_service=+ep "$CADDY_BIN" 2>/dev/null || true

	svc_enable
	svc_restart 2>/dev/null || svc_start

	echo
	ok "NaiveProxy is up."
	show_link
}

# --------------------------------------------------------------------------- #
# Menu actions
# --------------------------------------------------------------------------- #
do_install() {
	if is_installed; then
		warn "Already installed."
		read -rp "Reinstall / overwrite config? [y/N]: " a
		case "$a" in y | Y) ;; *) return 0 ;; esac
	fi

	detect_caddy
	pick_domain || { pause; return 1; }
	prompt_settings
	SECRET="$PROBE_DECOY"
	_do_install_common || { pause; return 1; }
	pause
}

do_install_no_build() {
	if is_installed; then
		warn "Already installed."
		read -rp "Reinstall / overwrite config? [y/N]: " a
		case "$a" in y | Y) ;; *) return 0 ;; esac
	fi

	if ! command -v curl >/dev/null 2>&1; then
		err "curl is required. Install with: apt install curl"
		pause
		return 1
	fi
	if ! command -v xz >/dev/null 2>&1; then
		warn "xz not found. Attempting install ..."
		apt-get update >/dev/null 2>&1 || true
		apt-get install -y xz-utils 2>/dev/null || {
			err "Could not install xz-utils. Install manually."
			pause
			return 1
		}
	fi

	download_naiveproxy || { pause; return 1; }

	if ! "$CADDY_BIN" list-modules 2>/dev/null | grep -q "http.handlers.forward_proxy"; then
		err "Downloaded caddy does not include the naive forward_proxy module."
		err "The asset may be mismatched. Try option 1 (build from source) instead."
		pause
		return 1
	fi

	pick_domain || { pause; return 1; }
	prompt_settings
	SECRET="$PROBE_DECOY"
	_do_install_common || { pause; return 1; }
	pause
}

do_update() {
	load_conf || { pause; return 1; }
	warn "This will rebuild caddy with xcaddy and restart the service."
	read -rp "Continue? [y/N]: " a
	case "$a" in y | Y) ;; *) return 0 ;; esac

	if ! command -v go >/dev/null 2>&1; then
		err "Go toolchain not found. Install Go first or use option 4."
		pause
		return 1
	fi

	build_caddy || { pause; return 1; }
	validate_caddyfile || { pause; return 1; }
	svc_restart
	ok "Caddy rebuilt and service restarted."
	pause
}

do_update_no_build() {
	load_conf || { pause; return 1; }
	warn "This will download the latest pre-built Caddy+forwardproxy binary and restart the service."
	read -rp "Continue? [y/N]: " a
	case "$a" in y | Y) ;; *) return 0 ;; esac

	svc_stop 2>/dev/null || true
	download_naiveproxy || {
		warn "Download failed. Attempting to restart with existing binary ..."
		svc_start 2>/dev/null || true
		pause
		return 1
	}
	if ! "$CADDY_BIN" list-modules 2>/dev/null | grep -q "http.handlers.forward_proxy"; then
		err "Downloaded caddy does not include forward_proxy. Not starting."
		pause
		return 1
	fi
	validate_caddyfile || { pause; return 1; }
	svc_start
	ok "Caddy updated and service restarted."
	pause
}

do_show() {
	show_link
	echo
	echo "Files:"
	printf '  service  : %s\n' "$SERVICE_FILE"
	printf '  caddy    : %s\n' "$CADDY_BIN"
	printf '  caddyfile: %s\n' "$caddy_path"
	printf '  certs    : %s\n' "$cert_dir"
	printf '  conf     : %s\n' "$conf_path"
	echo
	echo "Active Caddyfile:"
	sed 's/^/  /' "$caddy_path" 2>/dev/null || true
	pause
}

do_restart() {
	load_conf || { pause; return 1; }
	validate_caddyfile || { pause; return 1; }
	svc_restart
	ok "Restarted."
	pause
}

do_stop() {
	load_conf || { pause; return 1; }
	svc_stop
	ok "Stopped."
	pause
}

do_start() {
	load_conf || { pause; return 1; }
	validate_caddyfile || { pause; return 1; }
	svc_start
	ok "Started."
	pause
}

do_logs() {
	load_conf || { pause; return 1; }
	info "Following journal logs (Ctrl-C to exit) ..."
	journalctl -u "$SERVICE_NAME" -f --no-pager || true
	echo
	info "Caddy access log tail:"
	tail -n 80 "${log_dir}/access.log" 2>/dev/null || warn "No access log yet."
	pause
}

do_status() {
	load_conf || { pause; return 1; }
	svc_status
	echo
	info "Listening ports for caddy / common ports:"
	ss -lntup 2>/dev/null | grep -E 'caddy|:80|:443|:'"${PORT}" || true
	echo
	info "Cert expiry:"
	if command -v openssl >/dev/null 2>&1 && [ -s "${cert_dir}/fullchain.cer" ]; then
		openssl x509 -enddate -noout -in "${cert_dir}/fullchain.cer" 2>/dev/null || true
	else
		warn "No usable fullchain.cer in ${cert_dir} (run option 11 to repair)."
	fi
	echo
	info "Cert/key file sizes in ${cert_dir}:"
	ls -la "${cert_dir}/fullchain.cer" "${cert_dir}/private.key" 2>/dev/null || true
	if [ -s "${cert_dir}/fullchain.cer" ] && [ -s "${cert_dir}/private.key" ]; then
		if cert_key_match "${cert_dir}/fullchain.cer" "${cert_dir}/private.key"; then
			ok "Installed cert and private key match."
		else
			warn "Installed cert and private key do NOT match."
		fi
	fi
	echo
	info "Caddy modules:"
	"$CADDY_BIN" list-modules 2>/dev/null | grep -E 'http.handlers.forward_proxy|forward_proxy' || warn "forward_proxy module not found."
	echo
	info "acme.sh auto-renew hook for ${DOMAIN}:"
	if [ -n "$ACME_BIN" ]; then
		"$ACME_BIN" --info -d "$DOMAIN" ${ECC} 2>/dev/null | grep -E 'Le_Real|Le_ReloadCmd' || warn "No install-cert hook found (run option 11)."
		if crontab -l 2>/dev/null | grep -q acme.sh; then
			ok "acme.sh renewal cron is present."
		else
			warn "No acme.sh cron found -> run: ${ACME_BIN} --install-cronjob"
		fi
	fi
	pause
}

do_settings() {
	load_conf || { pause; return 1; }
	echo "Leave blank to keep current value."
	local old_domain="$DOMAIN" p a

	read -rp "Change domain? current [${DOMAIN}] [y/N]: " a
	case "$a" in y | Y) pick_domain || { pause; return 1; } ;; esac

	read -rp "Port [${PORT}]: " p
	PORT="${p:-$PORT}"
	while ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; do
		warn "Port must be 1-65535."
		read -rp "Port [${PORT}]: " p
		PORT="${p:-$PORT}"
	done
	read -rp "Username [${NAIVE_USER}]: " p
	NAIVE_USER="${p:-$NAIVE_USER}"
	read -rp "Password [${NAIVE_PASS}]: " p
	NAIVE_PASS="${p:-$NAIVE_PASS}"
	read -rp "Decoy/probe_resistance host [${SECRET}]: " p
	SECRET="${p:-$SECRET}"

	if [ "$DOMAIN" != "$old_domain" ]; then
		install_cert || { pause; return 1; }
	fi

	save_conf
	gen_caddyfile
	validate_caddyfile || { pause; return 1; }
	gen_service
	svc_restart
	ok "Settings applied."
	show_link
	pause
}

do_cert() {
	load_conf || { pause; return 1; }
	if [ -z "$ACME_BIN" ]; then
		err "acme.sh not found."
		pause
		return 1
	fi
	info "Repairing/reinstalling TLS cert for ${DOMAIN} ..."
	warn "If the private key is lost/zero-byte, this will offer a fresh re-issue."
	install_cert || { pause; return 1; }
	validate_caddyfile || { pause; return 1; }
	svc_restart
	ok "Cert installed and service restarted."
	pause
}

do_uninstall() {
	load_conf || { pause; return 1; }
	warn "This stops and disables the service, and removes ${naive_path}."
	read -rp "Type 'yes' to confirm: " a
	[ "$a" = "yes" ] || { info "Cancelled."; pause; return 0; }

	svc_stop 2>/dev/null || true
	systemctl disable "$SERVICE_NAME" 2>/dev/null || true
	rm -f "$SERVICE_FILE"
	systemctl daemon-reload
	rm -rf "$naive_path"
	ok "Removed. (acme.sh certificate and caddy binary are left intact.)"
	pause
}

# --------------------------------------------------------------------------- #
# Menu
# --------------------------------------------------------------------------- #
menu() {
	while :; do
		clear 2>/dev/null || true
		hr
		printf '  %sNaiveProxy Manager (systemctl)%s   (%s)\n' "$C_G" "$C_0" "$naive_path"
		hr
		if is_installed; then
			printf '  status: %sinstalled%s  domain: %s  port: %s\n' "$C_G" "$C_0" "$(. "$conf_path"; echo "$DOMAIN")" "$(. "$conf_path"; echo "$PORT")"
			if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
				printf '  service: %srunning%s\n' "$C_G" "$C_0"
			else
				printf '  service: %sstopped%s\n' "$C_R" "$C_0"
			fi
		else
			printf '  status: %snot installed%s\n' "$C_Y" "$C_0"
		fi
		hr
		cat <<MENU
  1) Install          (build caddy with xcaddy from source)
  2) Install no-build (download pre-built Caddy+forwardproxy binary)
  3) Update           (rebuild caddy with xcaddy & restart)
  4) Update no-build  (download latest pre-built binary & restart)
  5) Show config & connection info
  6) Restart
  7) Stop
  8) Start
  9) Logs (journal + access log)
 10) Change settings (domain/port/user/pass/decoy)
 11) Repair / reinstall TLS cert
 12) Status
 13) Uninstall
  0) Exit
MENU
		hr
		read -rp "Choose: " c
		case "$c" in
		1)  do_install          ;;
		2)  do_install_no_build ;;
		3)  do_update           ;;
		4)  do_update_no_build  ;;
		5)  do_show             ;;
		6)  do_restart          ;;
		7)  do_stop             ;;
		8)  do_start            ;;
		9)  do_logs             ;;
		10) do_settings         ;;
		11) do_cert             ;;
		12) do_status           ;;
		13) do_uninstall        ;;
		0)  exit 0              ;;
		*) warn "Invalid option."; sleep 1 ;;
		esac
	done
}

# --------------------------------------------------------------------------- #
main() {
	detect_root
	detect_acme
	menu
}
main "$@"
