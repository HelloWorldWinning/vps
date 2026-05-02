#!/bin/bash
# ============================================================
#  Apache2 + mod_dav WebDAV — Installer & Manager (combined)
#  Tested on: Debian 11 / 12 / 13 (Trixie)
#  Usage:
#    sudo bash webdav.sh install   — first-time setup
#    sudo bash webdav.sh           — management menu
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

WEBDAV_PATH="/data/WebDAV"
AUTH_FILE="/etc/apache2/webdav.htdigest"
SSL_DIR="/etc/apache2/ssl"
CONFIG_FILE="/etc/apache2/sites-available/webdav.conf"
STATE_FILE="/etc/apache2/webdav-install.conf"
ACME_HOME="/root/.acme.sh"

# ── helpers ──────────────────────────────────────────────────

print_banner() {
	echo -e "${CYAN}"
	echo "  ╔══════════════════════════════════════╗"
	echo "  ║     Apache2 + mod_dav  WebDAV        ║"
	echo "  ║      Installer & Manager v3.0        ║"
	echo "  ╚══════════════════════════════════════╝"
	echo -e "${NC}"
}

ask() {
	local MSG="$1" DEFAULT="$2" TIMEOUT="$3" SECRET="${4:-}"
	REPLY_VAL=""
	if [ "$SECRET" = "secret" ]; then
		echo -ne "${YELLOW}${MSG}${NC} (${TIMEOUT}s, default: ${BOLD}${DEFAULT}${NC}): "
		read -t "$TIMEOUT" -s REPLY_VAL || true
		echo ""
	else
		echo -ne "${YELLOW}${MSG}${NC} (${TIMEOUT}s, default: ${BOLD}${DEFAULT}${NC}): "
		read -t "$TIMEOUT" REPLY_VAL || true
		echo ""
	fi
	REPLY_VAL="${REPLY_VAL:-$DEFAULT}"
}

ask_yn() {
	local MSG="$1" DEFAULT="$2" TIMEOUT="$3"
	local _R
	echo -ne "${YELLOW}${MSG}${NC} [Y/n] (${TIMEOUT}s, default: ${BOLD}${DEFAULT}${NC}): "
	read -t "$TIMEOUT" _R || true
	echo ""
	_R="${_R:-$DEFAULT}"
	[[ "$_R" =~ ^[Yy]$ ]]
}

get_public_ip() {
	curl -s --max-time 8 https://api.ipify.org 2>/dev/null ||
		curl -s --max-time 8 https://ifconfig.me 2>/dev/null ||
		echo ""
}

write_htdigest() {
	local USER="$1" REALM="$2" PASS="$3" FILE="$4"
	local HASH
	HASH=$(printf '%s' "${USER}:${REALM}:${PASS}" | md5sum | awk '{print $1}')
	echo "${USER}:${REALM}:${HASH}" >"$FILE"
	chown root:www-data "$FILE"
	chmod 640 "$FILE"
}

load_state() {
	if [ -f "$STATE_FILE" ]; then
		# shellcheck disable=SC1090
		source "$STATE_FILE"
		# backward compat: old state files lack TLS_MODE / ACME_DOMAIN
		if [ -z "${TLS_MODE:-}" ]; then
			if [ "${USE_TLS:-false}" = true ]; then
				TLS_MODE="selfsigned"
			else
				TLS_MODE="none"
			fi
		fi
		ACME_DOMAIN="${ACME_DOMAIN:-}"
	else
		echo -e "${RED}State file not found. Run:  sudo bash webdav.sh install${NC}"
		exit 1
	fi
}

# ── Rebuild ports.conf from scratch ──────────────────────────
# Only the WebDAV port — nothing else.
rebuild_ports_conf() {
	local PORT="$1"
	local PORTS_CONF="/etc/apache2/ports.conf"

	cp -f "$PORTS_CONF" "${PORTS_CONF}.bak" 2>/dev/null || true

	cat >"$PORTS_CONF" <<EOF
# ports.conf — managed by webdav.sh
Listen ${PORT}
EOF

	echo -e "  → ports.conf rebuilt (Listen ${PORT} only)"
}

# ── write vhost ──────────────────────────────────────────────
write_vhost() {
	local PROTO_TLS="$1" # true / false

	if [ "$PROTO_TLS" = true ]; then
		cat >"$CONFIG_FILE" <<EOF
<VirtualHost *:${APACHE_PORT}>
    ServerName ${SERVER_NAME}

    SSLEngine on
    SSLCertificateFile    ${SSL_DIR}/webdav.crt
    SSLCertificateKeyFile ${SSL_DIR}/webdav.key

    Alias /webdav ${WEBDAV_PATH}

    <Directory ${WEBDAV_PATH}>
        DAV On
        AuthType Digest
        AuthName "webdav"
        AuthUserFile ${AUTH_FILE}
        Require valid-user
	Options Indexes FollowSymLinks
    </Directory>

    DavLockDB /var/lock/apache2/DavLock

    ErrorLog  \${APACHE_LOG_DIR}/webdav_error.log
    CustomLog \${APACHE_LOG_DIR}/webdav_access.log combined
</VirtualHost>
EOF
	else
		cat >"$CONFIG_FILE" <<EOF
<VirtualHost *:${APACHE_PORT}>
    ServerName ${SERVER_NAME}

    Alias /webdav ${WEBDAV_PATH}

    <Directory ${WEBDAV_PATH}>
        DAV On
        AuthType Digest
        AuthName "webdav"
        AuthUserFile ${AUTH_FILE}
        Require valid-user
	Options Indexes FollowSymLinks
    </Directory>

    DavLockDB /var/lock/apache2/DavLock

    ErrorLog  \${APACHE_LOG_DIR}/webdav_error.log
    CustomLog \${APACHE_LOG_DIR}/webdav_access.log combined
</VirtualHost>
EOF
	fi
}

# ── save state ───────────────────────────────────────────────
save_state() {
	cat >"$STATE_FILE" <<EOF
WEBDAV_USER="${WEBDAV_USER}"
SERVER_NAME="${SERVER_NAME}"
APACHE_PORT="${APACHE_PORT}"
USE_TLS="${USE_TLS}"
TLS_MODE="${TLS_MODE}"
ACME_DOMAIN="${ACME_DOMAIN:-}"
WEBDAV_PATH="${WEBDAV_PATH}"
AUTH_FILE="${AUTH_FILE}"
SSL_DIR="${SSL_DIR}"
EOF
}

# ── install acme.sh if missing ───────────────────────────────
ensure_acme_sh() {
	if [ -f "$ACME_HOME/acme.sh" ]; then
		echo -e "  → acme.sh already installed at ${ACME_HOME}"
		return 0
	fi
	echo -e "  → Installing acme.sh (manual extract)..."
	local TMPDIR
	TMPDIR=$(mktemp -d)
	curl -sS -L https://github.com/acmesh-official/acme.sh/archive/master.tar.gz \
		-o "$TMPDIR/acme.tar.gz"
	tar xzf "$TMPDIR/acme.tar.gz" -C "$TMPDIR"
	cd "$TMPDIR/acme.sh-master"
	bash ./acme.sh --install --home "$ACME_HOME" --no-cron 2>/dev/null
	cd /
	rm -rf "$TMPDIR"
	if [ ! -f "$ACME_HOME/acme.sh" ]; then
		echo -e "${RED}Failed to install acme.sh. Aborting.${NC}"
		return 1
	fi
	"$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt 2>/dev/null || true
	echo -e "  → ${GREEN}acme.sh installed.${NC}"
}

# ═════════════════════════════════════════════════════════════
#  INSTALL
# ═════════════════════════════════════════════════════════════
do_install() {
	print_banner

	# ── Cleanup from any previous install ────────────────────
	if [ -f "$STATE_FILE" ] || [ -f "$CONFIG_FILE" ]; then
		echo -e "${YELLOW}── Previous install detected — cleaning up ─────${NC}"
		# load old port so we can remove its Listen line
		local OLD_PORT=""
		if [ -f "$STATE_FILE" ]; then
			OLD_PORT=$(grep '^APACHE_PORT=' "$STATE_FILE" 2>/dev/null |
				cut -d'"' -f2 || true)
		fi
		# disable old site (ignore errors)
		a2dissite webdav.conf 2>/dev/null || true
		# stop apache so port is released
		systemctl stop apache2 2>/dev/null || true
		# back up & remove old configs (data dir is untouched)
		for F in "$CONFIG_FILE" "$STATE_FILE" "$AUTH_FILE"; do
			[ -f "$F" ] && mv -f "$F" "${F}.bak" &&
				echo -e "  → ${F} → .bak"
		done
		# remove old port from ports.conf if known
		if [ -n "$OLD_PORT" ]; then
			sed -i "/^[[:space:]]*Listen[[:space:]]\+${OLD_PORT}\b/d" \
				/etc/apache2/ports.conf 2>/dev/null || true
		fi
		# strip blank / carriage-return / malformed lines
		sed -i '/^[[:space:]]*$/d; s/\r$//' /etc/apache2/ports.conf 2>/dev/null || true
		echo -e "  → ${GREEN}Cleanup done. Data in ${WEBDAV_PATH} preserved.${NC}"
		echo ""
	fi

	echo -e "${CYAN}── Step 1/7 : Username ─────────────────────────${NC}"
	ask "WebDAV username" "WebDAV" 5
	WEBDAV_USER="$REPLY_VAL"
	echo -e "  → User: ${GREEN}${WEBDAV_USER}${NC}"

	echo ""
	echo -e "${CYAN}── Step 2/7 : Password ─────────────────────────${NC}"
	ask "WebDAV password" "WebDAV_password" 10 secret
	WEBDAV_PASS="$REPLY_VAL"
	echo -e "  → Password set."

	echo ""
	echo -e "${CYAN}── Step 3/7 : Server Name / IP ─────────────────${NC}"
	echo -ne "${YELLOW}Detecting public IP...${NC} "
	PUBLIC_IP=$(get_public_ip)
	if [ -n "$PUBLIC_IP" ]; then
		echo -e "${GREEN}${PUBLIC_IP}${NC}"
		DEFAULT_SERVER="$PUBLIC_IP"
	else
		echo -e "${RED}Could not detect.${NC}"
		DEFAULT_SERVER="127.0.0.1"
	fi
	ask "Server name or IP" "$DEFAULT_SERVER" 10
	SERVER_NAME="$REPLY_VAL"
	echo -e "  → Server: ${GREEN}${SERVER_NAME}${NC}"

	echo ""
	echo -e "${CYAN}── Step 4/7 : Port ─────────────────────────────${NC}"
	ask "WebDAV port" "9443" 5
	APACHE_PORT="$REPLY_VAL"
	echo -e "  → Port: ${GREEN}${APACHE_PORT}${NC}"

	echo ""
	echo -e "${CYAN}── Step 5/7 : TLS Certificate ──────────────────${NC}"
	echo ""
	echo -e "  ${CYAN}[1]${NC}  Self-signed certificate          (HTTPS)"
	echo -e "  ${CYAN}[2]${NC}  acme.sh / Let's Encrypt          (HTTPS, needs domain + port 80)"
	echo -e "  ${CYAN}[3]${NC}  No TLS                           (plain HTTP)"
	echo ""
	ask "Choose [1/2/3]" "1" 15
	local TLS_CHOICE="$REPLY_VAL"

	ACME_DOMAIN=""

	case "$TLS_CHOICE" in
	2)
		USE_TLS=true
		TLS_MODE="acme"
		echo ""
		ask "Domain name for Let's Encrypt certificate" "$SERVER_NAME" 15
		ACME_DOMAIN="$REPLY_VAL"
		SERVER_NAME="$ACME_DOMAIN"
		echo -e "  → ${GREEN}acme.sh / Let's Encrypt for ${ACME_DOMAIN}${NC}"
		;;
	3)
		USE_TLS=false
		TLS_MODE="none"
		echo -e "  → ${YELLOW}TLS disabled (plain HTTP)${NC}"
		;;
	*)
		USE_TLS=true
		TLS_MODE="selfsigned"
		echo -e "  → ${GREEN}TLS enabled (Self-signed)${NC}"
		;;
	esac

	echo ""
	echo -e "${CYAN}── Step 6/7 : Installing packages ──────────────${NC}"
	apt-get update -qq
	apt-get install -y apache2 apache2-utils openssl curl
	# socat is needed by acme.sh standalone mode
	[ "$TLS_MODE" = "acme" ] && apt-get install -y socat

	echo ""
	echo -e "${CYAN}── Step 7/7 : Configuring Apache2 + mod_dav ───${NC}"

	a2enmod dav dav_fs auth_digest alias
	[ "$USE_TLS" = true ] && a2enmod ssl

	mkdir -p "$WEBDAV_PATH"
	chown -R www-data:www-data "$WEBDAV_PATH"
	chmod 755 "$WEBDAV_PATH"

	mkdir -p /var/lock/apache2
	chown www-data:www-data /var/lock/apache2

	echo -e "  → Writing credentials..."
	write_htdigest "$WEBDAV_USER" "webdav" "$WEBDAV_PASS" "$AUTH_FILE"
	echo -e "  → ${GREEN}Done.${NC}"

	mkdir -p "$SSL_DIR"

	if [ "$TLS_MODE" = "selfsigned" ]; then
		openssl req -x509 -newkey rsa:4096 -days 36500 -nodes \
			-keyout "$SSL_DIR/webdav.key" \
			-out "$SSL_DIR/webdav.crt" \
			-subj "/CN=${SERVER_NAME}" \
			2>/dev/null
		chmod 600 "$SSL_DIR/webdav.key"
		echo -e "  → ${GREEN}Self-signed cert generated (36500 days)${NC}"
	fi

	if [ "$TLS_MODE" = "acme" ]; then
		echo -e "  → ${CYAN}Issuing Let's Encrypt certificate via acme.sh...${NC}"

		ensure_acme_sh || exit 1

		# Issue certificate using standalone mode (port 80)
		if "$ACME_HOME/acme.sh" --issue -d "$ACME_DOMAIN" \
			--standalone --keylength ec-256 --force; then

			# Install cert + key into Apache SSL dir

			# Install cert + key into Apache SSL dir
			# Skip reloadcmd during install — vhost not written yet.
			# acme.sh stores reloadcmd for future renewals.
			"$ACME_HOME/acme.sh" --install-cert -d "$ACME_DOMAIN" --ecc \
				--fullchain-file "$SSL_DIR/webdav.crt" \
				--key-file "$SSL_DIR/webdav.key" \
				--reloadcmd "systemctl reload apache2" \
				2>/dev/null || true

			chmod 600 "$SSL_DIR/webdav.key"
			echo -e "  → ${GREEN}Let's Encrypt cert issued & installed for ${ACME_DOMAIN}${NC}"
			echo -e "  → ${GREEN}Auto-renewal handled by acme.sh cron job${NC}"
		else
			echo -e "${RED}acme.sh certificate issuance failed!${NC}"
			echo -e "${YELLOW}Possible causes:${NC}"
			echo -e "  • Domain DNS does not point to this server"
			echo -e "  • Port 80 is blocked by firewall"
			echo -e "  • Rate limit hit"
			echo ""
			echo -e "${YELLOW}Falling back to self-signed certificate...${NC}"
			TLS_MODE="selfsigned"
			ACME_DOMAIN=""
			openssl req -x509 -newkey rsa:4096 -days 36500 -nodes \
				-keyout "$SSL_DIR/webdav.key" \
				-out "$SSL_DIR/webdav.crt" \
				-subj "/CN=${SERVER_NAME}" \
				2>/dev/null
			chmod 600 "$SSL_DIR/webdav.key"
			echo -e "  → ${YELLOW}Self-signed cert generated as fallback (36500 days)${NC}"
		fi
	fi

	write_vhost "$USE_TLS"

	# ── ports.conf: clean + add ──
	rebuild_ports_conf "$APACHE_PORT"

	a2ensite webdav.conf
	a2dissite 000-default.conf 2>/dev/null || true

	echo -e "  → Testing Apache config..."
	if ! apache2ctl configtest 2>&1; then
		echo -e "${RED}Config test failed — see errors above. Aborting.${NC}"
		exit 1
	fi

	systemctl restart apache2
	systemctl enable apache2

	save_state

	echo ""
	local PROTO="http"
	[ "$USE_TLS" = true ] && PROTO="https"
	echo -e "${GREEN}${BOLD}═══════════════════════════════════════════${NC}"
	echo -e "${GREEN}${BOLD}  WebDAV Ready!${NC}"
	echo -e "${GREEN}${BOLD}═══════════════════════════════════════════${NC}"
	echo -e "  URL      : ${CYAN}${PROTO}://${SERVER_NAME}:${APACHE_PORT}/webdav${NC}"
	echo -e "  User     : ${CYAN}${WEBDAV_USER}${NC}"
	echo -e "  Data     : ${CYAN}${WEBDAV_PATH}${NC}"
	echo -e "  TLS      : ${CYAN}${USE_TLS} (${TLS_MODE})${NC}"
	[ "$USE_TLS" = true ] &&
		echo -e "  Cert     : ${CYAN}${SSL_DIR}/webdav.crt${NC}"
	[ "$TLS_MODE" = "selfsigned" ] &&
		echo -e "  Cert type: ${CYAN}self-signed, 36500 days${NC}"
	[ "$TLS_MODE" = "acme" ] &&
		echo -e "  Cert type: ${CYAN}Let's Encrypt via acme.sh (auto-renew)${NC}"
	echo -e "${GREEN}${BOLD}═══════════════════════════════════════════${NC}"
	echo ""
	echo -e "  ${BOLD}Migration (run on vps1):${NC}"
	echo -e "  ${CYAN}rsync -avz --progress /data/WebDAV/ root@<vps2>:/data/WebDAV/${NC}"
	echo ""
	echo -e "  ${BOLD}Manager:${NC}"
	echo -e "  ${CYAN}sudo bash webdav.sh${NC}"
	echo ""
}

# ═════════════════════════════════════════════════════════════
#  MANAGER FUNCTIONS
# ═════════════════════════════════════════════════════════════

show_status() {
	load_state
	local PROTO="http"
	[ "$USE_TLS" = true ] && PROTO="https"
	local APACHE_STATE
	APACHE_STATE=$(systemctl is-active apache2 2>/dev/null || echo "unknown")

	echo -e "${BOLD}═══════════════════════════════════════════${NC}"
	echo -e "${BOLD}  Current WebDAV Status${NC}"
	echo -e "${BOLD}═══════════════════════════════════════════${NC}"

	if [ "$APACHE_STATE" = "active" ]; then
		echo -e "  Apache2  : ${GREEN}running ✓${NC}"
	else
		echo -e "  Apache2  : ${RED}${APACHE_STATE} ✗${NC}"
	fi

	echo -e "  URL      : ${CYAN}${PROTO}://${SERVER_NAME}:${APACHE_PORT}/webdav${NC}"
	echo -e "  User     : ${CYAN}${WEBDAV_USER}${NC}"
	echo -e "  Data     : ${CYAN}${WEBDAV_PATH}${NC}"
	echo -e "  Port     : ${CYAN}${APACHE_PORT}${NC}"
	echo -e "  TLS      : ${CYAN}${USE_TLS} (${TLS_MODE})${NC}"

	if [ "$USE_TLS" = true ] && [ -f "$SSL_DIR/webdav.crt" ]; then
		local EXPIRY CN
		EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_DIR/webdav.crt" | cut -d= -f2)
		CN=$(openssl x509 -subject -noout -in "$SSL_DIR/webdav.crt" |
			sed 's/.*CN\s*=\s*//' | sed 's/,.*//')
		echo -e "  Cert CN  : ${CYAN}${CN}${NC}"
		echo -e "  Cert Exp : ${CYAN}${EXPIRY}${NC}"
	fi

	local COUNT SIZE
	COUNT=$(find "$WEBDAV_PATH" -type f 2>/dev/null | wc -l)
	SIZE=$(du -sh "$WEBDAV_PATH" 2>/dev/null | cut -f1)
	echo -e "  Files    : ${CYAN}${COUNT} files, ${SIZE} total${NC}"
	echo -e "${BOLD}═══════════════════════════════════════════${NC}"
}

do_start() { systemctl start apache2 && echo -e "${GREEN}Apache2 started.${NC}"; }
do_stop() { systemctl stop apache2 && echo -e "${YELLOW}Apache2 stopped.${NC}"; }
do_restart() { systemctl restart apache2 && echo -e "${GREEN}Apache2 restarted.${NC}"; }
do_reload() {
	if apache2ctl configtest 2>&1; then
		systemctl reload apache2
		echo -e "${GREEN}Apache2 reloaded (no downtime).${NC}"
	else
		echo -e "${RED}Config test failed — reload aborted.${NC}"
	fi
}

do_logs() {
	echo -e "${CYAN}── Error Log (last 30 lines) ───────────────${NC}"
	tail -30 /var/log/apache2/webdav_error.log 2>/dev/null || echo "(empty)"
	echo ""
	echo -e "${CYAN}── Access Log (last 30 lines) ──────────────${NC}"
	tail -30 /var/log/apache2/webdav_access.log 2>/dev/null || echo "(empty)"
}

do_regen_tls() {
	load_state
	if [ "$USE_TLS" != true ]; then
		echo -e "${RED}TLS was not enabled. Re-run:  sudo bash webdav.sh install  and choose TLS.${NC}"
		return
	fi

	if [ "$TLS_MODE" = "acme" ]; then
		# ── acme.sh renewal / re-issue ──
		echo ""
		ask "Domain to re-issue" "${ACME_DOMAIN:-$SERVER_NAME}" 10
		local NEW_DOMAIN="$REPLY_VAL"

		if [ ! -f "$ACME_HOME/acme.sh" ]; then
			echo -e "${RED}acme.sh not found at ${ACME_HOME}. Re-run install with acme option.${NC}"
			return
		fi

		echo -e "  → Re-issuing certificate for ${NEW_DOMAIN}..."
		if "$ACME_HOME/acme.sh" --issue -d "$NEW_DOMAIN" \
			--standalone --keylength ec-256 --force; then

			"$ACME_HOME/acme.sh" --install-cert -d "$NEW_DOMAIN" --ecc \
				--fullchain-file "$SSL_DIR/webdav.crt" \
				--key-file "$SSL_DIR/webdav.key" \
				--reloadcmd "systemctl reload apache2" \
				2>/dev/null

			chmod 600 "$SSL_DIR/webdav.key"

			if [ "$NEW_DOMAIN" != "$SERVER_NAME" ]; then
				SERVER_NAME="$NEW_DOMAIN"
				ACME_DOMAIN="$NEW_DOMAIN"
				save_state
				sed -i "s|ServerName .*|ServerName ${NEW_DOMAIN}|" "$CONFIG_FILE"
			fi

			systemctl reload apache2
			local EXPIRY
			EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_DIR/webdav.crt" | cut -d= -f2)
			echo -e "  ${GREEN}New acme.sh cert for ${NEW_DOMAIN} — expires: ${EXPIRY}${NC}"
		else
			echo -e "${RED}acme.sh re-issue failed. Check domain DNS and port 80.${NC}"
		fi
	else
		# ── self-signed regeneration (original behavior) ──
		echo ""
		ask "New CN (IP or domain)" "$SERVER_NAME" 10
		local NEW_CN="$REPLY_VAL"

		mkdir -p "$SSL_DIR"
		openssl req -x509 -newkey rsa:4096 -days 36500 -nodes \
			-keyout "$SSL_DIR/webdav.key" \
			-out "$SSL_DIR/webdav.crt" \
			-subj "/CN=${NEW_CN}" \
			2>/dev/null
		chmod 600 "$SSL_DIR/webdav.key"

		if [ "$NEW_CN" != "$SERVER_NAME" ]; then
			SERVER_NAME="$NEW_CN"
			save_state
			sed -i "s|ServerName .*|ServerName ${NEW_CN}|" "$CONFIG_FILE"
		fi

		systemctl reload apache2
		local EXPIRY
		EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_DIR/webdav.crt" | cut -d= -f2)
		echo -e "  ${GREEN}New cert for ${NEW_CN} — expires: ${EXPIRY}${NC}"
	fi
}

do_change_credentials() {
	load_state
	echo ""
	ask "New username" "$WEBDAV_USER" 5
	local NEW_USER="$REPLY_VAL"

	ask "New password" "" 10 secret
	local NEW_PASS="$REPLY_VAL"

	if [ -z "$NEW_PASS" ]; then
		echo -e "${RED}No password entered. Aborted.${NC}"
		return
	fi

	write_htdigest "$NEW_USER" "webdav" "$NEW_PASS" "$AUTH_FILE"
	WEBDAV_USER="$NEW_USER"
	save_state
	systemctl reload apache2
	echo -e "  ${GREEN}Credentials updated. User: ${NEW_USER}${NC}"
}

do_change_port() {
	load_state
	echo ""
	ask "New port" "$APACHE_PORT" 10
	local NEW_PORT="$REPLY_VAL"

	if [ "$NEW_PORT" = "$APACHE_PORT" ]; then
		echo -e "${YELLOW}Port unchanged.${NC}"
		return
	fi

	local OLD_PORT="$APACHE_PORT"
	APACHE_PORT="$NEW_PORT"

	# Rewrite ports.conf with new port only
	rebuild_ports_conf "$APACHE_PORT"

	# Rewrite vhost with new port
	write_vhost "$USE_TLS"
	save_state

	if apache2ctl configtest 2>&1; then
		systemctl restart apache2
		echo -e "  ${GREEN}Port changed: ${OLD_PORT} → ${APACHE_PORT}${NC}"
	else
		echo -e "${RED}Config test failed after port change!${NC}"
	fi
}

do_upgrade_letsencrypt() {
	load_state
	echo ""
	echo -e "${YELLOW}Requirements:${NC}"
	echo -e "  • A real domain (A/AAAA record) pointing to this server's IP"
	echo -e "  • Port 80 must be reachable from the internet (one-time HTTP-01 challenge)"
	echo ""

	# Check if port 80 is occupied by something other than apache2
	local PORT80_PID
	PORT80_PID=$(ss -tlnp 'sport = :80' 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1)
	if [ -n "$PORT80_PID" ]; then
		local PORT80_NAME
		PORT80_NAME=$(ps -p "$PORT80_PID" -o comm= 2>/dev/null || echo "unknown")
		if [ "$PORT80_NAME" = "apache2" ]; then
			echo -e "${GREEN}Port 80 held by Apache — will be stopped for standalone challenge. ✓${NC}"
		else
			echo -e "${RED}Port 80 is occupied by '${PORT80_NAME}' (PID ${PORT80_PID}).${NC}"
			echo -e "${YELLOW}Stop that service first, then retry.${NC}"
			return
		fi
	else
		echo -e "${GREEN}Port 80 is free. ✓${NC}"
	fi

	ask "Domain name" "$SERVER_NAME" 10
	local DOMAIN="$REPLY_VAL"

	apt-get install -y certbot

	# Stop Apache so certbot standalone can bind port 80
	echo -e "  → Stopping Apache for standalone challenge..."
	systemctl stop apache2 2>/dev/null || true

	echo ""
	echo -e "${CYAN}Running certbot standalone...${NC}"
	if certbot certonly --standalone -d "$DOMAIN" \
		--non-interactive --agree-tos --register-unsafely-without-email; then

		# Point vhost at the Let's Encrypt cert
		local LE_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
		local LE_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

		SERVER_NAME="$DOMAIN"
		USE_TLS=true
		TLS_MODE="certbot"
		save_state

		# Rewrite vhost with LE paths
		cat >"$CONFIG_FILE" <<EOF
<VirtualHost *:${APACHE_PORT}>
    ServerName ${SERVER_NAME}

    SSLEngine on
    SSLCertificateFile    ${LE_CERT}
    SSLCertificateKeyFile ${LE_KEY}

    Alias /webdav ${WEBDAV_PATH}

    <Directory ${WEBDAV_PATH}>
        DAV On
        AuthType Digest
        AuthName "webdav"
        AuthUserFile ${AUTH_FILE}
        Require valid-user
	Options Indexes FollowSymLinks
    </Directory>

    DavLockDB /var/lock/apache2/DavLock

    ErrorLog  \${APACHE_LOG_DIR}/webdav_error.log
    CustomLog \${APACHE_LOG_DIR}/webdav_access.log combined
</VirtualHost>
EOF
		echo -e "  ${GREEN}Let's Encrypt cert installed for ${DOMAIN}.${NC}"
		echo -e "  ${GREEN}Auto-renewal via systemd timer (certbot renew).${NC}"
	else
		echo -e "${RED}Certbot failed. Check domain DNS and firewall (port 80).${NC}"
	fi

	# Restart Apache (port 80 is NOT in ports.conf — never was)
	systemctl start apache2
}

do_migration_cmd() {
	load_state
	echo ""
	echo -e "${BOLD}── One-line migration ──────────────────────${NC}"
	echo -e "${CYAN}  rsync -avz --progress ${WEBDAV_PATH}/ root@<vps2-ip>:${WEBDAV_PATH}/${NC}"
	echo ""
	echo -e "${BOLD}── After rsync on vps2 ─────────────────────${NC}"
	echo -e "${CYAN}  chown -R www-data:www-data ${WEBDAV_PATH}${NC}"
	echo ""
	echo -e "${YELLOW}  Apache config & TLS handled by 'bash webdav.sh install' on vps2.${NC}"
	echo -e "${YELLOW}  Only ${WEBDAV_PATH}/ needs rsyncing.${NC}"
}

do_reinstall() {
	echo -e "${YELLOW}Re-running install (your data in ${WEBDAV_PATH} is preserved)...${NC}"
	echo ""
	do_install
}

# ═════════════════════════════════════════════════════════════
#  MANAGEMENT MENU
# ═════════════════════════════════════════════════════════════

main_menu() {
	while true; do
		clear
		print_banner
		show_status
		echo ""
		echo -e "${BOLD}  Options:${NC}"
		echo ""
		echo -e "  ${CYAN}[1]${NC}  Start Apache2"
		echo -e "  ${CYAN}[2]${NC}  Stop Apache2"
		echo -e "  ${CYAN}[3]${NC}  Restart Apache2"
		echo -e "  ${CYAN}[4]${NC}  Reload Apache2        (no downtime)"
		echo -e "  ${CYAN}[5]${NC}  View logs"
		echo -e "  ${CYAN}[6]${NC}  Regenerate TLS cert   (self-signed / acme.sh)"
		echo -e "  ${CYAN}[7]${NC}  Change username / password"
		echo -e "  ${CYAN}[8]${NC}  Change port"
		echo -e "  ${CYAN}[9]${NC}  Upgrade to Let's Encrypt (certbot)"
		echo -e "  ${CYAN}[m]${NC}  Show migration rsync command"
		echo -e "  ${CYAN}[r]${NC}  Re-install (keeps data)"
		echo -e "  ${CYAN}[0]${NC}  Exit"
		echo ""
		echo -ne "  ${YELLOW}Choice:${NC} "
		read -t 60 CHOICE || {
			echo ""
			break
		}
		echo ""

		case "$CHOICE" in
		1) do_start ;;
		2) do_stop ;;
		3) do_restart ;;
		4) do_reload ;;
		5) do_logs ;;
		6) do_regen_tls ;;
		7) do_change_credentials ;;
		8) do_change_port ;;
		9) do_upgrade_letsencrypt ;;
		m | M) do_migration_cmd ;;
		r | R) do_reinstall ;;
		0)
			echo -e "${GREEN}Bye!${NC}"
			exit 0
			;;
		*) echo -e "${RED}Invalid choice.${NC}" ;;
		esac

		echo ""
		echo -ne "${YELLOW}Press Enter to return to menu...${NC}"
		read -t 30 || true
	done
}

# ═════════════════════════════════════════════════════════════
#  ENTRYPOINT
# ═════════════════════════════════════════════════════════════

if [ "$(id -u)" -ne 0 ]; then
	echo -e "${RED}Run as root:  sudo bash $0 [install]${NC}"
	exit 1
fi

case "${1:-}" in
install)
	do_install
	;;
"")
	if [ ! -f "$STATE_FILE" ]; then
		echo -e "${YELLOW}No existing install found. Starting installer...${NC}"
		echo ""
		do_install
	else
		main_menu
	fi
	;;
*)
	echo "Usage:  sudo bash $0 [install]"
	echo "  install  — run the installer"
	echo "  (none)   — open the management menu"
	exit 1
	;;
esac
