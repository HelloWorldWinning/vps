#!/bin/bash
#
# up_v6_gcp.sh
#
# Switch a GCE Debian instance that uses /etc/network/interfaces
# to use DHCP for both IPv4 and IPv6 on ens4 (like the official
# netplan/systemd-networkd setup), with automatic rollback if
# connectivity breaks.
#
# Steps:
#   1. Backup /etc/network/interfaces -> /etc/network/interfaces.bak
#   2. Write a DHCP-based config for IPv4 + IPv6 on ens4
#      and restart networking.
#   3. Test IPv4 + IPv6 via curl. If either fails, restore
#      the backup and restart networking again.
#

set -euo pipefail

INTERFACES_FILE="/etc/network/interfaces"
BACKUP_FILE="/etc/network/interfaces.bak"
TEST_URL="https://ip.sb"

echo "[*] up_v6_gcp.sh starting..."

#--- sanity checks -----------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "[!] This script must be run as root." >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "[!] systemctl not found; this script expects a systemd-based system." >&2
  exit 1
fi

if [[ ! -f "$INTERFACES_FILE" ]]; then
  echo "[!] $INTERFACES_FILE not found. This script is meant for ifupdown-based setups." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[!] curl is required for connectivity tests. Install it (apt-get install curl) and retry." >&2
  exit 1
fi

if ! command -v dhclient >/dev/null 2>&1; then
  echo "[!] dhclient (isc-dhcp-client) is required for DHCPv4/v6. Install it (apt-get install isc-dhcp-client) and retry." >&2
  exit 1
fi

#--- Step 1: backup ----------------------------------------------------------

if [[ -f "$BACKUP_FILE" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  echo "[*] Backup file $BACKUP_FILE already exists, copying to ${BACKUP_FILE}.${ts} as extra safety."
  cp -a "$BACKUP_FILE" "${BACKUP_FILE}.${ts}"
fi

echo "[*] Backing up $INTERFACES_FILE -> $BACKUP_FILE"
cp -a "$INTERFACES_FILE" "$BACKUP_FILE"

#--- Step 2: write "official-like" DHCP config ------------------------------
#
# This config:
#   - Uses DHCP for IPv4 on ens4 (like s4/netplan does).
#   - Uses DHCPv6 for IPv6 on ens4.
#   - Keeps loopback as usual.
#

cat > "$INTERFACES_FILE" << 'EOF'
auto lo
iface lo inet loopback

# Primary network interface on GCE (IPv4 via DHCP, IPv6 via DHCPv6)
allow-hotplug ens4

# IPv4: obtain address from GCP metadata via DHCP
iface ens4 inet dhcp
    # You can add DNS here if you want to override dhcp-provided ones
    # dns-nameservers 8.8.8.8 8.8.4.4

# IPv6: obtain address via DHCPv6 (GCP external IPv6)
iface ens4 inet6 dhcp
EOF

echo "[*] New /etc/network/interfaces written (DHCP v4 + v6 on ens4)."

#--- apply new config --------------------------------------------------------

echo "[*] Restarting networking.service (this may briefly drop SSH)..."
if ! systemctl restart networking; then
  echo "[!] systemctl restart networking failed; restoring backup..."
  cp -a "$BACKUP_FILE" "$INTERFACES_FILE"
  systemctl restart networking || true
  exit 1
fi

# Give DHCP a bit of time to complete
echo "[*] Waiting a few seconds for DHCPv4/IPv6 to settle..."
sleep 10

echo "[*] Current addresses for ens4:"
ip addr show dev ens4 || true
echo
echo "[*] Current routes:"
ip route || true
ip -6 route || true
echo

#--- Step 3: test IPv4 & IPv6 -----------------------------------------------

echo "[*] Testing IPv4 connectivity..."
v4_out="$(curl -4 -sS -m 10 "$TEST_URL" || true)"
v4_rc=$?

if [[ $v4_rc -eq 0 && -n "$v4_out" ]]; then
  echo "[+] IPv4 OK: $v4_out"
else
  echo "[!] IPv4 test FAILED (exit=$v4_rc, output='$v4_out')"
fi

echo "[*] Testing IPv6 connectivity..."
v6_out="$(curl -6 -sS -m 10 "$TEST_URL" || true)"
v6_rc=$?

if [[ $v6_rc -eq 0 && -n "$v6_out" ]]; then
  echo "[+] IPv6 OK: $v6_out"
else
  echo "[!] IPv6 test FAILED (exit=$v6_rc, output='$v6_out')"
fi

if [[ $v4_rc -eq 0 && -n "$v4_out" && $v6_rc -eq 0 && -n "$v6_out" ]]; then
  echo "[✓] Both IPv4 and IPv6 are working with the new DHCP-based config."
  exit 0
fi

#--- fallback ----------------------------------------------------------------

echo "[!] Either IPv4 or IPv6 failed; restoring original $INTERFACES_FILE..."
cp -a "$BACKUP_FILE" "$INTERFACES_FILE"

echo "[*] Restarting networking with restored config..."
systemctl restart networking || true

echo "[!] Rolled back to previous /etc/network/interfaces due to failed connectivity test."
exit 1

