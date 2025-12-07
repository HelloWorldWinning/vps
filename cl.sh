#!/usr/bin/env bash
# command_netbird-viewing_more.sh — pretty "view-only" NetBird peers using netbird status command
# Dependencies: jq, column
set -Eeuo pipefail

# --- Defaults ---
NETBIRD_TIMEOUT="${NETBIRD_TIMEOUT:-30}"
TZ="${TZ:-Asia/Shanghai}"

# --- Portable egress IP resolver (IPv4) ---
# Returns first valid IPv4 egress address; prints only the IP or empty on failure.
get_public_ip() {
	local ip=""
	_fetch_ip() {
		local url="$1" mode="$2" body=""
		case "$mode" in
		trim) body="$(curl -4 -sS --connect-timeout 3 --max-time 5 "$url" 2>/dev/null | head -1 | tr -d '\r\n')" ;;
		json) body="$(curl -4 -sS --connect-timeout 3 --max-time 5 "$url" 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)" ;;
		*) body="$(curl -4 -sS --connect-timeout 3 --max-time 5 "$url" 2>/dev/null | tr -d '\r\n')" ;;
		esac
		printf '%s' "$body" | tr -d ' \t\r\n'
	}
	ip="$(_fetch_ip 'http://ip.sb' trim)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip 'https://api.ipify.org' trim)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip 'https://icanhazip.com' trim)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip 'https://httpbin.org/ip' json)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip 'https://checkip.amazonaws.com' trim)"
	[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
		echo "$ip"
		return 0
	}
	echo ""
	return 1
}

# --- Portable egress IP resolver (IPv6) ---
# Returns first valid IPv6 egress address; prints only the IP or empty on failure.
get_public_ip_v6() {
	local ip=""
	_fetch_ip_v6() {
		local url="$1" body=""
		body="$(curl -6 -sS --connect-timeout 3 --max-time 5 "$url" 2>/dev/null | head -1 | tr -d '\r\n' | tr -d '[] \t')"
		printf '%s' "$body"
	}
	# Simple check for IPv6 format (contains colons and valid hex chars)
	_is_ipv6() {
		local addr="$1"
		[[ "$addr" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$addr" == *:* ]] && [[ ! "$addr" =~ \. ]]
	}
	ip="$(_fetch_ip_v6 'http://ip.sb')"
	_is_ipv6 "$ip" && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip_v6 'https://api6.ipify.org')"
	_is_ipv6 "$ip" && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip_v6 'https://icanhazip.com')"
	_is_ipv6 "$ip" && {
		echo "$ip"
		return 0
	}
	ip="$(_fetch_ip_v6 'https://v6.ident.me')"
	_is_ipv6 "$ip" && {
		echo "$ip"
		return 0
	}
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
			echo "Error: No supported package manager found (apt, yum, dnf, pacman, apk, brew)"
			echo "Please install $package manually"
			exit 2
		fi
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

# --- Get NetBird status JSON (augmented with _host_public_ip and _host_public_ip_v6) ---
get_netbird_status() {
	local json=""
	local public_ip=""
	local public_ip_v6=""

	# host binary
	if command -v netbird >/dev/null 2>&1; then
		if command -v timeout >/dev/null 2>&1; then
			json=$(timeout "$NETBIRD_TIMEOUT" netbird status --json 2>/dev/null)
		elif command -v gtimeout >/dev/null 2>&1; then
			json=$(gtimeout "$NETBIRD_TIMEOUT" netbird status --json 2>/dev/null)
		else
			json=$(netbird status --json 2>/dev/null)
		fi
		if [[ -n "${json:-}" && "$json" != "null" ]]; then
			public_ip="$(get_public_ip || true)"
			public_ip_v6="$(get_public_ip_v6 || true)"
			echo "$json" | jq \
				--arg public_ip "$public_ip" \
				--arg public_ip_v6 "$public_ip_v6" \
				'. + {"_is_docker": false, "_host_public_ip": $public_ip, "_host_public_ip_v6": $public_ip_v6}'
			return 0
		fi
	fi

	# docker container by image
	if command -v docker >/dev/null 2>&1; then
		local container_id
		container_id=$(docker ps -q --filter "ancestor=netbirdio/netbird:latest" | head -1)
		if [[ -n "$container_id" ]]; then
			if command -v timeout >/dev/null 2>&1; then
				json=$(timeout "$NETBIRD_TIMEOUT" docker exec "$container_id" netbird status --json 2>/dev/null)
			elif command -v gtimeout >/dev/null 2>&1; then
				json=$(gtimeout "$NETBIRD_TIMEOUT" docker exec "$container_id" netbird status --json 2>/dev/null)
			else
				json=$(docker exec "$container_id" netbird status --json 2>/dev/null)
			fi
			if [[ -n "${json:-}" && "$json" != "null" ]]; then
				public_ip="$(get_public_ip || true)"
				public_ip_v6="$(get_public_ip_v6 || true)"
				echo "$json" | jq \
					--arg public_ip "$public_ip" \
					--arg public_ip_v6 "$public_ip_v6" \
					'. + {"_is_docker": true, "_host_public_ip": $public_ip, "_host_public_ip_v6": $public_ip_v6}'
				return 0
			fi
		fi

		# docker container by name
		container_id=$(docker ps -q --filter "name=netbird" | head -1)
		if [[ -n "$container_id" ]]; then
			if command -v timeout >/dev/null 2>&1; then
				json=$(timeout "$NETBIRD_TIMEOUT" docker exec "$container_id" netbird status --json 2>/dev/null)
			elif command -v gtimeout >/dev/null 2>&1; then
				json=$(gtimeout "$NETBIRD_TIMEOUT" docker exec "$container_id" netbird status --json 2>/dev/null)
			else
				json=$(docker exec "$container_id" netbird status --json 2>/dev/null)
			fi
			if [[ -n "${json:-}" && "$json" != "null" ]]; then
				public_ip="$(get_public_ip || true)"
				public_ip_v6="$(get_public_ip_v6 || true)"
				echo "$json" | jq \
					--arg public_ip "$public_ip" \
					--arg public_ip_v6 "$public_ip_v6" \
					'. + {"_is_docker": true, "_host_public_ip": $public_ip, "_host_public_ip_v6": $public_ip_v6}'
				return 0
			fi
		fi
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

# Parse IP:port endpoint, handling both IPv4 and IPv6
# IPv4: "1.2.3.4:51820" -> "1.2.3.4"
# IPv6 bracketed: "[2001:db8::1]:51820" -> "2001:db8::1"
# IPv6 unbracketed: "2001:db8::1" -> "2001:db8::1"
def extract_ip_from_endpoint:
  if . == null or . == "" then ""
  elif startswith("[") then
    # IPv6 bracketed format: [ip]:port
    (split("]")[0] | ltrimstr("["))
  elif test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+:[0-9]+$") then
    # IPv4 format: ip:port
    split(":")[0]
  elif test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$") then
    # IPv4 without port
    .
  else
    # IPv6 without brackets - try to detect last colon as port separator
    # If the string after last : is all digits and <= 5 chars, treat as port
    (. | split(":")) as $parts |
    if ($parts | length) > 1 then
      ($parts[-1]) as $last |
      if ($last | test("^[0-9]{1,5}$")) and (($last | tonumber) <= 65535) then
        # Last part is likely a port, join the rest as IPv6
        ($parts[:-1] | join(":"))
      else
        # No port, entire string is IPv6
        .
      end
    else
      .
    end
  end;

# Check if an IP is IPv4
def is_ipv4:
  if . == null or . == "" then false
  else test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
  end;

# Check if an IP is IPv6
def is_ipv6:
  if . == null or . == "" then false
  elif test("\\.") then false  # Contains dot, not IPv6
  elif test(":") then true     # Contains colon, likely IPv6
  else false
  end;

# Extract self info
(.fqdn) as $self_fqdn |
(.netbirdIp | split("/")[0]) as $self_private_ip |

# Prefer true egress IP if present (added by get_netbird_status); else fall back to srflx/prflx NAT
(._host_public_ip // "") as $egress_ip |
(._host_public_ip_v6 // "") as $egress_ip_v6 |

# Determine self public IPv4
(
  if $egress_ip != "" then
    $egress_ip
  else
    (.peers.details
     | map(select(
         .iceCandidateEndpoint.local != "" and
         ((.iceCandidateType.local // "") | IN("srflx","prflx"))
       ))
     | map(.iceCandidateEndpoint.local | extract_ip_from_endpoint)
     | map(select(is_ipv4))
     | .[0] // "")
  end
) as $self_public_ip |

# Determine self public IPv6
(
  if $egress_ip_v6 != "" then
    $egress_ip_v6
  else
    (.peers.details
     | map(select(
         .iceCandidateEndpoint.local != "" and
         ((.iceCandidateType.local // "") | IN("srflx","prflx"))
       ))
     | map(.iceCandidateEndpoint.local | extract_ip_from_endpoint)
     | map(select(is_ipv6))
     | .[0] // "")
  end
) as $self_public_ip_v6 |

# Build self public endpoint for display
(
  if $self_public_ip != "" then "\($self_public_ip):0" else "" end
) as $self_endpoint_v4 |
(
  if $self_public_ip_v6 != "" then "[\($self_public_ip_v6)]:0" else "" end
) as $self_endpoint_v6 |

# Process all peers including self
(.peers.details + [{
  fqdn: $self_fqdn,
  netbirdIp: .netbirdIp,
  status: "Connected",
  lastStatusUpdate: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  connectionType: "Self",
  iceCandidateEndpoint: {
    remote: $self_endpoint_v4,
    remote_v6: $self_endpoint_v6
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
    if   $d > 0 then "\($d)d" + (if $h>0 then " \($h)h" else "" end) + " ago"
    elif $h > 0 then "\($h)h" + (if $m>0 then " \($m)m" else "" end) + " ago"
    elif $m > 0 then "\($m)m" + (if $s>0 then " \($s)s" else "" end) + " ago"
    else "\($s)s ago" end
  end;

def seen_ago(p):
  (p.lastStatusUpdate // "") as $ls |
  if $ls == "" then "" else try (($now - (parse_time($ls))) | humanize) catch "" end;

# Parse IP:port endpoint, handling both IPv4 and IPv6
def extract_ip_from_endpoint:
  if . == null or . == "" then ""
  elif startswith("[") then
    # IPv6 bracketed format: [ip]:port
    (split("]")[0] | ltrimstr("["))
  elif test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+:[0-9]+$") then
    # IPv4 format: ip:port
    split(":")[0]
  elif test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$") then
    # IPv4 without port
    .
  else
    # IPv6 without brackets
    (. | split(":")) as $parts |
    if ($parts | length) > 1 then
      ($parts[-1]) as $last |
      if ($last | test("^[0-9]{1,5}$")) and (($last | tonumber) <= 65535) then
        ($parts[:-1] | join(":"))
      else
        .
      end
    else
      .
    end
  end;

# Check if an IP is IPv4
def is_ipv4:
  if . == null or . == "" then false
  else test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
  end;

# Check if an IP is IPv6
def is_ipv6:
  if . == null or . == "" then false
  elif test("\\.") then false
  elif test(":") then true
  else false
  end;

# Extract IPv4 from remote endpoint
def get_public_ipv4(p):
  # First try the main remote endpoint
  ((p.iceCandidateEndpoint.remote // "") | extract_ip_from_endpoint) as $ip |
  if ($ip | is_ipv4) then $ip
  else ""
  end;

# Extract IPv6 from remote endpoint
def get_public_ipv6(p):
  # First check if there's a dedicated remote_v6 field (for self)
  ((p.iceCandidateEndpoint.remote_v6 // "") | extract_ip_from_endpoint) as $v6_dedicated |
  if ($v6_dedicated | is_ipv6) then $v6_dedicated
  else
    # Otherwise check if the main remote endpoint is IPv6
    ((p.iceCandidateEndpoint.remote // "") | extract_ip_from_endpoint) as $ip |
    if ($ip | is_ipv6) then $ip
    else ""
    end
  end;

def header: ["No.","NAME","DNS_LABEL","IP","PUBLIC_IP","PUBLIC_IP_V6","CONN","SEEN_AGO","LAST_SEEN"];

def base_row(idx; p):
  [ (idx + 1),
    (p.fqdn // "" | split(".")[0]),
    (p.fqdn//""),
    ((p.netbirdIp//"") | split("/")[0]),
    (get_public_ipv4(p)),
    (get_public_ipv6(p)),
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
    if   $d > 0 then "\($d)d" + (if $h>0 then " \($h)h" else "" end) + " ago"
    elif $h > 0 then "\($h)h" + (if $m>0 then " \($m)m" else "" end) + " ago"
    elif $m > 0 then "\($m)m" + (if $s>0 then " \($s)s" else "" end) + " ago"
    else "\($s)s ago" end
  end;

def seen_ago(p):
  (p.lastStatusUpdate // "") as $ls |
  if $ls == "" then "" else try (($now - (parse_time($ls))) | humanize) catch "" end;

# Parse IP:port endpoint, handling both IPv4 and IPv6
def extract_ip_from_endpoint:
  if . == null or . == "" then ""
  elif startswith("[") then
    (split("]")[0] | ltrimstr("["))
  elif test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+:[0-9]+$") then
    split(":")[0]
  elif test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$") then
    .
  else
    (. | split(":")) as $parts |
    if ($parts | length) > 1 then
      ($parts[-1]) as $last |
      if ($last | test("^[0-9]{1,5}$")) and (($last | tonumber) <= 65535) then
        ($parts[:-1] | join(":"))
      else
        .
      end
    else
      .
    end
  end;

def is_ipv4:
  if . == null or . == "" then false
  else test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
  end;

def is_ipv6:
  if . == null or . == "" then false
  elif test("\\.") then false
  elif test(":") then true
  else false
  end;

def get_public_ipv4(p):
  ((p.iceCandidateEndpoint.remote // "") | extract_ip_from_endpoint) as $ip |
  if ($ip | is_ipv4) then $ip
  else ""
  end;

def get_public_ipv6(p):
  ((p.iceCandidateEndpoint.remote_v6 // "") | extract_ip_from_endpoint) as $v6_dedicated |
  if ($v6_dedicated | is_ipv6) then $v6_dedicated
  else
    ((p.iceCandidateEndpoint.remote // "") | extract_ip_from_endpoint) as $ip |
    if ($ip | is_ipv6) then $ip
    else ""
    end
  end;

to_entries as $rows
|
( ["no","name","dns_label","ip","public_ip","public_ip_v6","connected","seen_ago","last_seen"] | @csv ),
( $rows[] |
  .key as $idx | .value as $p |
  ( [ ($idx+1),
      ($p.fqdn // "" | split(".")[0]),
      ($p.fqdn//""),
      (($p.netbirdIp//"") | split("/")[0]),
      (get_public_ipv4($p)),
      (get_public_ipv6($p)),
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
