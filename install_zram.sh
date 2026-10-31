#!/usr/bin/env bash
# Run: bash install_zram.sh
# Debian + systemd. Uses Debian's zram-tools default configuration.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

installed() {
    [[ "$(dpkg-query -W -f='${Status}' zram-tools 2>/dev/null || true)" == 'install ok installed' ]]
}
active_zram() {
    awk 'NR > 1 && $1 ~ /^\/dev\/zram[0-9]+$/ {found=1} END {exit !found}' /proc/swaps
}
show_status() {
    echo
    echo '========== Current zram / memory status =========='
    if installed; then
        echo 'zram-tools: installed'
    else
        echo 'zram-tools: not installed'
    fi
    if command -v free >/dev/null; then free -h; fi
    echo
    echo 'Active swap devices:'
    if command -v swapon >/dev/null; then
        swapon --show || true
    else
        cat /proc/swaps
    fi
    echo
    echo 'zram devices (empty means none):'
    if command -v zramctl >/dev/null; then zramctl || true; fi
    if [[ -d /run/systemd/system ]]; then
        echo
        echo 'zramswap.service:'
        systemctl --no-pager --full status zramswap.service 2>/dev/null || true
    fi
    if [[ -r /etc/default/zramswap ]]; then
        echo
        echo 'Explicit settings in /etc/default/zramswap:'
        awk '/^[[:space:]]*[^#[:space:]]/ {print; n++} END {if (!n) print "(Package defaults; no explicit overrides.)"}' /etc/default/zramswap
    fi
    echo '================================================='
}
fail() { echo "ERROR: $*" >&2; exit 1; }
trap 'echo "ERROR: failed at line $LINENO (exit $?)." >&2' ERR

show_status

if active_zram; then
    echo 'zram swap is already active. No changes needed.'
    exit 0
fi

[[ -r /etc/os-release ]] || fail 'Cannot identify this operating system.'
. /etc/os-release
[[ "${ID:-}" == debian ]] || fail 'This script is intended for Debian.'
[[ -d /run/systemd/system ]] || fail 'systemd is required. Some container VPSs cannot manage zram.'

if ! installed; then
    echo
    answer=''
    printf 'Install and enable zram? [Y/n] (default Yes after 3 seconds): '
    if [[ -t 0 ]]; then
        if ! IFS= read -r -t 3 answer; then
            answer=''
            echo
            echo 'No completed answer within 3 seconds; using Yes.'
        fi
    else
        fail 'Run interactively over SSH: bash install_zram.sh'
    fi
    case "$answer" in
        ''|y|Y) ;;
        n|N) echo 'Cancelled. Nothing changed.'; exit 0 ;;
        *) echo 'Unrecognized answer. Nothing changed.'; exit 0 ;;
    esac
fi

# Ask for privilege only after the installation question.
if (( EUID != 0 )); then
    command -v sudo >/dev/null || fail 'Run this script as root; sudo is unavailable.'
    sudo -v
    ROOT=(sudo)
else
    ROOT=()
fi

if ! installed; then
    echo 'Installing Debian zram-tools...'
    "${ROOT[@]}" apt-get update
    "${ROOT[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y zram-tools util-linux kmod
fi

# Leave active devices and their data alone; never restart active swap.
if ! active_zram; then
    echo 'Enabling and starting zramswap.service...'
    if ! "${ROOT[@]}" systemctl enable --now zramswap.service; then
        "${ROOT[@]}" journalctl -u zramswap.service -n 30 --no-pager || true
        fail 'Could not start zram. Check the log above; the VPS kernel must support zram.'
    fi
else
    "${ROOT[@]}" systemctl enable zramswap.service
fi

show_status
active_zram || fail 'Service finished, but no active zram swap was found. Check journalctl -u zramswap.service.'
echo 'Done: zram swap is active and enabled at boot.'
echo 'Configuration: /etc/default/zramswap (Debian package defaults unless already customized).'
