#!/bin/bash

# ============================================================
# REALITY DESTINATION SCANNER v2
# Logic: Filter Features FIRST -> Then Ping Survivors
# ============================================================

# --- CONFIGURATION ---
RTT_THRESHOLD=15.0 # Increased slightly to ensure you get results for testing
JITTER_THRESHOLD=10.0
PING_COUNT=4

# --- THE LIST ---
DOMAINS=(
	"www.cloudflare.com"
	"www.apple.com"
	"www.microsoft.com"
	"www.amazon.com"
	"www.google.com"
	"www.ibm.com"
	"www.oracle.com"
	"www.cisco.com"
	"www.salesforce.com"
	"www.dropbox.com"
	"www.shopify.com"
	"www.nvidia.com"
	"www.qualcomm.com"
	"www.tesla.com"
	"www.costco.com"
	"www.walmart.com"
	"www.bestbuy.com"
	"www.target.com"
	"www.nike.com"
	"www.pepsi.com"
	"dl.google.com"
	"developers.google.com"
	"azure.microsoft.com"
	"aws.amazon.com"
)

# --- COLORS ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GREY='\033[0;90m'
NC='\033[0m'

command -v openssl >/dev/null 2>&1 || {
	echo "Error: openssl required."
	exit 1
}
command -v bc >/dev/null 2>&1 || {
	echo "Error: bc required."
	exit 1
}

echo -e "${CYAN}Starting Scanner...${NC}"
echo "1. Filter by TLS 1.3 + H2 + OCSP"
echo "2. Ping survivors (Avg < ${RTT_THRESHOLD}ms, Jitter < ${JITTER_THRESHOLD}ms)"
echo "----------------------------------------------------------------------"
printf "%-25s | %-6s | %-6s | %-6s | %-15s | %-6s\n" "Domain" "TLS1.3" "H2" "OCSP" "RTT / Jitter" "SCORE"
echo "----------------------------------------------------------------------"

results=()

for domain in "${DOMAINS[@]}"; do

	# 1. CHECK TLS 1.3
	if ! openssl s_client -connect "$domain":443 -tls1_3 </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
		# printf "%-25s | ${GREY}NO (Skip)${NC}\n" "$domain"
		continue
	fi

	# 2. CHECK H2
	if ! openssl s_client -connect "$domain":443 -alpn h2 </dev/null 2>/dev/null | grep -q "ALPN protocol: h2"; then
		# printf "%-25s | ${GREEN}YES${NC}    | ${GREY}NO (Skip)${NC}\n" "$domain"
		continue
	fi

	# 3. CHECK OCSP
	if ! openssl s_client -connect "$domain":443 -status </dev/null 2>/dev/null | grep -q "OCSP Response Status: successful"; then
		# printf "%-25s | ${GREEN}YES${NC}    | ${GREEN}YES${NC}    | ${GREY}NO (Skip)${NC}\n" "$domain"
		continue
	fi

	# 4. MEASURE PING (Only if above passed)
	ping_out=$(ping -c $PING_COUNT -q "$domain" 2>/dev/null)

	# Robust Parsing: Find the line with "min/avg/max", strip everything before "=", strip " ms"
	stats_line=$(echo "$ping_out" | grep "min/avg/max" | tail -n 1)

	if [ -z "$stats_line" ]; then
		continue
	fi

	# Extract numbers string (e.g., "1.1/2.2/3.3/0.4")
	# sed command removes "rtt min/avg/max/mdev =" and " ms"
	nums=$(echo "$stats_line" | sed -E 's/.*= //; s/ ms//')

	# Get Avg (2nd item) and Jitter (4th item)
	avg_rtt=$(echo "$nums" | awk -F '/' '{print $2}')
	jitter=$(echo "$nums" | awk -F '/' '{print $4}')

	# Validate numbers exist
	if [ -z "$avg_rtt" ] || [ -z "$jitter" ]; then continue; fi

	# 5. FILTER & SCORE
	rtt_pass=$(echo "$avg_rtt < $RTT_THRESHOLD" | bc -l)
	jitter_pass=$(echo "$jitter < $JITTER_THRESHOLD" | bc -l)

	if [ "$rtt_pass" -eq 1 ] && [ "$jitter_pass" -eq 1 ]; then
		score=$(echo "$avg_rtt + (2 * $jitter)" | bc -l)

		printf "%-25s | ${GREEN}YES${NC}    | ${GREEN}YES${NC}    | ${GREEN}YES${NC}    | %-6s / %-6s | ${CYAN}%-6s${NC}\n" "$domain" "$avg_rtt" "$jitter" "$score"
		results+=("$score|$domain|$avg_rtt|$jitter")
	fi

done

echo "----------------------------------------------------------------------"
echo -e "${GREEN}BEST REALITY DESTINATIONS${NC}"
echo "----------------------------------------------------------------------"

if [ ${#results[@]} -gt 0 ]; then
	# Sort by Score
	IFS=$'\n' sorted=($(sort -n -t '|' -k1 <<<"${results[*]}"))
	unset IFS

	# Print Top 3
	for entry in "${sorted[@]}"; do
		s=$(echo "$entry" | cut -d'|' -f1)
		d=$(echo "$entry" | cut -d'|' -f2)
		r=$(echo "$entry" | cut -d'|' -f3)
		j=$(echo "$entry" | cut -d'|' -f4)
		printf "Score: ${CYAN}%-6s${NC} Domain: ${YELLOW}%-25s${NC} (RTT: %s, Jitter: %s)\n" "$s" "$d" "$r" "$j"
	done

	echo ""
	top_domain=$(echo "${sorted[0]}" | cut -d'|' -f2)
	echo ">> WINNER Config: \"dest\": \"$top_domain:443\", \"serverNames\": [\"$top_domain\"]"
else
	echo "No domains met the strict < ${RTT_THRESHOLD}ms criteria."
fi
