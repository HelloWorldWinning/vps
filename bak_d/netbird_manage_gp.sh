#!/bin/bash

#=============================================================================
# NetBird Peer Manager
# A comprehensive tool to manage NetBird peers via API
#=============================================================================

# Configuration
TOKEN="nbp_hTzNjw5EuwEOAo1Ph0OMinRhINwDtj0DsTGs"
LAST_SEEN_TIMEZONE="Asia/Shanghai"
API_BASE="https://api.netbird.io/api"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#=============================================================================
# Utility Functions
#=============================================================================

# Calculate time ago from ISO timestamp
calculate_seen_ago() {
	local last_seen="$1"
	local now_ts=$(date +%s)
	local seen_ts=$(date -d "$last_seen" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${last_seen%%.*}" +%s 2>/dev/null)

	if [[ -z "$seen_ts" ]]; then
		echo "N/A"
		return
	fi

	local diff=$((now_ts - seen_ts))

	if [[ $diff -lt 60 ]]; then
		echo "${diff}s ago"
	elif [[ $diff -lt 3600 ]]; then
		echo "$((diff / 60))m ago"
	elif [[ $diff -lt 86400 ]]; then
		local hours=$((diff / 3600))
		local mins=$(((diff % 3600) / 60))
		echo "${hours}h ${mins}m ago"
	else
		local days=$((diff / 86400))
		local hours=$(((diff % 86400) / 3600))
		echo "${days}d ${hours}h ago"
	fi
}

# Convert UTC to configured timezone
convert_timezone() {
	local utc_time="$1"
	TZ="$LAST_SEEN_TIMEZONE" date -d "$utc_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null ||
		TZ="$LAST_SEEN_TIMEZONE" date -j -f "%Y-%m-%dT%H:%M:%S" "${utc_time%%.*}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null ||
		echo "${utc_time:0:19}"
}

# Print separator line
print_separator() {
	local width=$1
	printf "${CYAN}"
	printf '─%.0s' $(seq 1 $width)
	printf "${NC}\n"
}

# Check dependencies
check_dependencies() {
	local missing=()
	for cmd in curl jq; do
		if ! command -v $cmd &>/dev/null; then
			missing+=($cmd)
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}"
		echo "Please install them first."
		exit 1
	fi
}

#=============================================================================
# API Functions
#=============================================================================

# Fetch all peers from API
fetch_peers() {
	local response
	response=$(curl -s -X GET "${API_BASE}/peers" \
		-H "Accept: application/json" \
		-H "Authorization: Token ${TOKEN}" 2>&1)

	if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
		echo -e "${RED}Error: Failed to fetch peers from API${NC}"
		exit 1
	fi

	# Check if response is valid JSON
	if ! echo "$response" | jq empty 2>/dev/null; then
		echo -e "${RED}Error: Invalid response from API${NC}"
		echo "$response"
		exit 1
	fi

	echo "$response"
}

# Update peer
update_peer() {
	local peer_id="$1"
	local data="$2"

	local response
	response=$(curl -s -X PUT "${API_BASE}/peers/${peer_id}" \
		-H "Accept: application/json" \
		-H "Content-Type: application/json" \
		-H "Authorization: Token ${TOKEN}" \
		--data-raw "$data" 2>&1)

	echo "$response"
}

# Delete peer
delete_peer() {
	local peer_id="$1"

	curl -s -X DELETE "${API_BASE}/peers/${peer_id}" \
		-H "Authorization: Token ${TOKEN}"

	return $?
}

#=============================================================================
# Display Functions
#=============================================================================

# Display peers table
display_peers_table() {
	local peers_json="$1"

	echo ""
	echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
	echo -e "${BOLD}${BLUE}║                                                   NETBIRD PEER MANAGER                                                                                               ║${NC}"
	echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
	echo ""
	echo -e "${YELLOW}Timezone: ${LAST_SEEN_TIMEZONE}${NC}"
	echo ""

	# Table header
	# Removed KERNEL column
	printf "${BOLD}${GREEN}%-4s %-18s %-22s %-14s %-42s %-5s %-12s %-12s %-4s %-8s %-12s %-20s %s${NC}\n" \
		"No." "NAME" "DNS_LABEL" "PRIVATE_IP" "PUBLIC_IP" "CONN" "OS" "CITY" "CC" "VERSION" "SEEN_AGO" "LAST_SEEN" "GROUPS"
	print_separator 205

	# Parse and display each peer
	local count=0
	local peer_ids=()

	# Sorting logic added here: jq 'sort_by(.dns_label // "")'
	while IFS= read -r peer; do
		count=$((count + 1))

		local id=$(echo "$peer" | jq -r '.id')
		local name=$(echo "$peer" | jq -r '.name // "N/A"')
		local dns_label=$(echo "$peer" | jq -r '.dns_label // "N/A"')
		local ip=$(echo "$peer" | jq -r '.ip // "N/A"')
		local connection_ip=$(echo "$peer" | jq -r '.connection_ip // "N/A"')
		local connected=$(echo "$peer" | jq -r '.connected')
		local os=$(echo "$peer" | jq -r '.os // "N/A"' | cut -d' ' -f1)
		local city=$(echo "$peer" | jq -r '.city_name // "N/A"')
		local country_code=$(echo "$peer" | jq -r '.country_code // "N/A"')
		local version=$(echo "$peer" | jq -r '.version // "N/A"')
		# Kernel removed
		local last_seen=$(echo "$peer" | jq -r '.last_seen // "N/A"')
		local groups=$(echo "$peer" | jq -r '[.groups[].name] | join(",")')

		# Store peer ID for later use
		peer_ids+=("$id")

		# Connection status indicator
		local conn_status
		if [[ "$connected" == "true" ]]; then
			conn_status="${GREEN}✓${NC}    "
		else
			conn_status="${RED}✗${NC}    "
		fi

		# Calculate seen ago
		local seen_ago=$(calculate_seen_ago "$last_seen")

		# Convert last_seen to configured timezone
		local last_seen_local=$(convert_timezone "$last_seen")

		# Truncate long fields
		[[ ${#name} -gt 16 ]] && name="${name:0:15}…"
		[[ ${#dns_label} -gt 20 ]] && dns_label="${dns_label:0:19}…"
		[[ ${#os} -gt 10 ]] && os="${os:0:9}…"
		[[ ${#city} -gt 10 ]] && city="${city:0:9}…"
		[[ ${#groups} -gt 25 ]] && groups="${groups:0:24}…"

		# Handle empty city
		[[ -z "$city" || "$city" == "null" ]] && city="-"

		# Removed kernel field from printf
		printf "%-4s %-18s %-22s %-14s %-42s %b %-12s %-12s %-4s %-8s %-12s %-20s %s\n" \
			"$count" "$name" "$dns_label" "$ip" "$connection_ip" "$conn_status" "$os" "$city" "$country_code" "$version" "$seen_ago" "$last_seen_local" "$groups"
		print_separator 205

	done < <(echo "$peers_json" | jq -c 'sort_by(.dns_label // "") | .[]')

	echo ""
	echo -e "${CYAN}Total peers: ${count}${NC}"
	echo ""

	# Store peer IDs in a global array
	PEER_IDS=("${peer_ids[@]}")
	PEER_COUNT=$count
}

#=============================================================================
# Interactive Menu Functions
#=============================================================================

# Get peer details by index (Updated to respect sort order)
get_peer_by_index() {
	local peers_json="$1"
	local index="$2"

	# We must apply the same sort logic here to ensure indices match
	echo "$peers_json" | jq -c "sort_by(.dns_label // \"\") | .[$((index - 1))]"
}

# Show peer details
show_peer_details() {
	local peer="$1"

	echo ""
	echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
	echo -e "${BOLD}${BLUE}                      PEER DETAILS                             ${NC}"
	echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
	echo ""
	echo -e "${CYAN}ID:${NC}              $(echo "$peer" | jq -r '.id')"
	echo -e "${CYAN}Name:${NC}            $(echo "$peer" | jq -r '.name')"
	echo -e "${CYAN}DNS Label:${NC}       $(echo "$peer" | jq -r '.dns_label')"
	echo -e "${CYAN}Private IP:${NC}      $(echo "$peer" | jq -r '.ip')"
	echo -e "${CYAN}Public IP:${NC}       $(echo "$peer" | jq -r '.connection_ip')"
	echo -e "${CYAN}Hostname:${NC}        $(echo "$peer" | jq -r '.hostname')"
	echo -e "${CYAN}OS:${NC}              $(echo "$peer" | jq -r '.os')"
	echo -e "${CYAN}Kernel:${NC}          $(echo "$peer" | jq -r '.kernel_version')"
	echo -e "${CYAN}Version:${NC}         $(echo "$peer" | jq -r '.version')"
	echo -e "${CYAN}Connected:${NC}       $(echo "$peer" | jq -r '.connected')"
	echo -e "${CYAN}City:${NC}            $(echo "$peer" | jq -r '.city_name')"
	echo -e "${CYAN}Country:${NC}         $(echo "$peer" | jq -r '.country_code')"
	echo -e "${CYAN}Groups:${NC}          $(echo "$peer" | jq -r '[.groups[].name] | join(", ")')"
	echo -e "${CYAN}SSH Enabled:${NC}     $(echo "$peer" | jq -r '.ssh_enabled')"
	echo -e "${CYAN}Serial Number:${NC}   $(echo "$peer" | jq -r '.serial_number')"
	echo ""
}

# Peer action menu
peer_action_menu() {
	local peers_json="$1"
	local peer_index="$2"
	local peer=$(get_peer_by_index "$peers_json" "$peer_index")
	local peer_id=$(echo "$peer" | jq -r '.id')
	local peer_name=$(echo "$peer" | jq -r '.name')

	show_peer_details "$peer"

	while true; do
		echo -e "${BOLD}${YELLOW}Actions for peer: ${peer_name}${NC}"
		echo ""
		echo -e "  ${GREEN}1)${NC} Reset Name"
		echo -e "  ${GREEN}2)${NC} Reset DNS Label (requires name change)"
		echo -e "  ${GREEN}3)${NC} Reset Private IP"
		echo -e "  ${RED}4)${NC} Delete Peer"
		echo -e "  ${BLUE}5)${NC} Back to peer list"
		echo ""
		read -p "Select action [1-5]: " action

		case $action in
		1)
			reset_peer_name "$peers_json" "$peer_index"
			;;
		2)
			echo -e "${YELLOW}Note: DNS label is auto-generated from the hostname.${NC}"
			echo -e "${YELLOW}To change DNS label, you need to change the peer name.${NC}"
			reset_peer_name "$peers_json" "$peer_index"
			;;
		3)
			reset_peer_ip "$peers_json" "$peer_index"
			;;
		4)
			delete_peer_interactive "$peers_json" "$peer_index"
			return 0
			;;
		5)
			return 0
			;;
		*)
			echo -e "${RED}Invalid option. Please try again.${NC}"
			;;
		esac
	done
}

# Reset peer name
reset_peer_name() {
	local peers_json="$1"
	local peer_index="$2"
	local peer=$(get_peer_by_index "$peers_json" "$peer_index")
	local peer_id=$(echo "$peer" | jq -r '.id')
	local current_name=$(echo "$peer" | jq -r '.name')
	local ssh_enabled=$(echo "$peer" | jq -r '.ssh_enabled')
	local login_exp=$(echo "$peer" | jq -r '.login_expiration_enabled')
	local inactivity_exp=$(echo "$peer" | jq -r '.inactivity_expiration_enabled')

	echo ""
	echo -e "${CYAN}Current name: ${current_name}${NC}"
	read -p "Enter new name (or press Enter to cancel): " new_name

	if [[ -z "$new_name" ]]; then
		echo -e "${YELLOW}Operation cancelled.${NC}"
		return
	fi

	echo ""
	echo -e "${YELLOW}Updating peer name to: ${new_name}${NC}"

	local data=$(jq -n \
		--arg name "$new_name" \
		--argjson ssh "$ssh_enabled" \
		--argjson login "$login_exp" \
		--argjson inactivity "$inactivity_exp" \
		'{name: $name, ssh_enabled: $ssh, login_expiration_enabled: $login, inactivity_expiration_enabled: $inactivity}')

	local response=$(update_peer "$peer_id" "$data")

	if echo "$response" | jq -e '.id' &>/dev/null; then
		echo -e "${GREEN}✓ Peer name updated successfully!${NC}"
		echo -e "${CYAN}New DNS Label: $(echo "$response" | jq -r '.dns_label')${NC}"
	else
		echo -e "${RED}✗ Failed to update peer name.${NC}"
		echo "$response" | jq -r '.message // .'
	fi
	echo ""
}

# Reset peer IP
reset_peer_ip() {
	local peers_json="$1"
	local peer_index="$2"
	local peer=$(get_peer_by_index "$peers_json" "$peer_index")
	local peer_id=$(echo "$peer" | jq -r '.id')
	local peer_name=$(echo "$peer" | jq -r '.name')
	local current_ip=$(echo "$peer" | jq -r '.ip')
	local ssh_enabled=$(echo "$peer" | jq -r '.ssh_enabled')
	local login_exp=$(echo "$peer" | jq -r '.login_expiration_enabled')
	local inactivity_exp=$(echo "$peer" | jq -r '.inactivity_expiration_enabled')

	echo ""
	echo -e "${CYAN}Current private IP: ${current_ip}${NC}"
	echo -e "${YELLOW}Note: IP must be in the 100.x.x.x range${NC}"
	read -p "Enter new IP (or press Enter to cancel): " new_ip

	if [[ -z "$new_ip" ]]; then
		echo -e "${YELLOW}Operation cancelled.${NC}"
		return
	fi

	# Basic IP validation
	if ! [[ "$new_ip" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo -e "${RED}Invalid IP format. Must be in 100.x.x.x range.${NC}"
		return
	fi

	echo ""
	echo -e "${YELLOW}Updating peer IP to: ${new_ip}${NC}"

	local data=$(jq -n \
		--arg name "$peer_name" \
		--arg ip "$new_ip" \
		--argjson ssh "$ssh_enabled" \
		--argjson login "$login_exp" \
		--argjson inactivity "$inactivity_exp" \
		'{name: $name, ip: $ip, ssh_enabled: $ssh, login_expiration_enabled: $login, inactivity_expiration_enabled: $inactivity}')

	local response=$(update_peer "$peer_id" "$data")

	if echo "$response" | jq -e '.id' &>/dev/null; then
		echo -e "${GREEN}✓ Peer IP updated successfully!${NC}"
		echo -e "${CYAN}New IP: $(echo "$response" | jq -r '.ip')${NC}"
	else
		echo -e "${RED}✗ Failed to update peer IP.${NC}"
		echo "$response" | jq -r '.message // .'
	fi
	echo ""
}

# Delete peer interactively
delete_peer_interactive() {
	local peers_json="$1"
	local peer_index="$2"
	local peer=$(get_peer_by_index "$peers_json" "$peer_index")
	local peer_id=$(echo "$peer" | jq -r '.id')
	local peer_name=$(echo "$peer" | jq -r '.name')

	echo ""
	echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
	echo -e "${RED}                     ⚠️  WARNING: DELETE PEER                     ${NC}"
	echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
	echo ""
	echo -e "${YELLOW}You are about to delete peer: ${BOLD}${peer_name}${NC}"
	echo -e "${YELLOW}Peer ID: ${peer_id}${NC}"
	echo ""
	echo -e "${RED}This action cannot be undone!${NC}"
	echo ""
	read -p "Type 'DELETE' to confirm deletion: " confirm

	if [[ "$confirm" == "DELETE" ]]; then
		echo ""
		echo -e "${YELLOW}Deleting peer...${NC}"

		if delete_peer "$peer_id"; then
			echo -e "${GREEN}✓ Peer deleted successfully!${NC}"
		else
			echo -e "${RED}✗ Failed to delete peer.${NC}"
		fi
	else
		echo -e "${YELLOW}Operation cancelled.${NC}"
	fi
	echo ""
}

#=============================================================================
# Main Function
#=============================================================================

main() {
	clear
	check_dependencies

	while true; do
		# Fetch peers
		echo -e "${CYAN}Fetching peers from NetBird API...${NC}"
		local peers_json=$(fetch_peers)

		# Display table
		clear
		display_peers_table "$peers_json"

		# Interactive menu
		echo -e "${BOLD}${YELLOW}Options:${NC}"
		echo -e "  ${GREEN}Enter peer number (1-${PEER_COUNT})${NC} to manage that peer"
		echo -e "  ${BLUE}r${NC} - Refresh peer list"
		echo -e "  ${RED}q${NC} - Quit"
		echo ""
		read -p "Select option: " selection

		case $selection in
		r | R)
			echo -e "${CYAN}Refreshing...${NC}"
			continue
			;;
		q | Q)
			echo -e "${GREEN}Goodbye!${NC}"
			exit 0
			;;
		'' | *[!0-9]*)
			echo -e "${RED}Invalid input. Please enter a number or 'r'/'q'.${NC}"
			sleep 1
			continue
			;;
		*)
			if [[ $selection -ge 1 && $selection -le $PEER_COUNT ]]; then
				peer_action_menu "$peers_json" "$selection"
			else
				echo -e "${RED}Invalid peer number. Please enter a number between 1 and ${PEER_COUNT}.${NC}"
				sleep 1
			fi
			;;
		esac
	done
}

# Run main function
main "$@"
