#!/usr/bin/env bash
# Minimal NetBird install + bring-up + concise checks
# Enhancements:
# - If daemon/socket missing, install/start the NetBird service and wait until ready
# - If NetBird is running/connected, first `deregister` and stop/disable service
# - Then do a clean `up` using SETUP_KEY
#
# Prints ONLY:
# - NetBird version
# - NetBird status
# - NetBird systemd state (if systemd exists)
# - WireGuard interfaces via: wg | rg interface   (fallback to grep)

set -euo pipefail

: "${SETUP_KEY:=F52A5E7F-2A31-4390-9B15-4AF53172A1EA}"
INSTALL_URL="https://pkgs.netbird.io/install.sh"
SOCK_PATH="/var/run/netbird.sock"
WAIT_SECS="${WAIT_SECS:-15}" # total wait budget for daemon/socket
SLEEP_STEP=1

have_cmd() { command -v "$1" >/dev/null 2>&1; }

install_curl_if_missing() {
	have_cmd curl && return
	if have_cmd apt-get; then
		sudo apt-get update -y && sudo apt-get install -y curl
	elif have_cmd dnf; then
		sudo dnf install -y curl
	elif have_cmd yum; then
		sudo yum install -y curl
	elif have_cmd pacman; then
		sudo pacman -Sy --noconfirm curl
	elif have_cmd apk; then
		sudo apk add --no-cache curl
	elif have_cmd zypper; then
		sudo zypper install -y curl
	else
		echo "curl missing and no known package manager found" >&2
		exit 1
	fi
}

install_netbird_if_missing() {
	have_cmd netbird && return
	curl -fsSL "$INSTALL_URL" | sh
}

# === Daemon control & readiness ===

daemon_via_cli() {
	netbird service status >/dev/null 2>&1
}

daemon_active_systemd() {
	if have_cmd systemctl; then
		systemctl is-active --quiet netbird 2>/dev/null
	else
		return 1
	fi
}

ensure_daemon_installed_and_started() {
	# Try the CLI's service manager first (works on Debian too)
	if ! daemon_via_cli && ! daemon_active_systemd && [ ! -S "$SOCK_PATH" ]; then
		# Install service if not present
		netbird service install >/dev/null 2>&1 || true
	fi

	# Start/enable via CLI if available; otherwise systemd
	if daemon_via_cli; then
		netbird service enable >/dev/null 2>&1 || true
		netbird service start >/dev/null 2>&1 || true
	elif have_cmd systemctl; then
		sudo systemctl enable --now netbird >/dev/null 2>&1 || true
	fi
}

wait_for_daemon() {
	# Wait for either: socket appears OR 'netbird status' returns something
	local waited=0
	while [ "$waited" -lt "$WAIT_SECS" ]; do
		if [ -S "$SOCK_PATH" ] || netbird status >/dev/null 2>&1; then
			return 0
		fi
		sleep "$SLEEP_STEP"
		waited=$((waited + SLEEP_STEP))
	done
	echo "NetBird daemon did not become ready within ${WAIT_SECS}s" >&2
	echo "If needed, try: sudo netbird service install && sudo netbird service start" >&2
	exit 1
}

connected() {
	# Guard against daemon not ready: caller must run wait_for_daemon first
	netbird status 2>/dev/null | grep -qiE '(^| )connected|status:\s*connected|Connected:\s*true'
}

# === "Running" branch: clean reset ===

deregister_if_running() {
	# If connected or clearly active, deregister & stop/disable before fresh up
	if connected || daemon_via_cli || daemon_active_systemd; then
		echo "Existing NetBird instance detected; deregistering..."
		# Deregister deletes this peer in management & clears local identity
		netbird deregister >/dev/null 2>&1 || true

		# Stop/disable to avoid auto reconnect with old state
		if daemon_via_cli; then
			netbird service stop >/dev/null 2>&1 || true
			netbird service disable >/dev/null 2>&1 || true
		elif have_cmd systemctl; then
			sudo systemctl stop netbird >/dev/null 2>&1 || true
			sudo systemctl disable netbird >/dev/null 2>&1 || true
		fi
	fi
}

bring_up() {
	# Re-enable/start and register/connect with the provided setup key
	if daemon_via_cli; then
		netbird service enable >/dev/null 2>&1 || true
		netbird service start >/dev/null 2>&1 || true
	elif have_cmd systemctl; then
		sudo systemctl enable --now netbird >/dev/null 2>&1 || true
	fi

	wait_for_daemon
	netbird up --setup-key "${SETUP_KEY}"
}

print_info() {
	if have_cmd netbird; then
		echo "NetBird version:"
		netbird version || true
		echo

		echo "NetBird status:"
		netbird status || true
		echo
	fi

	if have_cmd systemctl; then
		echo "NetBird systemd:"
		echo -n "  is-enabled: "
		systemctl is-enabled netbird 2>/dev/null || true
		echo -n "  is-active : "
		systemctl is-active netbird 2>/dev/null || true
		echo
	fi

	echo "WireGuard interfaces (wg | rg interface):"
	if have_cmd wg; then
		if have_cmd rg; then
			wg 2>/dev/null | rg '^interface' || true
		else
			wg 2>/dev/null | grep -E '^interface' || true
		fi
	else
		echo "wg not found"
	fi
}

main() {
	install_curl_if_missing
	install_netbird_if_missing

	if ! have_cmd netbird; then
		echo "netbird CLI not found after install attempt" >&2
		exit 1
	fi

	# Ensure daemon exists and is up enough to answer status, then branch logic
	ensure_daemon_installed_and_started
	wait_for_daemon

	# If already running/connected, do the requested cleanup branch first
	if connected || daemon_via_cli || daemon_active_systemd; then
		deregister_if_running
		# After deregister, we must (re)install/start service and wait again
		ensure_daemon_installed_and_started
		wait_for_daemon
	fi

	# Fresh registration & bring-up, then concise info
	bring_up
	print_info
}

main "$@"
