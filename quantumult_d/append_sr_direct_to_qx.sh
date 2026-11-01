#!/usr/bin/env bash
# Fetch Shadowrocket DIRECT rules and append Quantumult X rules using Direct_IP.
# Usage: bash append_sr_direct_to_qx.sh direct_ip_domain.txt
# Requires Bash, curl, awk and standard Unix utilities; no Python or jq needed.
# Imports ALL explicit Direct/DIRECT rules in [Rule], including GEOIP,CN.
# Existing rules are preserved. Rules removed upstream are NOT removed locally.
set -euo pipefail
export LC_ALL=C

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [[ $# -ne 1 || -z $1 ]]; then
    printf 'Usage: bash %s direct_ip_domain.txt\n' "${0##*/}" >&2
    exit 2
fi
for tool in curl awk mktemp cp cat date wc mkdir rmdir rm; do
    command -v "$tool" >/dev/null 2>&1 || die "Required command not found: $tool"
done

url='https://johnshall.github.io/Shadowrocket-ADBlock-Rules-Forever/sr_top500_whitelist.conf'
policy='Direct_IP'
# Prefix relative paths so filenames starting with '-' are safe for utilities.
target=$1
[[ $target = /* ]] || target="./$target"
[[ ! -L $target ]] || die 'Please supply a regular file, not a symbolic link.'
[[ ! -e $target || -f $target ]] || die 'Destination is not a regular file.'
[[ ! -e $target || ( -r $target && -w $target ) ]] || die 'Destination must be readable and writable.'

work=$(mktemp -d "${TMPDIR:-/tmp}/sr-direct-qx.XXXXXXXX")
locked=0
lock="${target}.sr-import.lock"
cleanup() {
    rm -rf -- "$work"
    if [[ $locked = 1 ]]; then rmdir -- "$lock" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -- "$lock" 2>/dev/null || die "Cannot acquire lock: $lock (check directory permissions or another running import)."
locked=1

printf 'Downloading Shadowrocket rules...\n'
curl --fail --location --silent --show-error \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 90 --retry 2 \
    --output "$work/source.conf" "$url" || die 'Download failed; destination was not changed.'

# Filter by the policy field, not comments or an entire contiguous Direct block.
# The source mixes Direct and Proxy rules, and uses IP-CIDR for IPv6 too.
awk -v policy="$policy" '
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function fail(s) { print "ERROR: source line " NR ": " s > "/dev/stderr"; bad=1 }
{
    line=trim($0)
    if (line ~ /^(#|;|\/\/)/ || line == "") next
    if (line ~ /^\[/) { in_rules=(tolower(line)=="[rule]"); next }
    if (!in_rules) next
    sub(/[ \t]*#.*/, "", line)
    n=split(line, f, ",")
    if (n < 3 || toupper(trim(f[3])) != "DIRECT") next
    t=toupper(trim(f[1])); value=trim(f[2]); options=""
    if (value == "" || value ~ /[ \t]/) { fail("invalid rule value"); next }
    if (t=="DOMAIN") t="host"
    else if (t=="DOMAIN-SUFFIX") t="host-suffix"
    else if (t=="DOMAIN-KEYWORD") t="host-keyword"
    else if (t=="IP-CIDR" || t=="IP-CIDR6" || t=="IP6-CIDR")
        t=(index(value, ":") ? "ip6-cidr" : "ip-cidr")
    else if (t=="GEOIP") t="geoip"
    else { fail("unsupported DIRECT rule type: " t); next }
    for (i=4; i<=n; i++) {
        opt=tolower(trim(f[i]))
        if (opt=="") continue
        if (opt=="no-resolve" && (t=="ip-cidr" || t=="ip6-cidr" || t=="geoip"))
            options=",no-resolve"
        else { fail("unsupported DIRECT option: " opt) }
    }
    if (t ~ /^host/ || t=="geoip") value=tolower(value)
    print t "," value "," policy options
    count++
}
END {
    if (!count) { print "ERROR: no convertible DIRECT rules found in [Rule]." > "/dev/stderr"; bad=1 }
    if (bad) exit 1
}' "$work/source.conf" > "$work/converted.txt" || die 'Conversion failed; destination was not changed.'

existing="$work/empty"
: > "$existing"
[[ ! -f $target ]] || existing=$target

# Normalize aliases ONLY for comparisons. Preserve every original byte in target.
# Policy names remain case-sensitive, because Direct_IP is a user-defined policy.
awk '
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function key(line,   f,n,t,v,p,i,k) {
    line=trim(line)
    if (line=="" || line ~ /^(#|;|\/\/)/) return ""
    sub(/[ \t]*#.*/, "", line)
    n=split(line, f, ",")
    if (n<3) return ""
    t=tolower(trim(f[1])); v=trim(f[2]); p=trim(f[3])
    if (t=="domain") t="host"
    if (t=="domain-suffix") t="host-suffix"
    if (t=="domain-keyword") t="host-keyword"
    if (t=="ip-cidr6" || t=="ip6-cidr" || (t=="ip-cidr" && index(v, ":"))) t="ip6-cidr"
    v=tolower(v)
    k=t "," v "," p
    for (i=4; i<=n; i++) if (trim(f[i])!="") k=k "," tolower(trim(f[i]))
    return k
}
FILENAME==ARGV[1] { k=key($0); if (k!="") seen[k]=1; next }
{ k=key($0); if (k!="" && !(k in seen)) { print; seen[k]=1 } }
' "$existing" "$work/converted.txt" > "$work/additions.txt"

converted=$(wc -l < "$work/converted.txt")
added=$(wc -l < "$work/additions.txt")
converted=$((converted + 0))
added=$((added + 0))
printf 'Converted: %s | New: %s | Duplicates skipped: %s\n' \
    "$converted" "$added" "$((converted - added))"
if [[ $added -eq 0 ]]; then
    printf 'Already up to date; no changes made.\n'
    exit 0
fi

if [[ -f $target ]]; then
    backup=$(mktemp "${target}.bak.$(date -u +%Y%m%dT%H%M%SZ).XXXXXXXX")
    cp -p -- "$target" "$backup" || die 'Backup failed; destination was not changed.'
    printf 'Backup: %s\n' "$backup"
fi

# Leading newline also handles an existing last line without a newline.
{
    printf '\n# Shadowrocket DIRECT import | %s | policy=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$policy"
    printf '# Source: %s\n' "$url"
    cat "$work/additions.txt"
} >> "$target"
printf 'Appended %s rules to %s\n' "$added" "$target"
printf 'Ensure Quantumult X has a policy named %s. Earlier conflicting rules retain priority.\n' "$policy"
