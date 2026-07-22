#!/bin/bash

# A robust, interactive script to upload files/folders to a specified API endpoint.
# It prints the NetBird peer list first, lets you pick a peer No.,
# or allows manual destination domain/IP input.
#
# Important:
# - NetBird status JSON is loaded once only, then reused everywhere.
# - The current node is included in the numbered peer table and highlighted.
# - The displayed ordering and peer-number resolution use the exact same cached rows.

# --- Configuration ---
API_PORT="7778"
API_PASSWD="kkb"

# --- Output formatting ---
DELIM_WIDTH=90
NO_COL_W=8
NO_COL_W_TOP=10

STATUS_COL_W=7

# --- Colors for better output ---
BOLD_BLUE=$'\033[1;34m'
BLUE=$'\033[0;34m'

YELLOW=$'\033[0;33m'
BOLD_YELLOW=$'\033[1;33m'

GREEN=$'\033[0;32m'
BOLD_GREEN=$'\033[1;32m'
RED=$'\033[0;31m'
BOLD_RED=$'\033[1;31m'
CYAN=$'\033[0;36m'
BOLD_CYAN=$'\033[1;36m'

# Current-node row: white text on a red background.
#CURRENT_ROW=$'\033[1;37;41m'
CURRENT_ROW=$'\033[1;37;44m'
NC=$'\033[0m'

# --- Cached NetBird status ---
NB_JSON=""
NB_JSON_OK=0
NB_HAS_PEERS=0
NB_ERROR_REASON=""

# Cached, normalized table rows:
# marker<TAB>fqdn<TAB>ip
# marker is CURRENT or PEER.
NB_PEER_ROWS=""

# --- Common delimiter ---
make_delim() {
	local width="${1:-$DELIM_WIDTH}"
	local i

	for ((i = 0; i < width; i++)); do
		printf '─'
	done
}

print_delim() {
	make_delim "${1:-$DELIM_WIDTH}"
	echo
}

sanitize_one_line() {
	printf '%s' "$1" | tr '\r\n\t' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

expand_path() {
	local p="$1"

	case "$p" in
	~)
		printf '%s\n' "$HOME"
		;;
	~/*)
		printf '%s\n' "$HOME/${p#~/}"
		;;
	*)
		printf '%s\n' "$p"
		;;
	esac
}

# Run NetBird status exactly once, cache JSON, and reuse NB_JSON later.
load_netbird_status_once() {
	NB_JSON=""
	NB_JSON_OK=0
	NB_HAS_PEERS=0
	NB_ERROR_REASON=""
	NB_PEER_ROWS=""

	if ! command -v netbird >/dev/null 2>&1; then
		NB_ERROR_REASON="'netbird' is not installed"
		return 1
	fi

	NB_JSON="$(netbird status --json 2>/dev/null || true)"

	if [ -z "$NB_JSON" ]; then
		NB_ERROR_REASON="NetBird returned empty status JSON"
		return 1
	fi

	if ! printf '%s' "$NB_JSON" | jq -e . >/dev/null 2>&1; then
		NB_ERROR_REASON="NetBird returned invalid status JSON"
		return 1
	fi

	NB_JSON_OK=1

	build_nb_peer_rows

	if [ -n "$NB_PEER_ROWS" ]; then
		NB_HAS_PEERS=1
	fi

	return 0
}

# Return the local node's best available FQDN/hostname.
get_current_peer_fqdn() {
	local peer=""

	if [ "$NB_JSON_OK" -eq 1 ]; then
		peer=$(
			printf '%s' "$NB_JSON" | jq -r '
                [
                    .fqdn?,
                    .localPeer.fqdn?,
                    .local_peer.fqdn?,
                    .peer.fqdn?,
                    .hostname?,
                    .hostName?,
                    .localPeer.hostname?,
                    .local_peer.hostname?,
                    .localPeer.name?,
                    .local_peer.name?
                ]
                | map(select(type == "string" and length > 0))
                | .[0] // empty
            '
		)
	fi

	if [ -z "$peer" ]; then
		peer="$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"
	fi

	printf '%s\n' "$peer"
}

# Return the local node's best available NetBird IP.
get_current_peer_ip() {
	local ip=""

	if [ "$NB_JSON_OK" -eq 1 ]; then
		ip=$(
			printf '%s' "$NB_JSON" | jq -r '
                [
                    .netbirdIp?,
                    .netbirdIP?,
                    .ip?,
                    .localPeer.netbirdIp?,
                    .localPeer.netbirdIP?,
                    .localPeer.ip?,
                    .local_peer.netbirdIp?,
                    .local_peer.netbirdIP?,
                    .local_peer.ip?,
                    .peer.netbirdIp?,
                    .peer.netbirdIP?,
                    .peer.ip?
                ]
                | map(select(type == "string" and length > 0))
                | .[0] // empty
            '
		)
	fi

	printf '%s\n' "$ip"
}

get_current_peer() {
	local peer
	peer="$(get_current_peer_fqdn)"
	peer="${peer%%.*}"
	printf '%s\n' "$peer"
}

# Build one normalized, sorted table used by both display and number resolution.
#
# Output stored in NB_PEER_ROWS:
# CURRENT<TAB>fqdn<TAB>ip
# PEER<TAB>fqdn<TAB>ip
#
# The local node is inserted even though NetBird normally omits it from
# .peers.details. Duplicate peer rows are removed.
build_nb_peer_rows() {
	local current_fqdn current_ip current_name remote_rows

	NB_PEER_ROWS=""

	[ "$NB_JSON_OK" -eq 1 ] || return 1

	current_fqdn="$(get_current_peer_fqdn)"
	current_ip="$(get_current_peer_ip)"
	current_name="${current_fqdn%%.*}"

	remote_rows=$(
		printf '%s' "$NB_JSON" | jq -r '
            (.peers.details? // [])
            | .[]
            | [
                (
                    .fqdn?
                    // .hostname?
                    // .hostName?
                    // .name?
                    // empty
                ),
                (
                    .netbirdIp?
                    // .netbirdIP?
                    // .ip?
                    // empty
                )
              ]
            | select(.[0] != "" or .[1] != "")
            | @tsv
        '
	)

	NB_PEER_ROWS=$(
		{
			if [ -n "$current_fqdn" ] || [ -n "$current_ip" ]; then
				printf 'CURRENT\t%s\t%s\n' "$current_fqdn" "$current_ip"
			fi

			if [ -n "$remote_rows" ]; then
				while IFS=$'\t' read -r fqdn ip; do
					[ -n "$fqdn" ] || fqdn="$ip"

					# Do not duplicate the current node if it also appears remotely.
					if { [ -n "$current_ip" ] && [ "$ip" = "$current_ip" ]; } ||
						{ [ -n "$current_fqdn" ] && [ "$fqdn" = "$current_fqdn" ]; } ||
						{ [ -n "$current_name" ] && [ "${fqdn%%.*}" = "$current_name" ]; }; then
						continue
					fi

					printf 'PEER\t%s\t%s\n' "$fqdn" "$ip"
				done <<<"$remote_rows"
			fi
		} | awk -F'\t' '
            BEGIN { OFS = FS }
            !seen[$2 FS $3]++
        ' | sort -t$'\t' -k2,2 -k3,3
	)
}

# --- Function to upload a single file ---
# Writes exactly one TSV result line to the result file:
# index<TAB>STATUS<TAB>source_path<TAB>message_or_saved_path
upload_file() {
	local index="$1"
	local file_path="$2"
	local api_host="$3"
	local result_file="$4"
	local response curl_status saved_path clean_response

	if [ ! -f "$file_path" ]; then
		printf '%s\tSKIP\t%s\t%s\n' "$index" "$file_path" "Not a regular file" >"$result_file"
		return 0
	fi

	response=$(curl -sS -X POST "http://${api_host}:${API_PORT}/?api_passwd=${API_PASSWD}" -F "file=@${file_path}" 2>&1)
	curl_status=$?

	if [ "$curl_status" -ne 0 ]; then
		clean_response=$(sanitize_one_line "$response")
		printf '%s\tFAIL\t%s\t%s\n' "$index" "$file_path" "Curl error: ${clean_response}" >"$result_file"
		return 0
	fi

	if [ -z "$response" ]; then
		printf '%s\tFAIL\t%s\t%s\n' "$index" "$file_path" "Empty reply from server" >"$result_file"
		return 0
	fi

	if printf '%s' "$response" | jq -e '.saved_success == true' >/dev/null 2>&1; then
		saved_path=$(printf '%s' "$response" | jq -r '.path')
		printf '%s\tOK\t%s\t%s\n' "$index" "$file_path" "$saved_path" >"$result_file"
	else
		clean_response=$(sanitize_one_line "$response")
		printf '%s\tFAIL\t%s\t%s\n' "$index" "$file_path" "Server response: ${clean_response}" >"$result_file"
	fi
}

# --- Function to print cached NetBird peer list before selection ---
# Output format: left-padded No., compact dynamic NAME/DNS_LABEL columns, IP.
# The current node appears in the same numbered list with a red background.
print_nb_list() {
	if [ "$NB_JSON_OK" -ne 1 ]; then
		echo -e "${YELLOW}Warning: ${NB_ERROR_REASON}. Please enter destination domain/IP manually.${NC}"
		return 1
	fi

	if [ "$NB_HAS_PEERS" -ne 1 ] || [ -z "$NB_PEER_ROWS" ]; then
		echo -e "${YELLOW}Warning: No NetBird peers found. Please enter destination domain/IP manually.${NC}"
		return 1
	fi

	printf '%s\n' "$NB_PEER_ROWS" | awk -F'\t' \
		-v no_w="$NO_COL_W" \
		-v peer_hi="$BOLD_RED" \
		-v current_hi="$CURRENT_ROW" \
		-v nc="$NC" '
        BEGIN {
            name_w = length("NAME")
            dns_w  = length("DNS_LABEL")
            ip_w   = length("IP")
        }

        NF >= 3 {
            marker = $1
            fqdn   = $2
            ip     = $3
	    sub(/\/.*/, "", ip)
            name   = fqdn
            sub(/\..*/, "", name)

            if (name == "") name = "-"
            if (fqdn == "") fqdn = "-"
            if (ip == "")   ip = "-"

            markers[NR] = marker
            names[NR]   = name
            dns[NR]     = fqdn
            ips[NR]     = ip

            if (length(name) > name_w) name_w = length(name)
            if (length(fqdn) > dns_w) dns_w = length(fqdn)
            if (length(ip)   > ip_w)   ip_w   = length(ip)
        }

        END {
            if (NR == 0) exit

            table_w = 1 + no_w + 2 + name_w + 2 + dns_w + 2 + ip_w

            printf " %*s  %-*s  %-*s  %s\n", no_w, "", name_w, "NAME", dns_w, "DNS_LABEL", "IP"
            for (i = 0; i < table_w; i++) printf "─"
            printf "\n"

            for (i = 1; i <= NR; i++) {
                if (markers[i] == "CURRENT") {
                    # Color the complete current-node row, including padding.
printf " "

printf "%*s", no_w - length(i), ""

printf "%s%d  %-*s  %-*s  %-*s%s\n",
    current_hi,
    i,
    name_w, names[i],
    dns_w, dns[i],
    ip_w, ips[i],
    nc

                } else {
                    printf " %s%*d%s  %s%-*s%s  %-*s  %s\n",
                        peer_hi, no_w, i, nc,
                        peer_hi, name_w, names[i], nc,
                        dns_w, dns[i],
                        ips[i]
                }
            }
        }
    '
}

# --- Function to resolve a peer No. from the cached displayed list ---
# Uses NB_PEER_ROWS directly, so numbering always matches print_nb_list.
resolve_peer_ip() {
	local num="$1"

	if [ "$NB_HAS_PEERS" -ne 1 ] || [ -z "$NB_PEER_ROWS" ]; then
		return 1
	fi

	printf '%s\n' "$NB_PEER_ROWS" |
		awk -F'\t' -v n="$num" 'NR == n { print $2 "\t" $3 }'
}

print_upload_queue() {
	local total="$1"
	local i file

	echo -e "Upload queue (${total} file(s)):${NC}"
	printf " %${NO_COL_W}s  %s\n" "No." "FILE"
	print_delim

	for ((i = 1; i <= total; i++)); do
		file="${upload_files[$((i - 1))]}"
		printf " %${NO_COL_W}d  %s\n" "$i" "$file"
	done

	print_delim
}

print_upload_results() {
	local total="$1"
	local i result_file result_index status path message fail_count skip_count ok_count
	local shown_path path_dir path_base

	fail_count=0
	skip_count=0
	ok_count=0

	echo -e "Upload results:${NC}"
	printf " %${NO_COL_W}s  %-*s  %s\n" "No." "$STATUS_COL_W" "STATUS" "DETAIL"
	print_delim

	for ((i = 1; i <= total; i++)); do
		result_file="${result_files[$i]}"

		if [ -s "$result_file" ]; then
			IFS=$'\t' read -r result_index status path message <"$result_file"
		else
			result_index="$i"
			status="FAIL"
			path="${upload_files[$((i - 1))]}"
			message="Upload job ended without a result"
		fi

		path_base="${path##*/}"
		path_dir="${path%/*}"

		if [ "$path_dir" = "$path" ]; then
			shown_path="${BOLD_RED}${path_base}${NC}"
		else
			shown_path="${path_dir}/${BOLD_RED}${path_base}${NC}"
		fi

		case "$status" in
		OK)
			ok_count=$((ok_count + 1))
			printf " %${NO_COL_W}d  ${BLUE}%-*s${NC}  %b -> ${YELLOW}%s${NC}\n" \
				"$i" "$STATUS_COL_W" "OK" "$shown_path" "$message"
			;;
		SKIP)
			skip_count=$((skip_count + 1))
			printf " %${NO_COL_W}d  ${YELLOW}%-*s${NC}  %b (%s)\n" \
				"$i" "$STATUS_COL_W" "SKIP" "$shown_path" "$message"
			;;
		*)
			fail_count=$((fail_count + 1))
			printf " %${NO_COL_W}d  ${RED}%-*s${NC}  %b (%s)\n" \
				"$i" "$STATUS_COL_W" "❌" "$shown_path" "$message"
			;;
		esac
	done

	print_delim

	if [ "$fail_count" -eq 0 ] && [ "$skip_count" -eq 0 ]; then
		echo -e "${BLUE}All tasks finished successfully. Uploaded: ${ok_count}/${total}.${NC}"
	elif [ "$fail_count" -eq 0 ]; then
		echo -e "${YELLOW}All tasks finished. Uploaded: ${ok_count}/${total}. Skipped: ${skip_count}.${NC}"
	else
		echo -e "${RED}All tasks finished with problems. Uploaded: ${ok_count}/${total}. Failed: ${fail_count}. Skipped: ${skip_count}.${NC}"
	fi

	return "$fail_count"
}

# --- Main Script Logic ---

# Detect OS
OS=""
if [ -f /etc/debian_version ]; then
	OS=$(lsb_release -si 2>/dev/null || grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
fi

# Debian branch
if [ "$OS" = "Debian" ]; then
	if ! command -v nc >/dev/null 2>&1; then
		apt-get install -y netcat-openbsd
	fi
	if ! command -v jq >/dev/null 2>&1; then
		apt-get install -y jq
	fi

# Ubuntu branch
elif [ "$OS" = "Ubuntu" ]; then
	if ! command -v nc >/dev/null 2>&1; then
		apt-get install -y netcat-openbsd
	fi
	if ! command -v jq >/dev/null 2>&1; then
		apt-get install -y jq
	fi
fi

# 1. Check for dependencies
command -v curl >/dev/null 2>&1 || {
	echo >&2 -e "${RED}Error: 'curl' is not installed.${NC}"
	exit 1
}
command -v jq >/dev/null 2>&1 || {
	echo >&2 -e "${RED}Error: 'jq' is not installed.${NC}"
	exit 1
}
command -v nc >/dev/null 2>&1 || {
	echo >&2 -e "${RED}Error: 'nc' (netcat) is not installed. It is required for the server health check.${NC}"
	exit 1
}

# Cache NetBird once. Manual destination input still works when this fails.
load_netbird_status_once

# === Step 1: Get Target Server and Check Connectivity ===
echo -e "Step 1: Target Server${NC}"
print_delim

print_nb_list
print_delim

read -r -p "Number/Domain/IP: " API_HOST

if [ -z "${API_HOST}" ]; then
	echo -e "${RED}Error: Peer No., domain, or IP is required.${NC}"
	exit 1
fi

# --- Lazy input ---
# If the entry is a 1-3 digit number, treat it as a peer No. from the printed cached NetBird list.
# Anything else, such as real IP, hostname, or domain, falls through to manual host behavior.
if [[ "${API_HOST}" =~ ^[0-9]{1,3}$ ]]; then
	peer_no="${API_HOST}"

	if [ "$NB_HAS_PEERS" -ne 1 ]; then
		echo -e "${RED}Error: a peer No. ('${peer_no}') was entered, but no cached NetBird peer list is available.${NC}"
		exit 1
	fi

	peer_line=$(resolve_peer_ip "${peer_no}")

	if [ -z "${peer_line}" ]; then
		echo -e "${RED}Error: no peer found with No. ${peer_no} in the NetBird list.${NC}"
		exit 1
	fi

	peer_fqdn="${peer_line%%$'\t'*}"
	API_HOST="${peer_line##*$'\t'}"
	peer_name="${peer_fqdn%%.*}"

	if [ -z "$API_HOST" ] || [ "$API_HOST" = "-" ]; then
		echo -e "${RED}Error: peer No. ${peer_no} ('${peer_name}') has no usable NetBird IP.${NC}"
		exit 1
	fi

	print_delim
	echo -e "${BOLD_RED}  ${peer_no}  ${peer_name}  ->  ${API_HOST}${NC}"
	print_delim
fi

echo "Checking server connectivity..."
if ! nc -z -w 5 "$API_HOST" "$API_PORT"; then
	echo -e "${RED}Error: Server '${API_HOST}' is not reachable on port '${API_PORT}'. Please check the address and ensure the service is running.${NC}"
	exit 1
fi

print_delim
echo -e "${BOLD_RED}  online  ${API_HOST}${NC}"
print_delim

# === Step 2: Collect All File/Folder Paths ===
echo -e "Step 2: Files and Folders to Upload${NC}"
echo -e "Enter one file/folder path per line. \nPress ENTER on an empty line when you are done."
print_delim

declare -a all_items=()
while IFS= read -r item; do
	[ -z "$item" ] && break
	all_items+=("$item")
done

if [ "${#all_items[@]}" -eq 0 ]; then
	echo -e "${RED}Error: No paths were entered.${NC}"
	exit 1
fi

# === Step 3: Build Upload Queue ===
echo -e "Processing ${#all_items[@]} item(s)...${NC}"
print_delim

declare -a upload_files=()

for item in "${all_items[@]}"; do
	item_expanded=$(expand_path "$item")

	if [ -f "${item_expanded}" ]; then
		upload_files+=("${item_expanded}")

	elif [ -d "${item_expanded}" ]; then
		echo -e "Scanning directory:${NC} ${item_expanded}"

		while IFS= read -r -d $'\0' file; do
			upload_files+=("$file")
		done < <(find "${item_expanded}" -type f -print0)

	else
		echo -e "${YELLOW}Warning: '${item}' is not a valid file or directory. Skipping.${NC}"
	fi
done

if [ "${#upload_files[@]}" -eq 0 ]; then
	echo -e "${RED}Error: No valid files were found in the provided paths.${NC}"
	exit 1
fi

print_upload_queue "${#upload_files[@]}"

# === Step 4: Upload All Queued Files ===
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

declare -a pids=()
declare -a result_files=()

total_uploads="${#upload_files[@]}"

echo -e "Uploading ${total_uploads} file(s) in parallel...${NC}"
print_delim

for ((i = 1; i <= total_uploads; i++)); do
	file="${upload_files[$((i - 1))]}"
	result_file="${tmp_dir}/result_${i}.tsv"
	result_files[$i]="$result_file"

	upload_file "$i" "$file" "$API_HOST" "$result_file" &
	pids[$i]=$!
done

for ((i = 1; i <= total_uploads; i++)); do
	wait "${pids[$i]}" 2>/dev/null || true
done

print_upload_results "$total_uploads"
exit_code=$?

exit "$exit_code"
