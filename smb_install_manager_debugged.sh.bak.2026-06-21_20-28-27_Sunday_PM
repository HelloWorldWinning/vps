#!/usr/bin/env bash
#
#  smb_install_manager.sh
#  ──────────────────────────────────────────────────────────
#  Samba (SMB/CIFS) installer & manager for Debian/Ubuntu VPS
#
#  Defaults:
#     Data : /data/SMB_d
#     Port : 9553
#     User : SMB
#     Pass : SMB_password   (CHANGE THIS — option [7])
#     Share: smb
#
#  Notes:
#     - Custom SMB ports work with Linux/macOS clients.
#     - Windows' built-in SMB client normally requires TCP/445.
#     - This version fixes false "not listening" status caused by
#       set -o pipefail + `ss | grep -q`.
#  ──────────────────────────────────────────────────────────

set -Eeuo pipefail

# ───────────────────────── Defaults ──────────────────────────
SMB_DATA_DEFAULT="/data/SMB_d"
SMB_PORT_DEFAULT="9553"
SMB_USER_DEFAULT="SMB"
SMB_PASS_DEFAULT="SMB_password"
SMB_SHARE_DEFAULT="smb"
SMB_EXTRA_PORTS_DEFAULT=""

SMB_CONF="/etc/samba/smb.conf"
SMB_STATE="/etc/samba/.smb_manager.state"

# ───────────────────────── Colours ───────────────────────────
if [[ -t 1 ]]; then
	C_OK=$'\e[32m'
	C_BAD=$'\e[31m'
	C_WARN=$'\e[33m'
	C_DIM=$'\e[2m'
	C_BOLD=$'\e[1m'
	C_RST=$'\e[0m'
else
	C_OK=""
	C_BAD=""
	C_WARN=""
	C_DIM=""
	C_BOLD=""
	C_RST=""
fi

ok() { echo "${C_OK}$*${C_RST}"; }
bad() { echo "${C_BAD}$*${C_RST}"; }
warn() { echo "${C_WARN}$*${C_RST}"; }
dim() { echo "${C_DIM}$*${C_RST}"; }
die() {
	bad "ERROR: $*"
	exit 1
}

# ───────────────────── Root requirement ──────────────────────
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
	die "Run as root: sudo bash $0"
fi

# ───────────────────── Current state values ──────────────────
SMB_DATA="$SMB_DATA_DEFAULT"
SMB_PORT="$SMB_PORT_DEFAULT"
SMB_USER="$SMB_USER_DEFAULT"
SMB_SHARE="$SMB_SHARE_DEFAULT"
SMB_EXTRA_PORTS="$SMB_EXTRA_PORTS_DEFAULT"

# shellcheck disable=SC1090
[[ -f "$SMB_STATE" ]] && source "$SMB_STATE"

# Backward compatibility with older state files that do not define SMB_EXTRA_PORTS.
SMB_EXTRA_PORTS="${SMB_EXTRA_PORTS:-}"

# ───────────────────────── Validation ────────────────────────
valid_port() {
	local p="${1:-}"
	[[ "$p" =~ ^[0-9]+$ ]] || return 1
	((p >= 1 && p <= 65535)) || return 1
}

valid_username() {
	local u="${1:-}"
	[[ "$u" =~ ^[A-Za-z_][A-Za-z0-9_.-]*[$]?$ ]] || return 1
}

valid_share_name() {
	local s="${1:-}"
	[[ "$s" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
}

validate_state_or_die() {
	valid_port "$SMB_PORT" || die "Invalid SMB_PORT in state/defaults: $SMB_PORT"
	valid_username "$SMB_USER" || die "Invalid SMB_USER in state/defaults: $SMB_USER"
	valid_share_name "$SMB_SHARE" || die "Invalid SMB_SHARE in state/defaults: $SMB_SHARE"
	[[ -n "$SMB_DATA" && "$SMB_DATA" == /* ]] || die "SMB_DATA must be an absolute path: $SMB_DATA"

	local p
	for p in $SMB_EXTRA_PORTS; do
		valid_port "$p" || die "Invalid extra SMB port in state: $p"
	done
}

validate_state_or_die

save_state() {
	umask 077
	cat >"$SMB_STATE" <<EOF_STATE
SMB_DATA="$SMB_DATA"
SMB_PORT="$SMB_PORT"
SMB_USER="$SMB_USER"
SMB_SHARE="$SMB_SHARE"
SMB_EXTRA_PORTS="$SMB_EXTRA_PORTS"
EOF_STATE
	chmod 600 "$SMB_STATE"
}

# ───────────────────────── Helpers ───────────────────────────
detect_ip() {
	local ip
	ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')
	[[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
	[[ -z "$ip" ]] && ip="<server-ip>"
	echo "$ip"
}

is_installed() {
	command -v smbd >/dev/null 2>&1 && dpkg -s samba >/dev/null 2>&1
}

smbd_running() {
	systemctl is-active --quiet smbd 2>/dev/null
}

nmbd_unit_exists() {
	systemctl list-unit-files nmbd.service >/dev/null 2>&1
}

config_exists() {
	[[ -f "$SMB_CONF" ]] && grep -Fqx "[$SMB_SHARE]" "$SMB_CONF" 2>/dev/null
}

unique_ports() {
	local seen=" " out="" p
	for p in "$SMB_PORT" $SMB_EXTRA_PORTS; do
		[[ -z "$p" ]] && continue
		case "$seen" in
			*" $p "*) ;;
			*)
				seen+="$p "
				out+="${out:+ }$p"
				;;
		esac
	done
	echo "$out"
}

# Robust listener check.
# Do NOT use: ss ... | grep -q ... while set -o pipefail is enabled.
# grep -q can exit early after a match, causing ss to receive SIGPIPE and
# making the pipeline fail even though the port exists.
port_listening() {
	local port="${1:-$SMB_PORT}"
	local out
	valid_port "$port" || return 1

	out=$(ss -H -ltn 2>/dev/null || true)
	awk -v want=":$port" '
		{
			for (i = 1; i <= NF; i++) {
				# Matches 0.0.0.0:9553, 127.0.0.1:9553, [::]:9553, :::9553
				if ($i ~ want "$") found = 1
			}
		}
		END { exit found ? 0 : 1 }
	' <<<"$out"
}

ports_listening_summary() {
	local p out=""
	for p in $(unique_ports); do
		if port_listening "$p"; then
			out+="${out:+, }TCP $p listening"
		else
			out+="${out:+, }TCP $p not listening"
		fi
	done
	echo "${out:-no ports configured}"
}

configured_smb_ports() {
	if [[ -f "$SMB_CONF" ]]; then
		testparm -s 2>/dev/null | awk -F= 'tolower($1) ~ /^[[:space:]]*smb ports[[:space:]]*$/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}'
	fi
}

smbd_socket_lines() {
	ss -lntp 2>/dev/null | awk '/smbd/ || /:139[[:space:]]/ || /:445[[:space:]]/ || /:'"$SMB_PORT"'[[:space:]]/' || true
}

file_stats() {
	if [[ -d "$SMB_DATA" ]]; then
		local n sz
		n=$(find "$SMB_DATA" -type f 2>/dev/null | wc -l | tr -d ' ')
		sz=$(du -sh "$SMB_DATA" 2>/dev/null | awk '{print $1}')
		echo "$n files, ${sz:-0} total"
	else
		echo "(data dir missing)"
	fi
}

pause() {
	echo
	read -rp "Press Enter to continue..." _
}

# ─────────────────────── Status screen ───────────────────────
print_header() {
	cat <<'BANNER'
  ╔══════════════════════════════════════╗
  ║        Samba  (SMB/CIFS) Server      ║
  ║       Installer & Manager  v1.1      ║
  ╚══════════════════════════════════════╝
BANNER
}

print_status() {
	local ip ports cfg_ports
	ip=$(detect_ip)
	ports=$(unique_ports)
	cfg_ports=$(configured_smb_ports || true)

	echo "═══════════════════════════════════════════"
	echo "  Current SMB Status"
	echo "═══════════════════════════════════════════"

	if is_installed; then
		printf "  %-9s: installed %s\n" "Samba" "${C_OK}✓${C_RST}"
	else
		printf "  %-9s: %s\n" "Samba" "${C_BAD}not installed ✗${C_RST}"
	fi

	if smbd_running; then
		printf "  %-9s: running %s\n" "smbd" "${C_OK}✓${C_RST}"
	else
		printf "  %-9s: %s\n" "smbd" "${C_BAD}stopped ✗${C_RST}"
	fi

	if config_exists; then
		printf "  %-9s: yes %s\n" "Config" "${C_OK}✓${C_RST}"
	else
		printf "  %-9s: %s\n" "Config" "${C_WARN}no ✗${C_RST}"
	fi

	if port_listening "$SMB_PORT"; then
		printf "  %-9s: TCP %s listening %s\n" "Listen" "$SMB_PORT" "${C_OK}✓${C_RST}"
	else
		printf "  %-9s: TCP %s %s\n" "Listen" "$SMB_PORT" "${C_BAD}not listening ✗${C_RST}"
	fi

	if [[ -n "$SMB_EXTRA_PORTS" ]]; then
		printf "  %-9s: %s\n" "Extra" "$(ports_listening_summary)"
	fi

	printf "  %-9s: smb://%s:%s/%s\n" "URL" "$ip" "$SMB_PORT" "$SMB_SHARE"
	printf "  %-9s: %s\n" "User" "$SMB_USER"
	printf "  %-9s: %s\n" "Data" "$SMB_DATA"
	printf "  %-9s: %s\n" "Ports" "$ports"
	[[ -n "$cfg_ports" ]] && printf "  %-9s: %s\n" "testparm" "$cfg_ports"
	printf "  %-9s: %s\n" "Files" "$(file_stats)"
	echo "═══════════════════════════════════════════"
}

# ─────────────────────── Firewall helpers ────────────────────
ufw_active() {
	command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"
}

open_firewall() {
	local p
	if ufw_active; then
		for p in $(unique_ports); do
			ufw allow "${p}/tcp" >/dev/null 2>&1 && echo "→ ufw: opened ${p}/tcp"
		done
	fi
}

close_firewall_port() {
	local p="${1:-}"
	valid_port "$p" || return 0
	if ufw_active; then
		ufw delete allow "${p}/tcp" >/dev/null 2>&1 || true
	fi
}

# ───────────────────── Service helpers ───────────────────────
smbd_enable_restart() {
	systemctl enable smbd >/dev/null 2>&1 || true
	if nmbd_unit_exists; then
		systemctl restart smbd nmbd 2>/dev/null || systemctl restart smbd
	else
		systemctl restart smbd
	fi
}

smbd_start() {
	if nmbd_unit_exists; then
		systemctl start smbd nmbd 2>/dev/null || systemctl start smbd
	else
		systemctl start smbd
	fi
}

smbd_stop() {
	if nmbd_unit_exists; then
		systemctl stop smbd nmbd 2>/dev/null || systemctl stop smbd
	else
		systemctl stop smbd
	fi
}

# ─────────────────────── Install flow ────────────────────────
do_install() {
	echo
	warn "Samba is not installed."
	read -rp "Install Samba now? [y/N]: " yn
	[[ "${yn,,}" == "y" || "${yn,,}" == "yes" ]] || {
		echo "Aborted."
		return 1
	}

	echo "→ Installing samba ..."
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -y || die "apt update failed"
	apt-get install -y samba samba-common-bin || die "apt install samba failed"

	configure_share "$SMB_PASS_DEFAULT"
	ok "Samba installed and configured."
	echo
	warn "Default password is '${SMB_PASS_DEFAULT}'. Change it via option [7]!"
}

# ────────────── Build / rebuild the share config ─────────────
# arg1 optional: password to set/reset for the SMB user.
configure_share() {
	local pass="${1:-}"
	local ports

	validate_state_or_die
	ports=$(unique_ports)

	mkdir -p "$SMB_DATA"

	# System user backing the Samba user. No shell, no login.
	if ! id "$SMB_USER" >/dev/null 2>&1; then
		useradd -M -s /usr/sbin/nologin "$SMB_USER" 2>/dev/null || useradd -M -s /bin/false "$SMB_USER"
	fi

	chown -R "$SMB_USER":"$SMB_USER" "$SMB_DATA"
	chmod -R 0775 "$SMB_DATA"

	# Backup existing config once.
	[[ -f "$SMB_CONF" && ! -f "${SMB_CONF}.orig" ]] && cp "$SMB_CONF" "${SMB_CONF}.orig"

	cat >"$SMB_CONF" <<EOF_CONF
#============== Generated by smb_install_manager.sh ==============
[global]
   workgroup = WORKGROUP
   server string = Samba VPS
   server role = standalone server
   smb ports = $ports
   security = user
   map to guest = never
   passdb backend = tdbsam
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   server min protocol = SMB2
   client min protocol = SMB2
   disable netbios = yes
   dns proxy = no

[$SMB_SHARE]
   path = $SMB_DATA
   browseable = yes
   read only = no
   writable = yes
   guest ok = no
   valid users = $SMB_USER
   create mask = 0664
   directory mask = 0775
   force user = $SMB_USER
   force group = $SMB_USER
EOF_CONF

	if ! testparm -s >/dev/null 2>&1; then
		warn "testparm reported issues — check $SMB_CONF"
		testparm -s || true
	fi

	# Set/reset Samba password only when a password is supplied.
	if [[ -n "$pass" ]]; then
		printf '%s\n%s\n' "$pass" "$pass" | smbpasswd -s -a "$SMB_USER" >/dev/null 2>&1
		smbpasswd -e "$SMB_USER" >/dev/null 2>&1
	fi

	save_state
	open_firewall
	smbd_enable_restart
}

# ─────────────────────── Menu actions ────────────────────────
act_start() {
	smbd_start
	ok "Started."
}

act_stop() {
	smbd_stop
	ok "Stopped."
}

act_restart() {
	smbd_enable_restart
	ok "Restarted."
}

act_reload() {
	if smbcontrol all reload-config >/dev/null 2>&1; then
		ok "Config reloaded."
	else
		warn "Reload failed; restarting smbd instead."
		act_restart
	fi
}

act_logs() {
	echo "── smbd journal (last 60 lines) ──"
	journalctl -u smbd -n 60 --no-pager 2>/dev/null || true
	echo
	echo "── recent samba logs ──"
	ls -1 /var/log/samba/ 2>/dev/null | head -30 || true
	echo
	warn "Note: update-apparmor-samba-profile messages about missing smbd-shares can appear even when smbd starts correctly."
	pause
}

act_debug() {
	local cfg_ports
	cfg_ports=$(configured_smb_ports || true)

	echo "===== Manager state file ====="
	if [[ -f "$SMB_STATE" ]]; then
		cat "$SMB_STATE"
	else
		echo "No state file: $SMB_STATE"
	fi

	echo
	echo "===== smb.conf smb ports line ====="
	if [[ -f "$SMB_CONF" ]]; then
		grep -nEi '^[[:space:]]*smb ports[[:space:]]*=' "$SMB_CONF" || echo "No smb ports line found"
	else
		echo "Missing $SMB_CONF"
	fi

	echo
	echo "===== testparm parsed smb ports ====="
	[[ -n "$cfg_ports" ]] && echo "smb ports = $cfg_ports" || echo "No smb ports line from testparm"

	echo
	echo "===== Listening sockets from ss ====="
	ss -lntp 2>/dev/null | grep -E 'smbd|:139[[:space:]]|:445[[:space:]]|:'"$SMB_PORT"'[[:space:]]' || echo "No matching sockets found"

	echo
	echo "===== Robust listener checks ====="
	local p
	for p in $(unique_ports); do
		if port_listening "$p"; then
			echo "OK: TCP $p is listening"
		else
			echo "BAD: TCP $p is not listening"
		fi
	done

	echo
	echo "===== Service status ====="
	systemctl is-active smbd 2>/dev/null || true
	systemctl --no-pager --full status smbd 2>/dev/null | sed -n '1,18p' || true
	pause
}

act_change_user() {
	local nu np old_user
	read -rp "New SMB username [$SMB_USER]: " nu
	nu="${nu:-$SMB_USER}"
	valid_username "$nu" || {
		bad "Invalid username. Use letters, numbers, dot, dash, underscore."
		pause
		return
	}

	read -rsp "New password (leave blank to keep current): " np
	echo

	old_user="$SMB_USER"
	if [[ "$nu" != "$SMB_USER" ]]; then
		id "$nu" >/dev/null 2>&1 || useradd -M -s /usr/sbin/nologin "$nu" 2>/dev/null || useradd -M -s /bin/false "$nu"
		chown -R "$nu":"$nu" "$SMB_DATA"
		smbpasswd -x "$old_user" >/dev/null 2>&1 || true
		SMB_USER="$nu"
	fi

	configure_share "$np"
	ok "User/password updated."
	pause
}

act_change_port() {
	local np old
	read -rp "New primary port [$SMB_PORT]: " np
	np="${np:-$SMB_PORT}"
	valid_port "$np" || {
		bad "Invalid port. Use 1-65535."
		pause
		return
	}

	old="$SMB_PORT"
	SMB_PORT="$np"
	configure_share ""

	if [[ "$old" != "$SMB_PORT" ]]; then
		close_firewall_port "$old"
	fi

	ok "Primary port changed: $old → $SMB_PORT"
	pause
}

act_change_path() {
	local npth
	read -rp "New data path [$SMB_DATA]: " npth
	npth="${npth:-$SMB_DATA}"
	[[ "$npth" == /* ]] || {
		bad "Path must be absolute. Example: /data/SMB_d"
		pause
		return
	}
	mkdir -p "$npth"
	SMB_DATA="$npth"
	configure_share ""
	ok "Share path changed to $SMB_DATA"
	pause
}

act_change_share() {
	local ns
	read -rp "New share name [$SMB_SHARE]: " ns
	ns="${ns:-$SMB_SHARE}"
	valid_share_name "$ns" || {
		bad "Invalid share name. Use letters, numbers, dot, dash, underscore."
		pause
		return
	}
	SMB_SHARE="$ns"
	configure_share ""
	ok "Share name changed to [$SMB_SHARE]"
	pause
}

act_add_445() {
	local yn p found="no"
	warn "Some clients, especially Windows Explorer, require the standard SMB port TCP/445."
	read -rp "Also listen on 445 alongside $SMB_PORT? [y/N]: " yn
	[[ "${yn,,}" == y* ]] || return

	for p in $SMB_EXTRA_PORTS; do
		[[ "$p" == "445" ]] && found="yes"
	done
	[[ "$SMB_PORT" == "445" ]] && found="yes"
	[[ "$found" == "yes" ]] || SMB_EXTRA_PORTS="${SMB_EXTRA_PORTS:+$SMB_EXTRA_PORTS }445"

	configure_share ""
	ok "Now configured to listen on: $(unique_ports)"
	pause
}

act_remove_445() {
	local p new=""
	if [[ "$SMB_PORT" == "445" ]]; then
		bad "445 is the primary port. Change the primary port first."
		pause
		return
	fi
	for p in $SMB_EXTRA_PORTS; do
		[[ "$p" == "445" ]] && continue
		new+="${new:+ }$p"
	done
	SMB_EXTRA_PORTS="$new"
	configure_share ""
	close_firewall_port 445
	ok "Removed extra 445 listener. Now configured to listen on: $(unique_ports)"
	pause
}

act_client_notes() {
	cat <<EOF_NOTES

  ── Client connection notes ──────────────────────────────
  Linux mount:
     sudo mkdir -p /mnt/smb
     sudo mount -t cifs //$(detect_ip)/$SMB_SHARE /mnt/smb \\
        -o username=$SMB_USER,port=$SMB_PORT,vers=3.0

  Linux smbclient:
     smbclient //$(detect_ip)/$SMB_SHARE -U $SMB_USER -p $SMB_PORT

  macOS Finder, Cmd+K:
     smb://$SMB_USER@$(detect_ip):$SMB_PORT/$SMB_SHARE

  Windows Explorer:
     Windows' built-in SMB client normally uses TCP/445 only.
     Enable option [a], then use:
        \\\\$(detect_ip)\\$SMB_SHARE

  Current configured Samba ports:
     $(unique_ports)
  ─────────────────────────────────────────────────────────
EOF_NOTES
	pause
}

act_migrate() {
	cat <<EOF_MIGRATE

  ── rsync migration command, run on OLD server ──
  rsync -avz --progress -e ssh \\
     $SMB_DATA/ \\
     root@$(detect_ip):$SMB_DATA/

  Adjust source path, target IP, and SSH user as needed.
EOF_MIGRATE
	pause
}

act_reinstall() {
	local yn
	warn "Re-install keeps data in $SMB_DATA but rewrites config."
	read -rp "Proceed? [y/N]: " yn
	[[ "${yn,,}" == y* ]] || return
	export DEBIAN_FRONTEND=noninteractive
	apt-get install -y --reinstall samba samba-common-bin
	configure_share ""
	ok "Re-installed."
	pause
}

act_uninstall() {
	local c p
	bad "This removes Samba packages. Data in $SMB_DATA is preserved."
	read -rp "Type REMOVE to confirm: " c
	[[ "$c" == "REMOVE" ]] || {
		echo "Cancelled."
		pause
		return
	}
	smbd_stop || true
	apt-get purge -y samba samba-common-bin 2>/dev/null || true
	apt-get autoremove -y 2>/dev/null || true
	for p in $(unique_ports); do
		close_firewall_port "$p"
	done
	ok "Samba removed. Data left at $SMB_DATA."
	pause
}

# ───────────────────────── Menu loop ─────────────────────────
menu() {
	while true; do
		clear
		print_header
		print_status
		cat <<'EOF_MENU'
  Options:
  [1]  Start smbd
  [2]  Stop smbd
  [3]  Restart smbd
  [4]  Reload config
  [5]  View logs
  [6]  Debug port / config / sockets
  [7]  Change username / password
  [8]  Change primary port
  [c]  Change share path
  [s]  Change share name
  [a]  Also listen on 445   (Windows compatibility)
  [b]  Remove extra 445 listener
  [9]  Show client connect notes
  [m]  Show migration rsync command
  [r]  Re-install            (keeps data)
  [u]  Uninstall Samba       (keeps data)
  [0]  Exit
EOF_MENU
		read -rp "  Choice: " ch
		case "$ch" in
		1) act_start; pause ;;
		2) act_stop; pause ;;
		3) act_restart; pause ;;
		4) act_reload; pause ;;
		5) act_logs ;;
		6) act_debug ;;
		7) act_change_user ;;
		8) act_change_port ;;
		c | C) act_change_path ;;
		s | S) act_change_share ;;
		a | A) act_add_445 ;;
		b | B) act_remove_445 ;;
		9) act_client_notes ;;
		m | M) act_migrate ;;
		r | R) act_reinstall ;;
		u | U) act_uninstall ;;
		0)
			echo "Bye."
			exit 0
			;;
		*)
			bad "Invalid choice."
			sleep 1
			;;
		esac
	done
}

# ─────────────────────────── Main ────────────────────────────
clear
print_header

if is_installed; then
	if ! config_exists; then
		warn "Samba is installed but our [$SMB_SHARE] share is not configured."
		read -rp "Configure it now with default password? [y/N]: " yn
		[[ "${yn,,}" == y* ]] && configure_share "$SMB_PASS_DEFAULT"
	fi
	print_status
	echo
	ok "Samba was found. Showing connection info and status above."
	pause
	menu
else
	print_status
	if do_install; then
		pause
		menu
	else
		exit 0
	fi
fi
