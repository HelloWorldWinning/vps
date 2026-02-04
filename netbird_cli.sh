#!/usr/bin/env bash
# NetBird bring-up with "reset + update" flow
# Steps:
#   1) If NetBird is running/connected: deregister
#   2) Stop/disable the service
#   3) Update to latest (or install) via system package manager
#   4) netbird up --setup-key
#   5) Print concise info (version/status/systemd/WireGuard interfaces)

set -euo pipefail

: "${SETUP_KEY:=F52A5E7F-2A31-4390-9B15-4AF53172A1EA}"
INSTALL_URL="https://pkgs.netbird.io/install.sh"
SOCK_PATH="/var/run/netbird.sock"
WAIT_SECS="${WAIT_SECS:-20}" # seconds to wait for daemon socket to appear
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

# ---- Status/daemon helpers ----

daemon_via_cli() { netbird service status >/dev/null 2>&1; }

daemon_active_systemd() {
	if have_cmd systemctl; then
		systemctl is-active --quiet netbird 2>/dev/null
	else
		return 1
	fi
}

connected() {
	netbird status 2>/dev/null | grep -qiE '(^| )connected|status:\s*connected|Connected:\s*true'
}

stop_disable_service() {
	if daemon_via_cli; then
		netbird service stop >/dev/null 2>&1 || true
		netbird service disable >/dev/null 2>&1 || true
	elif have_cmd systemctl; then
		sudo systemctl stop netbird >/dev/null 2>&1 || true
		sudo systemctl disable netbird >/dev/null 2>&1 || true
	fi
}

enable_start_service() {
	if daemon_via_cli; then
		netbird service enable >/dev/null 2>&1 || true
		netbird service start >/dev/null 2>&1 || true
	elif have_cmd systemctl; then
		sudo systemctl enable --now netbird >/dev/null 2>&1 || true
	fi
}

wait_for_daemon() {
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

# ---- Install/Update logic ----
# Strategy:
#   * Ensure repos are configured by running upstream install script (idempotent)
#   * Then use the detected package manager to upgrade/install 'netbird'
#   * Never auto-start here; service control is handled elsewhere.

seed_repos_with_upstream_script() {
	# This ensures the proper repo is configured for your distro.
	curl -fsSL "$INSTALL_URL" | sh || true
}

update_or_install_netbird() {
	seed_repos_with_upstream_script

	if have_cmd apt-get; then
		sudo apt-get update -y
		# Install or upgrade to latest available in repo
		if dpkg -s netbird >/dev/null 2>&1; then
			sudo apt-get install -y --only-upgrade netbird || sudo apt-get install -y netbird
		else
			sudo apt-get install -y netbird
		fi
	elif have_cmd dnf; then
		# dnf upgrade will install if missing with --allowerasing fallback
		if rpm -q netbird >/dev/null 2>&1; then
			sudo dnf upgrade -y netbird || sudo dnf install -y netbird
		else
			sudo dnf install -y netbird
		fi
	elif have_cmd yum; then
		if rpm -q netbird >/dev/null 2>&1; then
			sudo yum update -y netbird || sudo yum install -y netbird
		else
			sudo yum install -y netbird
		fi
	elif have_cmd zypper; then
		if rpm -q netbird >/div/null 2>&1; then
			sudo zypper update -y netbird || sudo zypper install -y netbird
		else
			sudo zypper install -y netbird
		fi
	elif have_cmd pacman; then
		# pacman has no explicit "upgrade-only" for a single package; -S installs/updates
		sudo pacman -Sy --noconfirm netbird
	elif have_cmd apk; then
		# apk add will upgrade if repository has newer version
		sudo apk add --no-cache --upgrade netbird || sudo apk add --no-cache netbird
	else
		# As a last resort, try the upstream script alone
		seed_repos_with_upstream_script
	fi
}

# ---- Main actions ----

deregister_if_running() {
	if connected || daemon_via_cli || daemon_active_systemd; then
		echo "Existing NetBird instance detected; deregistering..."
		netbird deregister >/dev/null 2>&1 || true
		stop_disable_service
	fi
}

bring_up() {
	enable_start_service
	wait_for_daemon
	#netbird up --setup-key "${SETUP_KEY}" --enable-rosenpass --rosenpass-permissive --allow-server-ssh --enable-ssh-root
	netbird up --setup-key "${SETUP_KEY}" --allow-server-ssh --enable-ssh-root
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

	# If netbird isn't present, update_or_install_netbird will install it.
	if ! have_cmd netbird; then
		update_or_install_netbird
	fi

	# If present, reset state if running/connected
	if have_cmd netbird; then
		# Try to stop cleanly even if socket is missing
		deregister_if_running
	else
		echo "netbird CLI still not found after install attempt" >&2
		exit 1
	fi

	# Ensure we’re on the latest available version from repos
	update_or_install_netbird

	# After package changes, the service may be reinstalled; ensure it’s enabled & ready
	# Some distros need explicit install of the service unit:
	if ! daemon_via_cli && ! daemon_active_systemd; then
		# 'netbird service install' is idempotent where supported
		netbird service install >/dev/null 2>&1 || true
	fi

	bring_up
	print_info
}

main "$@"
