#!/bin/bash
# sys_info.sh - login banner with a system summary
#
# Optional variables. Each is read from the environment first; if it is not
# set there, the last "export NAME=..." line in ~/.bashrc, ~/.profile or
# ~/.bash_profile is used (so the order of lines in ~/.bashrc does not matter).
#
#   setup_time_first   When this machine was set up. Write it once with:
#                        echo export setup_time_first=\"$(date)\" >>~/.bashrc
#                      Also accepts "2025-11-13 22:45:00" or an epoch (1731500000).
#                      If missing or unreadable: modification time of /etc/passwd.
#
#   next_payment_date  Next billing date. Accepted formats:
#                        2026-11-16_22-20-45   2026-11-16_22-20   2026-11-16_22
#                        2026-11-16            2026-11            2026
#                      Missing parts default to the start of the period
#                      (2026-11 -> 2026-11-01 00:00, 2026 -> 2026-01-01 00:00).
#                      The "Next Pay" row is printed only when this is set.

export LC_ALL=C

# ---------------------------------------------------------------- settings
LABEL_W=10   # width of the left column (longest label is 10 chars)
SEP='----------------------------------------------------------------------'

if [[ -t 1 ]]; then
  RED=$'\033[31m'; YEL=$'\033[33m'; RST=$'\033[0m'
else
  RED=''; YEL=''; RST=''
fi

# ---------------------------------------------------------------- helpers
# row LABEL VALUE  -> every line goes through here, so the ':' column always lines up
row() { printf "%-${LABEL_W}s : %s\n" "$1" "$2"; }

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

# get_var NAME -> value from the environment, else from the shell rc files (never eval'd)
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
    val=${BASH_REMATCH[1]}                 # quoted: take what is inside the quotes
  else
    val=${val%%[[:space:]]#*}              # unquoted: drop a trailing "# comment"
  fi
  trim "$val"
}

# to_epoch STRING -> epoch seconds for a free-form date (e.g. output of `date`)
to_epoch() {
  local s=$1 e
  [[ -z $s ]] && return 1
  if [[ $s =~ ^@?[0-9]{9,}$ ]]; then echo "${s#@}"; return 0; fi
  e=$(date -d "$s" +%s 2>/dev/null) && { echo "$e"; return 0; }
  # GNU date does not know most zone abbreviations (AWST, CST, ...): drop them
  # and read the time as local time, which is where `date` wrote it.
  s=$(sed -E 's/(^|[[:space:]])[A-Z]{2,5}([[:space:]]|$)/ /g' <<<"$s")
  e=$(date -d "$s" +%s 2>/dev/null) && { echo "$e"; return 0; }
  return 1
}

# pay_to_epoch STRING -> epoch seconds for the next_payment_date formats
pay_to_epoch() {
  local re='^([0-9]{4})(-([0-9]{1,2})(-([0-9]{1,2})([_T ]([0-9]{1,2})([-:]([0-9]{1,2})([-:]([0-9]{1,2}))?)?)?)?)?$'
  [[ $1 =~ $re ]] || return 1
  local Y=${BASH_REMATCH[1]}       m=${BASH_REMATCH[3]:-1}  d=${BASH_REMATCH[5]:-1}
  local H=${BASH_REMATCH[7]:-0}    M=${BASH_REMATCH[9]:-0}  S=${BASH_REMATCH[11]:-0}
  date -d "$Y-$m-$d $H:$M:$S" +%s 2>/dev/null   # also rejects 2026-02-30, 25h, ...
}

# fmt_dur SECONDS -> " 365d |    0h |    6m"  (same 5-char columns as RAM/Swap/Disk)
fmt_dur() {
  local s=$1
  (( s < 0 )) && s=$(( -s ))
  printf '%4dd | %4dh | %4dm' $(( s / 86400 )) $(( s % 86400 / 3600 )) $(( s % 3600 / 60 ))
}

fmt_date() { date -d "@$1" '+%Y-%m-%d %H:%M'; }

# Trailing note column: the "(" sits at the same position on every
# duration row and every size row ("    (" after d/h/m, " G  (" after sizes).
DUR_NOTE='    '
SIZE_NOTE=' G  '

# lscpu FIELD -> first value word (+ unit), e.g. "64 KiB"
lscpu_out=$(lscpu 2>/dev/null)
lscpu_field() {
  awk -F: -v k="$1" '$1 == k { n = split($2, a, " "); print a[1] (n > 1 && a[2] !~ /^\(/ ? " " a[2] : ""); exit }' <<<"$lscpu_out"
}

# ---------------------------------------------------------------- output
if [[ -t 1 ]]; then clear; printf '\033c'; fi

now=$(date +%s)

echo "$SEP"

# Login
if [[ -n $SSH_CLIENT ]]; then
  row "Last Login" "${SSH_CLIENT%% *}  ($(date '+%Y-%m-%d %H:%M:%S %a'))"
fi

# Setup Time: time since setup_time_first (fallback: /etc/passwd mtime)
setup_epoch=$(to_epoch "$(get_var setup_time_first)") || setup_epoch=$(stat -c %Y /etc/passwd)
row "Setup Time" "$(fmt_dur $(( now - setup_epoch )))${DUR_NOTE}($(fmt_date "$setup_epoch"))"

# Up Time: time since boot
up_s=$(cut -d. -f1 /proc/uptime)
row "Up Time" "$(fmt_dur "$up_s")${DUR_NOTE}($(fmt_date $(( now - up_s ))))"

# Next Pay: time left until next_payment_date (row only when the variable is set)
pay_raw=$(get_var next_payment_date)
if [[ -n $pay_raw ]]; then
  if pay_epoch=$(pay_to_epoch "$pay_raw"); then
    left=$(( pay_epoch - now ))
    pay_txt="$(fmt_dur "$left")${DUR_NOTE}($(fmt_date "$pay_epoch")"
    if   (( left < 0 ));          then row "Next Pay" "${RED}${pay_txt}, OVERDUE)${RST}"
    elif (( left < 7 * 86400 ));  then row "Next Pay" "${YEL}${pay_txt})${RST}"
    else                               row "Next Pay" "${pay_txt})"
    fi
  else
    row "Next Pay" "${RED}cannot read next_payment_date='${pay_raw}'${RST}"
  fi
fi

# CPU
cpu_model=$(awk -F: '/^model name/ { sub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo)
cpu_mhz=$(awk -F: '/^cpu MHz/ { sub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo)
cpu_cores=$(lscpu_field 'CPU(s)'); [[ -z $cpu_cores ]] && cpu_cores=$(nproc)
l1=$(lscpu_field 'L1d cache'); l2=$(lscpu_field 'L2 cache'); l3=$(lscpu_field 'L3 cache')

row "CPU Model" "${cpu_model:-unknown}"
row "CPU MHz"   "${cpu_mhz:-unknown}"
row "CPU Cores" "$cpu_cores"
row "CPU Cache" "L1:${l1:-?} / L2:${l2:-?} / L3:${l3:-?}"

# System
os=$(lsb_release -ds 2>/dev/null | tr -d '"')
if [[ -z $os && -r /etc/os-release ]]; then os=$(. /etc/os-release; echo "$PRETTY_NAME"); fi
row "OS"     "${os:-unknown}"
row "Arch"   "$(uname -m)"
row "Kernel" "$(uname -r)"
row "TCP CC" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"

# Memory / disk: avail | used | total, in GB
swap=$(free -m | awk '/^Swap:/ { printf "%5.1f | %5.1f | %5.1f", $4/1024, $3/1024, $2/1024 }')
ram=$(free -m  | awk '/^Mem:/  { printf "%5.1f | %5.1f | %5.1f", $7/1024, $3/1024, $2/1024 }')
disk=$(df -BG --exclude-type overlay --exclude-type tmpfs --total 2>/dev/null |
       awk '$1 == "total" { gsub(/G/, ""); printf "%5s | %5s | %5s", $4, $3, $2 }')
row "Swap" "${swap}${SIZE_NOTE}(avail | used | total)"
row "RAM"  "${ram}${SIZE_NOTE}(avail | used | total)"
row "Disk" "${disk}${SIZE_NOTE}(avail | used | total)"

# Public IP (an error page or JSON from a rate-limited service is ignored)
pub_ip=''
for url in https://ipinfo.io/ip https://api.ipify.org https://icanhazip.com; do
  pub_ip=$(curl -s -m 5 "$url" 2>/dev/null | tr -d '[:space:]')
  [[ $pub_ip =~ ^[0-9A-Fa-f:.]+$ ]] && break
  pub_ip=''
done
row "Public IP" "${pub_ip:-Unable to determine}"

echo "$SEP"
