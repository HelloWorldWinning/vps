#!/usr/bin/env bash
set -euo pipefail

# Debian/Ubuntu VPS preparation for a wg-quick full-tunnel client.
# 1. Installs and verifies required userspace dependencies.
# 2. Detects the original default-route interface addresses.
# 3. Prints PostUp/PreDown lines to paste above [Peer].
#
# Run before enabling the WireGuard configuration.

RULE_PRIORITY="${RULE_PRIORITY:-100}"
INSTALL_DNS_HELPER=1

usage() {
    cat <<'EOF'
Usage: ./prepare-wireguard-vps.sh [--without-resolvconf] [--priority NUMBER]

  --without-resolvconf  Skip resolvconf. Remove every "DNS =" line from the
                        WireGuard configuration when using this option.
  --priority NUMBER     Policy-rule priority (default: 100).
EOF
}

while (($#)); do
    case "$1" in
        --without-resolvconf)
            INSTALL_DNS_HELPER=0
            ;;
        --priority)
            (($# >= 2)) || { printf 'Error: --priority needs a number.\n' >&2; exit 2; }
            RULE_PRIORITY="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Error: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ ! "$RULE_PRIORITY" =~ ^[0-9]+$ ]] || ((RULE_PRIORITY < 1 || RULE_PRIORITY > 32765)); then
    printf 'Error: priority must be an integer from 1 through 32765.\n' >&2
    exit 2
fi

if ((EUID != 0)); then
    printf 'Error: run this script as root.\n' >&2
    printf 'Example: sudo %s\n' "$0" >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    printf 'Error: cannot identify this Linux distribution.\n' >&2
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
    debian|ubuntu) ;;
    *)
        printf 'Error: only Debian and Ubuntu are supported (found %s).\n' "${ID:-unknown}" >&2
        exit 1
        ;;
esac

packages=(wireguard-tools iproute2 iptables)
required_commands=(wg wg-quick ip iptables-restore ip6tables-restore)
if ((INSTALL_DNS_HELPER)); then
    packages+=(resolvconf)
    required_commands+=(resolvconf)
fi

printf 'Installing WireGuard VPS dependencies...\n'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${packages[@]}"

printf '\nVerifying commands...\n'
missing=0
for command_name in "${required_commands[@]}"; do
    if command_path="$(command -v "$command_name" 2>/dev/null)"; then
        printf 'OK: %s -> %s\n' "$command_name" "$command_path"
    else
        printf 'MISSING: %s\n' "$command_name" >&2
        missing=1
    fi
done
((missing == 0)) || exit 1

declare -a rules=()
declare -A seen=()

add_family_rules() {
    local family="$1"
    local host_prefix="$2"
    local ip_flag rule_command address cidr device
    local -a devices=()

    if [[ "$family" == "4" ]]; then
        ip_flag="-4"
        rule_command="ip rule"
    else
        ip_flag="-6"
        rule_command="ip -6 rule"
    fi

    while IFS= read -r device; do
        [[ -n "$device" ]] && devices+=("$device")
    done < <(ip "$ip_flag" route show table main default 2>/dev/null \
        | awk '{for (i=1; i<=NF; i++) if ($i=="dev") print $(i+1)}' \
        | sort -u)

    for device in "${devices[@]}"; do
        while IFS= read -r cidr; do
            [[ -n "$cidr" ]] || continue
            address="${cidr%%/*}"
            [[ -n "${seen["$family:$address"]+x}" ]] && continue
            seen["$family:$address"]=1
            rules+=("PostUp = $rule_command add priority $RULE_PRIORITY from $address/$host_prefix lookup main")
            rules+=("PreDown = $rule_command del priority $RULE_PRIORITY from $address/$host_prefix lookup main || true")
        done < <(ip -o "$ip_flag" addr show dev "$device" scope global 2>/dev/null \
            | awk '{print $4}')
    done
}

add_family_rules 4 32
add_family_rules 6 128

if ((${#rules[@]} == 0)); then
    printf 'Error: no global address was found on a main-table default-route interface.\n' >&2
    exit 1
fi

printf '\n============================================================\n'
printf 'COPY THIS BLOCK ABOVE [Peer] IN THE WG-QUICK CONFIGURATION\n'
printf '============================================================\n'
printf '%s\n' \
    '# Keep replies from the VPS original address on its original route.' \
    "${rules[@]}"
printf '%s\n' '============================================================'

if ((INSTALL_DNS_HELPER)); then
    printf 'Dependencies include resolvconf for configurations containing "DNS =".\n'
else
    printf 'resolvconf was skipped; remove "DNS =" from the configuration.\n'
fi

