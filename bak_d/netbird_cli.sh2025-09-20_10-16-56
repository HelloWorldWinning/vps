#!/usr/bin/env bash
# Minimal NetBird install + bring-up + concise checks
# Prints ONLY:
# - NetBird version
# - NetBird status
# - NetBird systemd state (if systemd exists)
# - WireGuard interfaces via: wg | rg interface   (fallback to grep)

set -euo pipefail

: "${SETUP_KEY:=F52A5E7F-2A31-4390-9B15-4AF53172A1EA}"
INSTALL_URL="https://pkgs.netbird.io/install.sh"

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

connected() {
	netbird status 2>/dev/null | grep -qiE '(^| )connected|status:\s*connected'
}

bring_up() {
	netbird up --setup-key "${SETUP_KEY}"
}

print_info() {
	# NetBird version
	if have_cmd netbird; then
		echo "NetBird version:"
		netbird version || true
		echo

		echo "NetBird status:"
		netbird status || true
		echo
	fi

	# systemd state (short)
	if have_cmd systemctl; then
		echo "NetBird systemd:"
		echo -n "  is-enabled: "
		systemctl is-enabled netbird 2>/dev/null || true
		echo -n "  is-active : "
		systemctl is-active netbird 2>/dev/null || true
		echo
	fi

	# WireGuard interfaces (as requested)
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

	if have_cmd netbird; then
		if connected; then
			: # already connected; do nothing
		else
			bring_up
		fi
		print_info
	else
		echo "netbird CLI not found after install attempt" >&2
		exit 1
	fi
}

main "$@"
