#!/usr/bin/env bash
# Verify and finish a Debian 13 generic-cloud installation after normal boot.

set -Eeuo pipefail

EXPECTED_MAJOR="${EXPECTED_MAJOR:-13}"

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[[ $EUID -eq 0 ]] || die "Run this script as root."
[[ ! -e /run/live/medium ]] || die "Rescue Mode is still active. End the Rescue session in VirtFusion first."
[[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."

# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == debian ]] || die "This is not Debian."
[[ ${VERSION_ID:-} == "$EXPECTED_MAJOR" ]] || die "Expected Debian $EXPECTED_MAJOR, found ${VERSION_ID:-unknown}."

printf 'Detected: %s\n' "${PRETTY_NAME:-Debian}"
printf 'Kernel:   %s\n' "$(uname -r)"

#if command -v cloud-init >/dev/null 2>&1; then
#    printf '\nWaiting for cloud-init...\n'
#    cloud-init status --wait
#    [[ $(cloud-init status --format json 2>/dev/null | grep -c '"status": "done"' || true) -ge 1 ]] || \
#        printf 'WARNING: Review cloud-init status and logs if provisioning was not successful.\n' >&2
#else
#    printf 'WARNING: cloud-init is not installed.\n' >&2
#fi

if command -v cloud-init >/dev/null 2>&1; then
	printf '\nWaiting for cloud-init...\n'

	if ! cloud-init status --wait; then
		printf 'WARNING: cloud-init completed with errors; review its status and logs.\n' >&2
	fi

	cloud-init status --long || true
else
	printf 'WARNING: cloud-init is not installed.\n' >&2
fi

printf '\nUpdating Debian packages...\n'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get full-upgrade -y
apt-get autoremove --purge -y
apt install wget curl tmux cron -y

systemctl enable --now cron 2>/dev/null || true
if systemctl is-active --quiet cron; then
	printf 'cron is running.\n'
else
	printf 'WARNING: cron is not running; install or start cron manually.\n' >&2
fi

if ! dpkg-query -W -f='${Status}' qemu-guest-agent 2>/dev/null | grep -q 'ok installed'; then
	apt-get install -y qemu-guest-agent
fi

# This unit is static on Debian and normally starts when its VirtIO device exists.
systemctl start qemu-guest-agent 2>/dev/null ||
	printf 'NOTICE: qemu-guest-agent is not active; the provider may not expose its VirtIO device.\n' >&2

printf '\nSystem verification:\n'
cat /etc/os-release
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,MOUNTPOINTS
df -h /
ip -4 addr show
ip -4 route show
systemctl is-active qemu-guest-agent 2>/dev/null || true

if [[ -e /run/reboot-required ]]; then
	printf '\nA reboot is recommended to finish package updates.\n'
else
	printf '\nDebian %s setup is complete; no reboot is currently required.\n' "$EXPECTED_MAJOR"
fi
