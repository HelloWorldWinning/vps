#!/usr/bin/env bash
# wg_newer.sh — install newer wireguard-tools from Debian backports (no unstable/sid)
set -euo pipefail

# Re-run as root if needed
[ "$(id -u)" -eq 0 ] || exec sudo -- "$0" "$@"

. /etc/os-release
CODENAME="${VERSION_CODENAME:?cannot detect Debian codename}"
BPO="${CODENAME}-backports"

# 1) Clean up unstable left by the old version of this script
if [ -e /etc/apt/sources.list.d/unstable.list ] || [ -e /etc/apt/preferences.d/limit-unstable ]; then
	echo ">> Packages currently installed from unstable (review this list):"
	apt list --installed 2>/dev/null | grep -E '/unstable[ ,]' || echo "   (none)"
	rm -f /etc/apt/sources.list.d/unstable.list /etc/apt/preferences.d/limit-unstable
	echo ">> Removed unstable source and pin."
fi

# 2) Enable backports only if no active (uncommented) entry exists
if ! grep -RhsqE "^[^#]*[[:space:]]${BPO}([[:space:]]|$)" /etc/apt/sources.list /etc/apt/sources.list.d/; then
	cat >"/etc/apt/sources.list.d/${BPO}.sources" <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${BPO}
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
	echo ">> Added ${BPO}."
fi

# 3) Install the backports version.
#    The 'pkg/release' form selects that exact version, so it also downgrades
#    from a newer sid build. ('-t' alone will not downgrade.)
apt-get update
apt-get install -y --allow-downgrades "wireguard-tools/${BPO}"

# 4) Verify
apt-cache policy wireguard-tools
wg --version
