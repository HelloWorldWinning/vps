#!/usr/bin/env bash
set -Eeuo pipefail

# up_v4v6_aws.sh
#
# Debian AWS ifupdown -> AWS-style netplan v4/v6.
#
# Before success:
#   /etc/network/interfaces is the fallback.
#
# After success:
#   /etc/network/interfaces is moved to /etc/network/interfaces.bak
#   /etc/network/interfaces is replaced with loopback-only config.
#
# Netplan file:
#   /etc/netplan/50-cloud-init.yaml

IFACE="${IFACE:-ens5}"

INTERFACES="/etc/network/interfaces"
INTERFACES_SUCCESS_BAK="/etc/network/interfaces.bak"

NETPLAN_DIR="/etc/netplan"
NETPLAN_FILE="${NETPLAN_DIR}/50-cloud-init.yaml"

STAMP="$(date +%Y%m%d_%H%M%S)"
INTERFACES_ROLLBACK_COPY="/root/interfaces.rollback.before_up_v4v6_aws.${STAMP}"
NETPLAN_COPY_DIR="/root/netplan.backup.before_up_v4v6_aws.${STAMP}"

PING4_TARGET="${PING4_TARGET:-8.8.8.8}"
PING6_TARGET="${PING6_TARGET:-2606:4700:4700::1111}"

log() {
    echo "[$(date '+%F %T')] $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

need_root() {
    [ "$(id -u)" -eq 0 ] || die "Run as root."
}

detect_iface() {
    local detected=""

    detected="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}' || true)"

    if [ -n "${detected}" ]; then
        echo "${detected}"
    else
        echo "${IFACE}"
    fi
}

install_netplan_if_missing() {
    if cmd_exists netplan; then
        log "netplan already installed."
        return 0
    fi

    log "netplan missing. Installing netplan.io before changing network."

    cmd_exists apt-get || die "apt-get not found. Install netplan.io manually."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update || die "apt-get update failed. Network unchanged."
    apt-get install -y netplan.io || die "apt-get install netplan.io failed. Network unchanged."

    cmd_exists netplan || die "netplan still missing after install. Network unchanged."

    log "netplan.io installed."
}

backup_before_change() {
    [ -f "${INTERFACES}" ] || die "Missing fallback file: ${INTERFACES}"

    cp -a "${INTERFACES}" "${INTERFACES_ROLLBACK_COPY}"
    log "Saved rollback copy: ${INTERFACES_ROLLBACK_COPY}"

    mkdir -p "${NETPLAN_DIR}"
    mkdir -p "${NETPLAN_COPY_DIR}"

    if ls "${NETPLAN_DIR}"/*.yaml >/dev/null 2>&1; then
        cp -a "${NETPLAN_DIR}"/*.yaml "${NETPLAN_COPY_DIR}/"
        log "Saved old netplan YAML files to: ${NETPLAN_COPY_DIR}"
    else
        log "No old netplan YAML files found."
    fi
}

write_netplan() {
    local mac="$1"

    cat > "${NETPLAN_FILE}" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      match:
        macaddress: "${mac}"
      dhcp4: true
      dhcp6: true
      set-name: "${IFACE}"
EOF

    chmod 600 "${NETPLAN_FILE}"

    log "Generated AWS-style netplan:"
    cat "${NETPLAN_FILE}"
}

restore_fallback() {
    log "Fallback started."

    if [ -f "${NETPLAN_FILE}" ]; then
        mv -f "${NETPLAN_FILE}" "${NETPLAN_FILE}.failed.${STAMP}"
        log "Moved failed netplan file to: ${NETPLAN_FILE}.failed.${STAMP}"
    fi

    if [ -d "${NETPLAN_COPY_DIR}" ]; then
        find "${NETPLAN_COPY_DIR}" -maxdepth 1 -type f -name '*.yaml' -exec cp -a {} "${NETPLAN_DIR}/" \;
        log "Restored old netplan YAML files, if any."
    fi

    if [ -f "${INTERFACES_ROLLBACK_COPY}" ]; then
        cp -a "${INTERFACES_ROLLBACK_COPY}" "${INTERFACES}"
        log "Restored ${INTERFACES}"
    fi

    log "Restarting ifupdown networking."

    if cmd_exists ifdown; then
        ifdown --force "${IFACE}" 2>/dev/null || true
    fi

    ip addr flush dev "${IFACE}" 2>/dev/null || true

    if cmd_exists ifup; then
        ifup "${IFACE}" 2>/dev/null || true
    fi

    if cmd_exists systemctl; then
        systemctl restart networking 2>/dev/null || true
    else
        service networking restart 2>/dev/null || true
    fi

    log "Fallback finished."

    ip addr show dev "${IFACE}" || true
    ip route || true
    ip -6 route || true
}

fail_and_restore() {
    local reason="$1"

    echo
    log "FAILED: ${reason}"
    restore_fallback
    exit 1
}

wait_for_ipv4() {
    local i

    for i in $(seq 1 30); do
        if ip -4 addr show dev "${IFACE}" scope global | grep -q 'inet '; then
            return 0
        fi
        sleep 1
    done

    return 1
}

wait_for_ipv6() {
    local i

    for i in $(seq 1 45); do
        if ip -6 addr show dev "${IFACE}" scope global | grep -q 'inet6 '; then
            return 0
        fi
        sleep 1
    done

    return 1
}

ping4_ok() {
    ping -4 -c 3 -W 3 "${PING4_TARGET}" >/dev/null 2>&1
}

ping6_ok() {
    ping -6 -c 3 -W 5 "${PING6_TARGET}" >/dev/null 2>&1
}

disable_ifupdown_after_success() {
    log "Disabling old ifupdown config for ${IFACE}."

    if [ ! -f "${INTERFACES}" ]; then
        log "${INTERFACES} does not exist; writing loopback-only file."
    elif grep -Eq "^[[:space:]]*iface[[:space:]]+${IFACE}[[:space:]]+" "${INTERFACES}"; then
        if [ -e "${INTERFACES_SUCCESS_BAK}" ]; then
            mv -f "${INTERFACES_SUCCESS_BAK}" "${INTERFACES_SUCCESS_BAK}.${STAMP}"
            log "Existing ${INTERFACES_SUCCESS_BAK} moved to ${INTERFACES_SUCCESS_BAK}.${STAMP}"
        fi

        mv -f "${INTERFACES}" "${INTERFACES_SUCCESS_BAK}"
        log "Moved ${INTERFACES} to ${INTERFACES_SUCCESS_BAK}"
    else
        log "${INTERFACES} does not contain ${IFACE}; keeping a clean loopback-only file."
    fi

    cat > "${INTERFACES}" <<EOF
# This host uses netplan for primary networking.
# Old config was moved to:
#   ${INTERFACES_SUCCESS_BAK}
#
# Netplan file:
#   ${NETPLAN_FILE}

auto lo
iface lo inet loopback
EOF

    chmod 644 "${INTERFACES}"

    log "Wrote loopback-only ${INTERFACES}"
}

main() {
    need_root

    cmd_exists ip || die "Missing command: ip"
    cmd_exists awk || die "Missing command: awk"
    cmd_exists grep || die "Missing command: grep"
    cmd_exists ping || die "Missing command: ping"

    IFACE="$(detect_iface)"

    [ -d "/sys/class/net/${IFACE}" ] || die "Interface does not exist: ${IFACE}"

    local mac
    mac="$(cat "/sys/class/net/${IFACE}/address")"
    [ -n "${mac}" ] || die "Could not read MAC address for ${IFACE}"

    log "Interface: ${IFACE}"
    log "MAC: ${mac}"
    log "Fallback file before success: ${INTERFACES}"
    log "Target netplan file: ${NETPLAN_FILE}"

    install_netplan_if_missing
    backup_before_change
    write_netplan "${mac}"

    if cmd_exists systemctl; then
        systemctl enable systemd-networkd >/dev/null 2>&1 || true
        systemctl start systemd-networkd >/dev/null 2>&1 || true
    fi

    log "Running: netplan generate"
    netplan generate || fail_and_restore "netplan generate failed"

    log "Running: netplan apply"
    netplan apply || fail_and_restore "netplan apply failed"

    log "Waiting for IPv4 address."
    wait_for_ipv4 || fail_and_restore "No IPv4 address after netplan apply"

    log "Waiting for IPv6 address."
    wait_for_ipv6 || fail_and_restore "No IPv6 address after netplan apply"

    log "Current address state:"
    ip addr show dev "${IFACE}" || true

    log "Current route state:"
    ip route || true
    ip -6 route || true

    log "Testing IPv4 ping: ${PING4_TARGET}"
    ping4_ok || fail_and_restore "IPv4 ping failed"

    log "Testing IPv6 ping: ${PING6_TARGET}"
    ping6_ok || fail_and_restore "IPv6 ping failed"

    disable_ifupdown_after_success

    echo
    log "SUCCESS: IPv4 and IPv6 both work."
    log "Active netplan file: ${NETPLAN_FILE}"
    log "Old ifupdown config: ${INTERFACES_SUCCESS_BAK}"
    log "Current ${INTERFACES}: loopback only"
    log "Emergency rollback copy: ${INTERFACES_ROLLBACK_COPY}"
}

main "$@"
