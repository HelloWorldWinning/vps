#!/usr/bin/env bash
# command_netbird-viewing_more.sh — pretty "view-only" NetBird peers using netbird status command
# Dependencies: jq, column
set -Eeuo pipefail

# --- Defaults ---
NETBIRD_TIMEOUT="${NETBIRD_TIMEOUT:-30}"
TZ="${TZ:-Asia/Shanghai}"

# --- Portable egress IP resolver (IPv4) ---
get_public_ip() {
	local ip=""
	_fetch_ip4() {
		local url="$1" mode="$2" body=""
		case "$mode" in
		trim) body="$(curl -4 -sS --connect-timeout 2 --max-time 3 "$url" 2>/dev/null | head -1 | tr -d '\r\n')" ;;
		json) body="$(curl -4 -sS --connect-timeout 2 --max-time 3 "$url" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)" ;;
		*) body="$(curl -4 -sS --connect-timeout 2 --max-time 3 "$url" 2>/dev/null | tr -d '\r\n')" ;;
		esac
		printf '%s' "$body" | tr -d ' \t\r\n'
	}
	ip="$(_fetch_ip4 'http://ip.sb' trim)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip4 'https://api.ipify.org' trim)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip4 'https://ifconfig.me/ip' trim)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	echo ""
	return 1
}

# --- Portable egress IP resolver (IPv6) ---
get_public_ipv6() {
	local ip=""
	_fetch_ip6() {
		local url="$1"
		# curl -6 forces IPv6
		curl -6 -sS --connect-timeout 2 --max-time 3 "$url" 2>/dev/null | head -1 | tr -d ' \t\r\n'
	}
	# Try a few services that support IPv6
	ip="$(_fetch_ip6 'https://api64.ipify.org')"
	# Basic IPv6 regex validation (colons and hex)
	if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ip" == *:* ]]; then
		echo "$ip"
		return 0
	fi

	ip="$(_fetch_ip6 'https://icanhazip.com')"
	if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ip" == *:* ]]; then
		echo "$ip"
		return 0
	fi

	echo ""
	return 1
}

# --- CLI parsing / help ---
show_help() {
	cat <<'EOF'
Usage:
  command_netbird-viewing_more.sh [list] [--connected] [--name SUBSTR] [--ip SUBSTR]
                                  [--csv] [--json] [--wide] [--sort FIELD] [--watch [N]]

Subcommands:
  list            (default) show table
  json            show filtered JSON
  csv             export CSV
  detail FQDN     show a single peer (pretty JSON)

Options:
  --connected         only connected peers
  --name SUBSTR       filter by name (case-insensitive regex ok)
  --ip SUBSTR         filter by IP (regex ok)
  --wide              (not applicable for command version)
  --sort FIELD        name (default) | ip | last_seen | connected
  --watch [N]         refresh every N seconds (default 5)
  -h, --help          this help

Examples:
  ./command_netbird-viewing_more.sh
  ./command_netbird-viewing_more.sh --connected --name mac
  ./command_netbird-viewing_more.sh --name mac --csv > peers.csv
  ./command_netbird-viewing_more.sh detail macbookpro.ai.com
  ./command_netbird-viewing_more.sh --watch 3
EOF
}

cmd="list"
ONLY_CONNECTED=0
NAME=""
IPF=""
WIDE=0
SORT="name"
WATCH=0
INTERVAL=5
PEER_FQDN=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	list | json | csv)
		cmd="$1"
		shift
		;;
	detail)
		cmd="detail"
		PEER_FQDN="${2-}"
		shift 2
		;;
	--connected)
		ONLY_CONNECTED=1
		shift
		;;
	--name)
		NAME="${2-}"
		shift 2
		;;
	--ip)
		IPF="${2-}"
		shift 2
		;;
	--wide)
		WIDE=1
		shift
		;;
	--sort)
		SORT="${2-name}"
		shift 2
		;;
	--watch)
		WATCH=1
		if [[ "${2-}" =~ ^[0-9]+$ ]]; then
			INTERVAL="$2"
			shift 2
		else shift 1; fi
		;;
	-h | --help)
		show_help
		exit 0
		;;
	*)
		echo "Unknown arg: $1"
		show_help
		exit 1
		;;
	esac
done

# --- Auto-installing dependency checker ---
need() {
	local cmd="$1"
	local package="${2:-$1}"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Missing dependency: $cmd"
		echo "Attempting to install $package..."
		# Simple package manager detection
		if command -v apt >/dev/null 2>&1; then
			sudo apt update && sudo apt install -y "$package"
		elif command -v yum >/dev/null 2>&1; then
			sudo yum install -y "$package"
		elif command -v dnf >/dev/null 2>&1; then
			sudo dnf install -y "$package"
		elif command -v pacman >/dev/null 2>&1; then
			sudo pacman -S --noconfirm "$package"
		elif command -v apk >/dev/null 2>&1; then
			sudo apk add "$package"
		elif command -v brew >/dev/null 2>&1; then
			brew install "$package"
		else
			echo "Please install $package manually"
			exit 2
		fi

		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "Error: Failed to install $cmd"
			exit 2
		fi
	fi
}

need jq
need column bsdmainutils

# --- Get NetBird status JSON (augmented with _host_public_ip4 and _host_public_ip6) ---
get_netbird_status() {
	local json=""
	local ip4=""
	local ip6=""

	# Helper to run netbird command
	run_nb() {
		local to="$NETBIRD_TIMEOUT"
		if command -v timeout >/dev/null 2>&1; then
			timeout "$to" "$@" 2>/dev/null
		elif command -v gtimeout >/dev/null 2>&1; then
			gtimeout "$to" "$@" 2>/dev/null
		else "$@" 2>/dev/null; fi
	}

	# 1. Host binary
	if command -v netbird >/dev/null 2>&1; then
		json=$(run_nb netbird status --json)
	# 2. Docker container by image
	elif command -v docker >/dev/null 2>&1; then
		local cid
		cid=$(docker ps -q --filter "ancestor=netbirdio/netbird:latest" | head -1)
		[[ -z "$cid" ]] && cid=$(docker ps -q --filter "name=netbird" | head -1)

		if [[ -n "$cid" ]]; then
			json=$(run_nb docker exec "$cid" netbird status --json)
			# If found via docker, mark it
			[[ -n "$json" && "$json" != "null" ]] && json=$(echo "$json" | jq '. + {"_is_docker": true}')
		fi
	fi

	if [[ -n "${json:-}" && "$json" != "null" ]]; then
		# Fetch IPs in parallel-ish (background subshells could be used, but keeping it simple/sequential to avoid race cond output)
		ip4="$(get_public_ip || true)"
		ip6="$(get_public_ipv6 || true)"

		# Inject IPs into JSON
		echo "$json" | jq --arg ip4 "$ip4" --arg ip6 "$ip6" '. + {"_host_public_ip4": $ip4, "_host_public_ip6": $ip6}'
		return 0
	fi

	echo "Error: Unable to get netbird status. Make sure netbird is running (host or docker)." >&2
	exit 3
}

# --- Helpers ---
gen_sort_expr() {
	case "$SORT" in
	name) echo '(.fqdn // "" | ascii_downcase)' ;;
	ip) echo '(.netbirdIp // "")' ;;
	last_seen) echo '(.lastStatusUpdate // "")' ;;
	connected) echo '[ (if .status == "Connected" then 0 else 1 end), (.fqdn // "" | ascii_downcase) ]' ;;
	*) echo '(.fqdn // "" | ascii_downcase)' ;;
	esac
}

build_jq_common() {
	local SORT_EXPR
	SORT_EXPR="$(gen_sort_expr)"
	local JQ_COMMON
	JQ_COMMON="$(
		cat <<'JQ'
def matches(s; q): (q == "" or ((s // "") | test(q; "i")));

# Extract self info
(.fqdn) as $self_fqdn |
(.netbirdIp | split("/")[0]) as $self_private_ip |

# Get injected host IPs
(._host_public_ip4 // "") as $self_ip4 |
(._host_public_ip6 // "") as $self_ip6 |

# Process all peers including self
(.peers.details + [{
  fqdn: $self_fqdn,
  netbirdIp: .netbirdIp,
  status: "Connected",
  lastStatusUpdate: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  connectionType: "Self",
  # We use a custom object for self to carry both IPs
  iceCandidateEndpoint: {
     remote: "", 
     _self_ip4: $self_ip4, 
     _self_ip6: $self_ip6 
  },
  lastWireguardHandshake: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  transferReceived: 0,
  transferSent: 0,
  latency: 0
}])
| map(select( ($only_connected == 0) or (.status == "Connected") ))
| map(select(matches(.fqdn; $name) and matches(.netbirdIp; $ip)))
| sort_by( __SORT_EXPR__ )
JQ
	)"
	JQ_COMMON="${JQ_COMMON/__SORT_EXPR__/$SORT_EXPR}"
	printf '%s' "$JQ_COMMON"
}

# --- Rendering: Table (TSV -> column) ---
render_table() {
	local NOW_TS
	NOW_TS=$(date -u +%s)
	local JQ_COMMON
	JQ_COMMON="$(build_jq_common)"
	local JQ_TSV
	JQ_TSV="$(
		cat <<'JQ'
def parse_time(s):
  if (s // "") == "" then empty
  else (s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)
  end;

def format_time(s):
  if (s // "") == "" then ""
  else try ((s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) | strftime("%Y-%m-%d %H:%M:%S")) catch ""
  end;

def humanize:
  if (.|tonumber) < 0 then "0s ago"
  else
    ( (. /86400)|floor ) as $d |
    ( ((. %86400)/3600)|floor ) as $h |
    ( ((. % 3600)/60)|floor ) as $m |
    ( (. % 60)|floor ) as $s |
    if    $d > 0 then "\($d)d" + (if $h>0 then " \($h)h" else "" end) + " ago"
    elif $h > 0 then "\($h)h" + (if $m>0 then " \($m)m" else "" end) + " ago"
    elif $m > 0 then "\($m)m" + (if $s>0 then " \($s)s" else "" end) + " ago"
    else "\($s)s ago" end
  end;

def seen_ago(p):
  (p.lastStatusUpdate // "") as $ls |
  if $ls == "" then "" else try (($now - (parse_time($ls))) | humanize) catch "" end;

# Safe IP extraction that handles IPv6 brackets [2001:db8::1]:51820
def clean_ip(s):
  if (s//"") == "" then ""
  else 
    # Remove leading [ 
    # Remove ]:port OR :port at end
    s | sub("^\\[";"") | sub("\\]:[0-9]+$";"") | sub(":[0-9]+$";"")
  end;

def header: ["No.","NAME","DNS_LABEL","IP","PUB_IP4","PUB_IP6","CONN","SEEN_AGO","LAST_SEEN"];

def base_row(idx; p):
  # Determine Public IPs
  # If it is Self, we use the injected fields
  # If it is Peer, we determine based on the single active connection string
  (if p.connectionType == "Self" then
      {v4: (p.iceCandidateEndpoint._self_ip4 // ""), v6: (p.iceCandidateEndpoint._self_ip6 // "")}
   else
      (clean_ip(p.iceCandidateEndpoint.remote)) as $rem |
      (if ($rem | contains(":")) then "" else $rem end) as $v4 |
      (if ($rem | contains(":")) then $rem else "" end) as $v6 |
      {v4: $v4, v6: $v6}
   end) as $pubs |

  [ (idx + 1),
    (p.fqdn // "" | split(".")[0]),
    (p.fqdn//""),
    ((p.netbirdIp//"") | split("/")[0]),
    ($pubs.v4),
    ($pubs.v6),
    (if p.status == "Connected" then "✓" else "✗" end),
    (seen_ago(p)),
    (format_time(p.lastStatusUpdate))
  ];

to_entries as $rows
| (header|@tsv),
( $rows[] | .key as $idx | .value as $p | (base_row($idx; $p)|@tsv) )
JQ
	)"
	get_netbird_status |
		jq -r \
			--arg name "$NAME" \
			--arg ip "$IPF" \
			--argjson only_connected "$ONLY_CONNECTED" \
			--argjson now "$NOW_TS" \
			"$JQ_COMMON | $JQ_TSV" |
		column -t -s $'\t' |
		awk 'function line(n){for(i=1;i<=n;i++)printf "─"; printf "\n"}
         NR==1{print; line_len=length($0); line(line_len); next}
         {print; line(length($0)>line_len?length($0):line_len)}'
}

# --- Rendering: CSV ---
render_csv() {
	local NOW_TS
	NOW_TS=$(date -u +%s)
	local JQ_COMMON
	JQ_COMMON="$(build_jq_common)"
	local JQ_CSV
	JQ_CSV="$(
		cat <<'JQ'
def parse_time(s):
  if (s // "") == "" then empty
  else (s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)
  end;

def format_time(s):
  if (s // "") == "" then ""
  else try ((s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) | strftime("%Y-%m-%d %H:%M:%S")) catch ""
  end;

def humanize:
  if (.|tonumber) < 0 then "0s ago"
  else
    ( (. /86400)|floor ) as $d |
    ( ((. %86400)/3600)|floor ) as $h |
    ( ((. % 3600)/60)|floor ) as $m |
    ( (. % 60)|floor ) as $s |
    if    $d > 0 then "\($d)d" + (if $h>0 then " \($h)h" else "" end) + " ago"
    elif $h > 0 then "\($h)h" + (if $m>0 then " \($m)m" else "" end) + " ago"
    elif $m > 0 then "\($m)m" + (if $s>0 then " \($s)s" else "" end) + " ago"
    else "\($s)s ago" end
  end;

def seen_ago(p):
  (p.lastStatusUpdate // "") as $ls |
  if $ls == "" then "" else try (($now - (parse_time($ls))) | humanize) catch "" end;

def clean_ip(s):
  if (s//"") == "" then ""
  else 
    s | sub("^\\[";"") | sub("\\]:[0-9]+$";"") | sub(":[0-9]+$";"")
  end;

to_entries as $rows
|
( ["no","name","dns_label","ip","pub_ip4","pub_ip6","connected","seen_ago","last_seen"] | @csv ),
( $rows[] |
  .key as $idx | .value as $p |
  (if p.connectionType == "Self" then
      {v4: (p.iceCandidateEndpoint._self_ip4 // ""), v6: (p.iceCandidateEndpoint._self_ip6 // "")}
   else
      (clean_ip(p.iceCandidateEndpoint.remote)) as $rem |
      (if ($rem | contains(":")) then "" else $rem end) as $v4 |
      (if ($rem | contains(":")) then $rem else "" end) as $v6 |
      {v4: $v4, v6: $v6}
   end) as $pubs |

  ( [ ($idx+1),
      ($p.fqdn // "" | split(".")[0]),
      ($p.fqdn//""),
      (($p.netbirdIp//"") | split("/")[0]),
      ($pubs.v4),
      ($pubs.v6),
      ($p.status == "Connected"),
      (seen_ago($p)),
      (format_time($p.lastStatusUpdate))
    ] | @csv )
)
JQ
	)"
	get_netbird_status |
		jq -r \
			--arg name "$NAME" \
			--arg ip "$IPF" \
			--argjson only_connected "$ONLY_CONNECTED" \
			--argjson now "$NOW_TS" \
			"$JQ_COMMON | $JQ_CSV"
}

# --- Rendering: JSON (unchanged shape, still filtered/sorted) ---
render_json() {
	local JQ_COMMON
	JQ_COMMON="$(build_jq_common)"
	get_netbird_status |
		jq -r \
			--arg name "$NAME" \
			--arg ip "$IPF" \
			--argjson only_connected "$ONLY_CONNECTED" \
			"$JQ_COMMON"
}

# --- Detail by FQDN ---
render_detail() {
	local fqdn="$1"
	[[ -n "$fqdn" ]] || {
		echo "detail: missing PEER_FQDN"
		exit 1
	}
	get_netbird_status | jq --arg fqdn "$fqdn" '.peers.details[] | select(.fqdn == $fqdn)'
}

# --- Simple watch loop ---
watch_loop() {
	trap 'exit 0' INT
	while :; do
		printf '\033c' || true
		render_table
		echo
		date +"Updated: %Y-%m-%d %H:%M:%S (%Z)"
		sleep "$INTERVAL"
	done
}

# --- Execute ---
if [[ "$WATCH" -eq 1 ]]; then
	watch_loop
	exit 0
fi

case "$cmd" in
list) render_table ;;
json) render_json ;;
csv) render_csv ;;
detail) render_detail "$PEER_FQDN" ;;
*)
	show_help
	exit 1
	;;
esac
