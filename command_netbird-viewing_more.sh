#!/usr/bin/env bash
# command_netbird-viewing_more.sh — pretty "view-only" NetBird peers using netbird status command
# Dependencies: jq, column
set -Eeuo pipefail

# --- Defaults ---
NETBIRD_TIMEOUT="${NETBIRD_TIMEOUT:-30}"
TZ="${TZ:-Asia/Shanghai}"

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
	local package="${2:-$1}" # Use second argument as package name, or default to command name

	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Missing dependency: $cmd"
		echo "Attempting to install $package..."

		# Detect package manager and install
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
		else
			echo "Error: No supported package manager found (apt, yum, dnf, pacman, apk)"
			echo "Please install $package manually"
			exit 2
		fi

		# Verify installation succeeded
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "Error: Failed to install $cmd"
			exit 2
		else
			echo "Successfully installed $cmd"
		fi
	fi
}

need jq
need column bsdmainutils

# --- Get NetBird status JSON ---
get_netbird_status() {
	local json=""
	local is_docker=false
	local public_ip=""

	# First try host version
	if command -v netbird >/dev/null 2>&1; then
		if json=$(timeout "$NETBIRD_TIMEOUT" netbird status --json 2>/dev/null); then
			echo "$json"
			return 0
		fi
	fi

	# Then try docker version
	if command -v docker >/dev/null 2>&1; then
		local container_id
		container_id=$(docker ps -q --filter "ancestor=netbirdio/netbird:latest" | head -1)
		if [[ -n "$container_id" ]]; then
			if json=$(timeout "$NETBIRD_TIMEOUT" docker exec "$container_id" netbird status --json 2>/dev/null); then
				# Get public IP for docker host using multiple methods
				public_ip=$(get_public_ip)
				echo "$json" | jq --arg public_ip "$public_ip" '. + {"_is_docker": true, "_host_public_ip": $public_ip}'
				return 0
			fi
		fi

		# Try by name if no container found by image
		container_id=$(docker ps -q --filter "name=netbird" | head -1)
		if [[ -n "$container_id" ]]; then
			if json=$(timeout "$NETBIRD_TIMEOUT" docker exec "$container_id" netbird status --json 2>/dev/null); then
				# Get public IP for docker host using multiple methods
				public_ip=$(get_public_ip)
				echo "$json" | jq --arg public_ip "$public_ip" '. + {"_is_docker": true, "_host_public_ip": $public_ip}'
				return 0
			fi
		fi
	fi

	echo "Error: Unable to get netbird status. Make sure netbird is running (host or docker)." >&2
	exit 3
}

# --- Get public IP using multiple methods ---
get_public_ip() {
	local ip=""

	# Method 1: ip.sb (fast and reliable)
	if [[ -z "$ip" ]]; then
		ip=$(timeout 5 curl -s --connect-timeout 3 ip.sb 2>/dev/null | head -1)
	fi

	# Method 2: ipify.org
	if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		ip=$(timeout 5 curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null)
	fi

	# Method 3: icanhazip.com
	if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		ip=$(timeout 5 curl -s --connect-timeout 3 https://icanhazip.com 2>/dev/null | tr -d '\n\r')
	fi

	# Method 4: httpbin.org
	if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		ip=$(timeout 5 curl -s --connect-timeout 3 https://httpbin.org/ip 2>/dev/null | jq -r '.origin // empty' 2>/dev/null)
	fi

	# Method 5: checkip.amazonaws.com
	if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		ip=$(timeout 5 curl -s --connect-timeout 3 https://checkip.amazonaws.com 2>/dev/null | tr -d '\n\r')
	fi

	# Validate IP format
	if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "$ip"
	else
		echo ""
	fi
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
(._is_docker // false) as $is_docker |

# Get self public IP - different logic for host vs docker
(if $is_docker then
  # For docker: use the fetched host public IP
  (._host_public_ip // "")
else
  # For host: find first peer with srflx/prflx local type
  (.peers.details
  | map(select(
      .iceCandidateEndpoint.local != "" and
      ((.iceCandidateType.local // "") | IN("srflx","prflx"))
    ))
  | (.[0].iceCandidateEndpoint.local // "")
  | split(":")[0])
end) as $self_public_ip |

# Process all peers including self
(.peers.details + [{
  fqdn: $self_fqdn,
  netbirdIp: .netbirdIp,
  status: "Connected",
  lastStatusUpdate: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  connectionType: "Self",
  iceCandidateEndpoint: {remote: (if $self_public_ip != "" then "\($self_public_ip):0" else "" end)},
  lastWireguardHandshake: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  transferReceived: 0,
  transferSent: 0,
  latency: 0
}])
| map(select( ($only_connected == 0) or (.status == "Connected") ))
| map(select(
    matches(.fqdn; $name)
    and matches(.netbirdIp; $ip)
  ))
| sort_by( __SORT_EXPR__ )
JQ
	)"
	# inject the sort expression safely
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
# Parse timestamps and convert to local time display format
def parse_time(s):
  if (s // "") == "" then empty 
  else
    # Handle various timestamp formats
    (s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)
  end;

# Convert timestamp to YYYY-MM-DD HH:MM:SS format  
def format_time(s):
  if (s // "") == "" then ""
  else
    try (
      (s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) 
      | strftime("%Y-%m-%d %H:%M:%S")
    ) catch ""
  end;

# Humanize seconds as "Xd Xh", "Xh Ym", "Xm Zs", or "Xs" (filter form)
def humanize:
  if (.|tonumber) < 0 then "0s ago"
  else
    ( (. /86400)|floor ) as $d |
    ( ((. %86400)/3600)|floor ) as $h |
    ( ((. % 3600)/60)|floor ) as $m |
    ( (. % 60)|floor ) as $s |
    if   $d > 0 then "\($d)d" + (if $h>0 then " \($h)h" else "" end) + " ago"
    elif $h > 0 then "\($h)h" + (if $m>0 then " \($m)m" else "" end) + " ago"
    elif $m > 0 then "\($m)m" + (if $s>0 then " \($s)s" else "" end) + " ago"
    else "\($s)s ago" end
  end;

# Compute seen_ago for a peer (empty if no lastStatusUpdate)
def seen_ago(p):
  (p.lastStatusUpdate // "") as $ls |
  if $ls == "" then "" else
    try (($now - (parse_time($ls))) | humanize) catch ""
  end;

def header: ["No.","NAME","DNS_LABEL","IP","PUBLIC_IP","CONN","SEEN_AGO","LAST_SEEN"];

def base_row(idx; p):
  [ (idx + 1),                                           # No.
    (p.fqdn//""),                                        # NAME
    (p.fqdn // "" | split(".")[0]),                      # DNS_LABEL  
    ((p.netbirdIp//"") | split("/")[0]),                 # IP (private NetBird IP)
    (((p.iceCandidateEndpoint.remote // "") | split(":")[0]) // ""), # PUBLIC_IP (empty if not found)
    (if p.status == "Connected" then "✓" else "✗" end), # CONN
    (seen_ago(p)),                                       # SEEN_AGO
    (format_time(p.lastStatusUpdate))                    # LAST_SEEN (formatted)
  ];

# Number the rows AFTER filtering & sorting
to_entries as $rows
| (header|@tsv),
( $rows[] |
    .key as $idx | .value as $p |
    (base_row($idx; $p)|@tsv)
)
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
		# Single continuous splitter line (Unicode box-drawing single line)
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
  else
    (s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)
  end;

def format_time(s):
  if (s // "") == "" then ""
  else
    try (
      (s | sub("\\.[0-9]+Z$"; "Z") | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) 
      | strftime("%Y-%m-%d %H:%M:%S")
    ) catch ""
  end;

# Humanize seconds (filter form)
def humanize:
  if (.|tonumber) < 0 then "0s ago"
  else
    ( (. /86400)|floor ) as $d |
    ( ((. %86400)/3600)|floor ) as $h |
    ( ((. % 3600)/60)|floor ) as $m |
    ( (. % 60)|floor ) as $s |
    if   $d > 0 then "\($d)d" + (if $h>0 then " \($h)h" else "" end) + " ago"
    elif $h > 0 then "\($h)h" + (if $m>0 then " \($m)m" else "" end) + " ago"
    elif $m > 0 then "\($m)m" + (if $s>0 then " \($s)s" else "" end) + " ago"
    else "\($s)s ago" end
  end;

def seen_ago(p):
  (p.lastStatusUpdate // "") as $ls |
  if $ls == "" then "" else
    try (($now - (parse_time($ls))) | humanize) catch ""
  end;

# Number rows after filtering & sorting
to_entries as $rows
|
( ["no","name","dns_label","ip","public_ip","connected","seen_ago","last_seen"] | @csv ),
( $rows[] |
  .key as $idx | .value as $p |
  ( [ ($idx+1),
      ($p.fqdn//""), 
      ($p.fqdn // "" | split(".")[0]), 
      (($p.netbirdIp//"") | split("/")[0]),
      (((p.iceCandidateEndpoint.remote // "") | split(":")[0]) // ""),
      ($p.status == "Connected"), 
      (seen_ago($p)), 
      (format_time($p.lastStatusUpdate))
    ]
  ) | @csv
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
	get_netbird_status | jq --arg fqdn "$fqdn" '
    .peers.details[] | select(.fqdn == $fqdn)
  '
}

# --- Simple watch loop (no fragile quoting) ---
watch_loop() {
	trap 'exit 0' INT
	while :; do
		printf '\033c' || true # clear screen
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
