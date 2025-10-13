#!/usr/bin/env bash
# ==============================================================================
# Restic Backup Setup Script for Debian/Ubuntu (Source & Target)
# ==============================================================================
# This script interactively configures:
#   - Target VPS: creates 'restic' user, repo directory, and installs the
#     source's public key (optionally with restrictive flags).
#   - Source VPS: installs restic, generates a dedicated SSH key, sets up
#     SSH config, writes ENV, creates systemd service/timers, and
#     runs an initial backup so you immediately get snapshots.
#
# Requirements:
#   - Run as root (sudo).
#   - Debian/Ubuntu-ish system with systemd.
#   - OpenSSH server on target; outbound SSH from source.
#
# Security notes:
#   - By default, we add the source key as-is. You can choose to add a
#     restricted authorized_keys entry (no-pty, no-port-forwarding, etc.).
#   - StrictHostKeyChecking=no is used in the SSH config for convenience.
#     Adjust to your security posture if desired.
# ==============================================================================

set -Eeuo pipefail

# --- Colors ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

# --- Logging helpers ---
info() { echo -e "${C_CYAN}${C_BOLD}ℹ ${1}${C_RESET}"; }
success() { echo -e "${C_GREEN}${C_BOLD}✔ ${1}${C_RESET}"; }
warn() { echo -e "${C_YELLOW}${C_BOLD}⚠ ${1}${C_RESET}"; }
fatal() {
	echo -e "${C_RED}${C_BOLD}✖ ${1}${C_RESET}"
	exit 1
}

trap 'fatal "An unexpected error occurred. Check the logs above and try again."' ERR

require_root() { [[ "$(id -u)" -eq 0 ]] || fatal "Run as root (use sudo)."; }
require_cmd() { command -v "$1" &>/dev/null || fatal "Missing command: $1"; }

prompt() {
	local msg="${1}"
	local default="${2:-}"
	if [[ -n "$default" ]]; then
		read -rp "${msg} [default: ${default}]: " _ans || true
		echo "${_ans:-$default}"
	else
		read -rp "${msg}: " _ans || true
		echo "${_ans}"
	fi
}

confirm() {
	local msg="${1}"
	local def="${2:-Y}"
	local prompt_suffix="(Y/n)"
	[[ "$def" =~ ^[Nn]$ ]] && prompt_suffix="(y/N)"
	read -rp "${msg} ${prompt_suffix}: " _ans || true
	_ans="${_ans:-$def}"
	[[ "$_ans" =~ ^[Yy]$ ]]
}

is_ip() {
	[[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

ensure_pkg() {
	require_cmd apt-get
	apt-get update -y
	DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# --- Target VPS Setup ---
setup_target() {
	info "Starting Restic Target VPS setup..."

	# restic user
	if id "restic" &>/dev/null; then
		warn "User 'restic' already exists. Skipping user creation."
	else
		adduser --disabled-password --gecos "" restic
		success "Created user 'restic'."
	fi

	# repo path
	local repo_path
	repo_path="$(prompt "Enter the path to store backup data" "/data/Restic_D")"
	mkdir -p "$repo_path"
	chown -R restic:restic "$repo_path"
	chmod 700 "$repo_path"
	success "Repository directory '$repo_path' is ready."

	# add source public key
	info "Paste the PUBLIC SSH key from the SOURCE VPS (single line)."
	local ssh_public_key
	read -r -p "Public key: " ssh_public_key
	[[ -z "${ssh_public_key}" ]] && fatal "SSH public key cannot be empty."

	local restrict_key="N"
	if confirm "Restrict this key (no-pty, no-X11, no-agent, no-port-forwarding)?" "Y"; then
		restrict_key="Y"
	fi

	local ssh_dir="/home/restic/.ssh"
	local auth_keys="${ssh_dir}/authorized_keys"
	mkdir -p "$ssh_dir"
	touch "$auth_keys"

	if grep -Fq "$ssh_public_key" "$auth_keys"; then
		warn "Key already present in authorized_keys. Skipping."
	else
		if [[ "$restrict_key" == "Y" ]]; then
			# You can also add: command="internal-sftp -d ${repo_path}"
			# but restic over sftp works fine without forcing a specific command.
			echo 'no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty '"$ssh_public_key" >>"$auth_keys"
		else
			echo "$ssh_public_key" >>"$auth_keys"
		fi
	fi

	chown -R restic:restic "$ssh_dir"
	chmod 700 "$ssh_dir"
	chmod 600 "$auth_keys"
	success "SSH public key added for user 'restic'."

	echo
	success "✅ Target VPS setup is complete!"
	info "Ready to accept backups at '$repo_path' from the source VPS."
}

# --- Source VPS Setup ---
setup_source() {
	info "Starting Restic Source VPS setup..."

	# Install restic & ssh if needed
	if ! command -v restic &>/dev/null; then
		info "Installing restic..."
		ensure_pkg restic
		success "Restic installed."
	else
		success "Restic is already installed."
	fi
	if ! command -v ssh &>/dev/null; then
		info "Installing OpenSSH client..."
		ensure_pkg openssh-client
		success "OpenSSH client installed."
	fi

	# Optional 'restic' user (service runs as root)
	if ! id "restic" &>/dev/null; then
		adduser --disabled-password --gecos "" restic
		success "Created user 'restic'."
	fi

	# SSH key management (dedicated key)
	local ssh_key_path="/etc/restic/id_restic"
	mkdir -p /etc/restic
	if confirm "Generate a new, dedicated SSH key for Restic?" "Y"; then
		if [[ -f "$ssh_key_path" ]]; then
			warn "SSH key already exists at '$ssh_key_path'."
			echo
			warn "Existing public key:"
			echo -e "${C_YELLOW}$(cat "${ssh_key_path}.pub")${C_RESET}"
			echo
			if confirm "Use the existing key?" "Y"; then
				info "Using existing SSH key."
			else
				if confirm "Generate a new key and overwrite?" "N"; then
					ssh-keygen -t ed25519 -f "$ssh_key_path" -q -N ""
					chmod 600 "$ssh_key_path"
					chmod 644 "${ssh_key_path}.pub"
					success "New SSH key generated at '$ssh_key_path'."
				else
					fatal "Setup cancelled by user."
				fi
			fi
		else
			ssh-keygen -t ed25519 -f "$ssh_key_path" -q -N ""
			chmod 600 "$ssh_key_path"
			chmod 644 "${ssh_key_path}.pub"
			success "New SSH key generated at '$ssh_key_path'."
		fi

		echo
		warn "IMPORTANT: Copy the public key below and paste it on the TARGET VPS:"
		echo -e "${C_YELLOW}$(cat "${ssh_key_path}.pub")${C_RESET}"
		echo
		read -rp "Press [Enter] to continue AFTER you have added the key on the target..." _
	else
		warn "Skipping key generation. Ensure the target accepts your chosen key."
	fi

	# Target host
	local target_host
	target_host="$(prompt "Enter the IP or domain of the Target VPS")"
	[[ -z "$target_host" ]] && fatal "Target host cannot be empty."

	local target_ip=""
	if is_ip "$target_host"; then
		info "Input is an IP address. Using it directly."
		target_ip="$target_host"
	else
		info "Input is a domain name. Resolving..."
		target_ip="$(getent hosts "$target_host" | awk '{print $1}' | head -n1 || true)"
	fi
	[[ -z "$target_ip" ]] && fatal "Could not resolve or validate host '$target_host'."
	success "Target host is set to '$target_ip'."

	local ssh_port
	ssh_port="$(prompt "Enter the SSH port of the Target VPS" "54322")"
	[[ "$ssh_port" =~ ^[0-9]+$ ]] || fatal "SSH port must be numeric."

	# Backup paths - improved handling for multi-line paste
	info "Enter the full paths to back up, one per line. Empty line to finish."
	info "You can paste multiple paths at once."
	local backup_paths=()
	local input_buffer=""

	# Read all input until we get an empty line
	while IFS= read -r line; do
		# Trim whitespace
		line="$(echo "$line" | xargs)"

		# Empty line signals end of input
		if [[ -z "$line" ]]; then
			echo
			break
		fi

		# Process the line as a path
		if [[ -d "$line" || -f "$line" ]]; then
			if [[ ! " ${backup_paths[*]-} " =~ " ${line} " ]]; then
				backup_paths+=("$line")
				echo -e "${C_GREEN}  ✔ Added: ${line}${C_RESET}"
			else
				echo -e "${C_YELLOW}  ⚠ Duplicate ignored: ${line}${C_RESET}"
			fi
		else
			echo -e "${C_YELLOW}  ⚠ Path not found: ${line}${C_RESET}"
		fi
	done

	[[ ${#backup_paths[@]} -gt 0 ]] || fatal "No valid backup paths were provided."

	# Remote repo path
	local remote_repo_path
	remote_repo_path="$(prompt "Enter the Restic repository path on the target" "/data/Restic_D")"

	# Password setup
	info "Setting up Restic repository password."
	local restic_password restic_password_confirm
	read -rs -p "Enter a password for the repository [default: restic]: " restic_password
	echo
	restic_password="${restic_password:-restic}"
	read -rs -p "Confirm the password [default: restic]: " restic_password_confirm
	echo
	restic_password_confirm="${restic_password_confirm:-restic}"
	[[ "$restic_password" == "$restic_password_confirm" ]] || fatal "Passwords do not match."

	# SSH client config (root) to use dedicated key & port
	mkdir -p /root/.ssh && chmod 700 /root/.ssh
	cat >/root/.ssh/config <<EOF
# Restic Target Host Configuration
Host ${target_ip}
    HostName ${target_ip}
    User restic
    Port ${ssh_port}
    IdentityFile ${ssh_key_path}
    StrictHostKeyChecking no
    UserKnownHostsFile /root/.ssh/known_hosts
EOF
	chmod 600 /root/.ssh/config
	success "SSH config created for root to connect to target."

	# Quick connectivity check
	info "Verifying SSH connectivity to target..."
	if ssh -o BatchMode=yes "${target_ip}" "echo ok" &>/dev/null; then
		success "SSH connectivity verified."
	else
		fatal "SSH connection failed. Check port, key, and firewall, then rerun."
	fi

	# Environment file (no 'export' keywords)
	umask 077
	cat >/etc/restic/env <<EOF
# Restic Environment Configuration
RESTIC_REPOSITORY=sftp:restic@${target_ip}:${remote_repo_path}
RESTIC_PASSWORD=${restic_password}
EOF
	chmod 600 /etc/restic/env
	success "Restic environment file created at /etc/restic/env."

	# Create default excludes file
	cat >/etc/restic/excludes <<'EOF'
/dev
/proc
/sys
/run
/tmp
/var/tmp
/var/cache
/var/lib/docker/overlay2
*.swap
*.swp
**/.cache
EOF
	chmod 644 /etc/restic/excludes
	success "Excludes file created at /etc/restic/excludes."

	# Initialize repository (idempotent)
	info "Initializing Restic repository on target (safe if already exists)..."
	RESTIC_REPOSITORY="sftp:restic@${target_ip}:${remote_repo_path}" \
		RESTIC_PASSWORD="${restic_password}" \
		restic init && success "Repository initialized." || warn "Repo may already exist; continuing."

	# Build the backup paths block for systemd ExecStart (multiline)
	local backup_paths_formatted=""
	for p in "${backup_paths[@]}"; do
		backup_paths_formatted+=" \\\
\n  ${p}"
	done

	# Systemd units
	info "Creating systemd service and timer files..."

	cat >/etc/systemd/system/restic-backup.service <<EOF
[Unit]
Description=Restic backup to ${target_ip}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/restic/env
UMask=0077
ExecStart=/usr/bin/restic backup${backup_paths_formatted} \\
  --tag vps-source,scheduled \\
  --exclude-file /etc/restic/excludes
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

	cat >/etc/systemd/system/restic-backup.timer <<'EOF'
[Unit]
Description=Daily restic backup

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

	cat >/etc/systemd/system/restic-prune.service <<EOF
[Unit]
Description=Restic forget+prune for ${target_ip}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/restic/env
UMask=0077
ExecStart=/usr/bin/restic forget --prune \\
  --keep-daily 7 --keep-weekly 4 --keep-monthly 12
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

	cat >/etc/systemd/system/restic-prune.timer <<'EOF'
[Unit]
Description=Weekly restic prune

[Timer]
OnCalendar=weekly
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

	systemctl daemon-reload
	systemctl enable --now restic-backup.timer
	systemctl enable --now restic-prune.timer
	success "Systemd timers have been enabled and started."

	# Run initial backup automatically
	echo
	info "Starting initial backup..."
	if systemctl start restic-backup.service; then
		success "Initial backup triggered. You can watch logs with:"
		echo "  journalctl -u restic-backup.service -n 100 -f"
	else
		warn "Failed to start the backup service. Check 'systemctl status restic-backup.service'."
	fi

	echo
	success "✅ Source VPS setup is complete!"
	info "Manual run: systemctl start restic-backup.service"
	info "Status:      journalctl -u restic-backup.service"
	info "Check snaps: RESTIC_REPOSITORY=\"sftp:restic@${target_ip}:${remote_repo_path}\" RESTIC_PASSWORD='*****' restic snapshots"
	echo "=================== for viewing ==================="
cat << 'EOF'
export RESTIC_REPOSITORY=/data/Restic
export RESTIC_PASSWORD='restic'
restic ls latest
EOF

}

# --- Main ---
main() {
	require_root
	require_cmd awk
	require_cmd getent
	echo -e "${C_BOLD}--- Restic Backup Setup ---${C_RESET}"
	echo "This script will configure Restic for client-server backups."
	echo
	echo "Which part of the setup is this?"
	echo "  1) Target VPS (stores backups)"
	echo "  2) Source VPS (is backed up)"
	read -rp "Choose an option [default: 1]: " choice
	case "${choice:-1}" in
	2) setup_source ;;
	1 | *) setup_target ;;
	esac

}

main
