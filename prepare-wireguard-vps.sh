#!/usr/bin/env bash
set -euo pipefail

# prepare-wireguard-vps.sh (v3, read-only)
#
# Prints the PostUp/PreDown BLOCK for a wg-quick full-tunnel client on a VPS.
# Paste the BLOCK into the [Interface] section of the WireGuard config,
# ABOVE the first [Peer] line. Without it, replies to inbound SSH leave
# through the tunnel and SSH stops working.
#
# This script:
#   - only READS with "ip route", "ip addr" and "ip rule"
#   - never installs packages, never writes or edits any file
#     (not /etc/hosts, not /etc/resolv.conf, not the WireGuard config)
#   - does not need root
#   - prints the same BLOCK every time it runs
#
# Usage: bash prepare-wireguard-vps.sh [--priority NUMBER]
#   --priority NUMBER  ip rule priority, 1-32765 (default: 100). It must be
#                      lower than the priorities of the tunnel's own rules.

RULE_PRIORITY="${RULE_PRIORITY:-100}"

while (($#)); do
    case "$1" in
        --priority)
            (($# >= 2)) || { printf 'Error: --priority needs a number.\n' >&2; exit 2; }
            RULE_PRIORITY="$2"
            shift
            ;;
        -h|--help)
            sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            printf 'Error: unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
    shift
done

if [[ ! "$RULE_PRIORITY" =~ ^[0-9]+$ ]] || ((RULE_PRIORITY < 1 || RULE_PRIORITY > 32765)); then
    printf 'Error: priority must be an integer from 1 through 32765.\n' >&2
    exit 2
fi

command -v ip >/dev/null 2>&1 || { printf 'Error: "ip" command not found (package iproute2).\n' >&2; exit 1; }

declare -a rules=()
declare -A seen=()

add_family_rules() { # <4|6> <host prefix length>
    local family="$1" host_prefix="$2" flag rule_cmd device cidr address
    local -a devices=()

    if [[ "$family" == 4 ]]; then
        flag=-4; rule_cmd='ip -4 rule'
    else
        flag=-6; rule_cmd='ip -6 rule'
    fi

    # Interfaces that carry the default route in the main table (e.g. ens4).
    while IFS= read -r device; do
        [[ -n "$device" ]] && devices+=("$device")
    done < <(ip "$flag" route show table main default 2>/dev/null \
        | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") print $(i + 1)}' \
        | sort -u)

    # One rule pair per global address on those interfaces.
    for device in "${devices[@]}"; do
        while IFS= read -r cidr; do
            [[ -n "$cidr" ]] || continue
            address="${cidr%%/*}"
            [[ -n "${seen["$family:$address"]+x}" ]] && continue
            seen["$family:$address"]=1
            rules+=("PostUp = $rule_cmd add priority $RULE_PRIORITY from $address/$host_prefix lookup main")
            rules+=("PreDown = $rule_cmd del priority $RULE_PRIORITY from $address/$host_prefix lookup main || true")
        done < <(ip -o "$flag" addr show dev "$device" scope global 2>/dev/null | awk '{print $4}')
    done
}

add_family_rules 4 32
add_family_rules 6 128

if ((${#rules[@]} == 0)); then
    printf 'Error: no global address was found on a main-table default-route interface.\n' >&2
    printf 'Check: ip route show default; ip -6 route show default\n' >&2
    exit 1
fi

printf '============================================================\n'
printf 'PASTE THIS BLOCK INTO [Interface], ABOVE THE FIRST [Peer]\n'
printf '============================================================\n'
printf '# Keep replies from the VPS original address on its original route.\n'
printf '%s\n' "${rules[@]}"
printf '============================================================\n'
