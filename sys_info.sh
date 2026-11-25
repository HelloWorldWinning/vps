#!/bin/bash
# sys_info.sh - login banner with a system summary
#
# Optional variables are read from the environment first, then from the last
# matching assignment in the first matching file: ~/.bashrc, ~/.profile,
# ~/.bash_profile. Assignments are read as text.
#
# setup_time_first accepts the output of date, a local timestamp, or an epoch.
# If missing or invalid, it falls back to the modification time of /etc/passwd.
# next_payment_date accepts YYYY[-MM[-DD[_HH[-MM[-SS]]]]].
# Missing date parts default to 01 and missing clock parts default to 00.

export LC_ALL=C

LABEL_W=11
SEP='----------------------------------------------------------------------'

if [[ -t 1 ]]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; RST=$'\033[0m'
else
  RED=''; YEL=''; RST=''
fi

row() { printf "%-${LABEL_W}s : %s\n" "$1" "$2"; }

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

get_var() {
  local name=$1 val=${!1} f line
  if [[ -z $val ]]; then
    for f in ~/.bashrc ~/.profile ~/.bash_profile; do
      [[ -r $f ]] || continue
      line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${name}=" "$f" | tail -n 1)
      if [[ -n $line ]]; then val=${line#*=}; break; fi
    done
  fi
  val=$(trim "$val")
  if [[ $val =~ ^\"([^\"]*)\" || $val =~ ^\'([^\']*)\' ]]; then
    val=${BASH_REMATCH[1]}
  else
    val=${val%%[[:space:]]#*}
  fi
  trim "$val"
}

to_epoch() {
  local s=$1 e
  [[ -z $s ]] && return 1
  if [[ $s =~ ^@?[0-9]{9,}$ ]]; then
    printf '%s\n' "${s#@}"
    return 0
  fi
  e=$(date -d "$s" +%s 2>/dev/null) && { printf '%s\n' "$e"; return 0; }
  # For unrecognized timezone abbreviations, interpret the date as local time.
  s=$(sed -E 's/(^|[[:space:]])[A-Z]{2,5}([[:space:]]|$)/ /g' <<<"$s")
  date -d "$s" +%s 2>/dev/null
}

pay_to_epoch() {
  local re='^([0-9]{4})(-([0-9]{1,2})(-([0-9]{1,2})([_T ]([0-9]{1,2})([-:]([0-9]{1,2})([-:]([0-9]{1,2}))?)?)?)?)?$'
  [[ $1 =~ $re ]] || return 1
  local Y=${BASH_REMATCH[1]} m=${BASH_REMATCH[3]:-1} d=${BASH_REMATCH[5]:-1}
  local H=${BASH_REMATCH[7]:-0} M=${BASH_REMATCH[9]:-0} S=${BASH_REMATCH[11]:-0}
  date -d "$Y-$m-$d $H:$M:$S" +%s 2>/dev/null
}

fmt_dur() {
  local s=$1
  (( s < 0 )) && s=$(( -s ))
  printf '%4dd | %4dh | %4dm' $(( s / 86400 )) $(( s % 86400 / 3600 )) $(( s % 3600 / 60 ))
}

fmt_date() { date -d "@$1" '+%Y-%m-%d %H:%M'; }

DUR_NOTE='    '

lscpu_out=$(lscpu 2>/dev/null)
lscpu_field() {
  awk -F: -v k="$1" '$1 == k { n = split($2, a, " "); print a[1] (n > 1 && a[2] !~ /^\(/ ? " " a[2] : ""); exit }' <<<"$lscpu_out"
}

valid_ipv4() {
  local octet
  local -a octets
  [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a octets <<<"$1"
  for octet in "${octets[@]}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}

valid_ipv6() {
  local address=$1 group groups left right
  group='[[:xdigit:]]{1,4}'
  [[ $address == *:* ]] || return 1
  if [[ $address == *.* ]]; then
    valid_ipv4 "${address##*:}" || return 1
    # An embedded IPv4 address occupies two IPv6 groups.
    address=${address%:*}:0:0
  fi
  if [[ $address != *::* ]]; then
    [[ $address =~ ^($group:){7}$group$ ]]
    return
  fi
  left=${address%%::*}
  right=${address#*::}
  [[ -z $left || $left =~ ^$group(:$group)*$ ]] || return 1
  [[ -z $right || $right =~ ^$group(:$group)*$ ]] || return 1
  groups=${left//[^:]/}${right//[^:]/}
  (( ${#groups} + (${#left} > 0) + (${#right} > 0) < 8 ))
}

public_ip() {
  local family=$1 url answer
  shift
  command -v curl >/dev/null 2>&1 || return 1
  for url in "$@"; do
    answer=$(curl -q "-$family" --noproxy '*' -fsS --connect-timeout 2 --max-time 3 "$url" 2>/dev/null) || continue
    answer=$(trim "$answer")
    if "valid_ipv$family" "$answer"; then
      printf '%s\n' "$answer"
      return 0
    fi
  done
  return 1
}

if [[ -t 1 ]]; then clear; printf '\033c'; fi

now=$(date +%s)
echo "$SEP"

if [[ -n $SSH_CLIENT ]]; then
  row "Last Login" "${SSH_CLIENT%% *}  ($(date '+%Y-%m-%d %H:%M:%S %a'))"
fi

setup_epoch=$(to_epoch "$(get_var setup_time_first)") || setup_epoch=$(stat -c %Y /etc/passwd)
row "Setup Time" "$(fmt_dur $(( now - setup_epoch )))${DUR_NOTE}($(fmt_date "$setup_epoch"))"

up_s=$(cut -d. -f1 /proc/uptime)
row "Up Time" "$(fmt_dur "$up_s")${DUR_NOTE}($(fmt_date $(( now - up_s ))))"

pay_raw=$(get_var next_payment_date)
if [[ -n $pay_raw ]]; then
  if pay_epoch=$(pay_to_epoch "$pay_raw"); then
    left=$(( pay_epoch - now ))
    pay_txt="$(fmt_dur "$left")${DUR_NOTE}($(fmt_date "$pay_epoch")"
    if   (( left < 0 ));         then row "Next Pay" "${RED}${pay_txt}, OVERDUE)${RST}"
    elif (( left < 7 * 86400 )); then row "Next Pay" "${YEL}${pay_txt})${RST}"
    else                              row "Next Pay" "${pay_txt})"
    fi
  else
    row "Next Pay" "${RED}cannot read next_payment_date='${pay_raw}'${RST}"
  fi
fi

cpu_model=$(awk -F: '/^model name/ { sub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo)
cpu_mhz=$(awk -F: '/^cpu MHz/ { sub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo)
cpu_cores=$(lscpu_field 'CPU(s)'); [[ -z $cpu_cores ]] && cpu_cores=$(nproc)
l1=$(lscpu_field 'L1d cache'); l2=$(lscpu_field 'L2 cache'); l3=$(lscpu_field 'L3 cache')

row "CPU Model" "${cpu_model:-unknown}"
row "CPU MHz"   "${cpu_mhz:-unknown}"
row "CPU Cores" "$cpu_cores"
row "CPU Cache" "L1:${l1:-?} / L2:${l2:-?} / L3:${l3:-?}"

os=$(lsb_release -ds 2>/dev/null | tr -d '"')
if [[ -z $os && -r /etc/os-release ]]; then os=$(. /etc/os-release; echo "$PRETTY_NAME"); fi
row "OS"     "${os:-unknown}"
row "Arch"   "$(uname -m)"
row "Kernel" "$(uname -r)"
row "TCP CC" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"

# Memory and disk use the same avail | used | total layout, in 1024-based G.
read -r swap_avail swap_used swap_total < <(
  free -m | awk '/^Swap:/ { printf "%.1f %.1f %.1f\n", $4/1024, $3/1024, $2/1024 }'
)
read -r ram_avail ram_used ram_total < <(
  free -m | awk '/^Mem:/ { printf "%.1f %.1f %.1f\n", $7/1024, $3/1024, $2/1024 }'
)
read -r disk_avail disk_used disk_total < <(
  df -BG --exclude-type overlay --exclude-type tmpfs --total 2>/dev/null |
    awk '$1 == "total" { gsub(/G/, ""); print $4, $3, $2 }'
)

resource_row() {
  local label=$1 avail=${2:-} used=${3:-} total=${4:-}
  if [[ -n $avail && -n $used && -n $total ]]; then
    printf "%-${LABEL_W}s : %5s avail | %5s used | %5s G total\n" "$label" "$avail" "$used" "$total"
  else
    row "$label" "N/A"
  fi
}

resource_row "Swap" "$swap_avail" "$swap_used" "$swap_total"
resource_row "RAM" "$ram_avail" "$ram_used" "$ram_total"
resource_row "Disk" "$disk_avail" "$disk_used" "$disk_total"

if ip4=$(public_ip 4 https://api.ipify.org https://icanhazip.com https://ipinfo.io/ip); then
  row "Public IP 4" "$ip4"
fi
if ip6=$(public_ip 6 https://api6.ipify.org https://icanhazip.com https://ipinfo.io/ip); then
  row "Public IP 6" "$ip6"
fi

echo "$SEP"
