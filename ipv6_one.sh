#!/bin/bash

# ==========================================
# IPv6 Auto-Enabler for Debian/Ubuntu VPS
# ==========================================

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for root
if [ "$EUID" -ne 0 ]; then
	echo -e "${RED}Please run as root.${NC}"
	exit 1
fi

# Detect Primary Interface
INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
if [ -z "$INTERFACE" ]; then
	echo -e "${RED}Could not detect primary network interface. Exiting.${NC}"
	exit 1
fi

echo -e "${GREEN}Detected Interface: $INTERFACE${NC}"

# ==========================================
# STEP 0: BACKUP
# ==========================================
echo -e "\n${YELLOW}--- Step 0: Backing up interfaces file ---${NC}"
cp /etc/network/interfaces /etc/network/interfaces.bak
echo "Backup created at /etc/network/interfaces.bak"

# ==========================================
# STEP 1: GET IPv6 DATA & CALCULATE GATEWAY
# ==========================================
echo -e "\n${YELLOW}--- Step 1: Input IPv6 Address ---${NC}"
echo "Please paste the IPv6 address(es) provided by your VPS provider."
echo "If you paste multiple lines, the first one will be used as the primary address."
echo "Press ENTER, paste your IPs, then press Ctrl+D to finish."
echo "-----------------------------------"

# Read multi-line input
IPV6_INPUT=$(cat)

# Extract the first valid non-empty line
IPV6_ADDR=$(echo "$IPV6_INPUT" | grep -v '^\s*$' | head -n1 | xargs)

if [ -z "$IPV6_ADDR" ]; then
	echo -e "${RED}No IP address provided. Exiting.${NC}"
	exit 1
fi

echo -e "${GREEN}Selected Primary IPv6: $IPV6_ADDR${NC}"

# Robust Gateway Calculation (Heuristic: Assume Gateway is ::1 of the subnet)
# Logic: Take the part before the last colon or the double colon and append 1
# This works for 2403:5680::1:6536 -> 2403:5680::1
IPV6_GATEWAY=$(echo "$IPV6_ADDR" | sed 's/::.*$/::1/')

echo -e "Calculated Gateway: ${YELLOW}$IPV6_GATEWAY${NC}"
read -p "Is this gateway correct? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	read -p "Please enter the correct Gateway IP: " IPV6_GATEWAY
fi

# ==========================================
# STEP 2: APPLY CONFIG & TEST
# ==========================================
echo -e "\n${YELLOW}--- Step 2: Applying Configuration ---${NC}"

# Append config to interfaces file
cat <<EOF >>/etc/network/interfaces

# IPv6 Configuration (Added by script)
iface $INTERFACE inet6 static
    address $IPV6_ADDR/64
    gateway $IPV6_GATEWAY
    # Robust routing for VPS
    up ip -6 route add $IPV6_GATEWAY dev $INTERFACE
    up ip -6 route add default via $IPV6_GATEWAY dev $INTERFACE
EOF

echo "Restarting networking service..."
systemctl restart networking

echo "Testing connectivity (Wait 3s)..."
sleep 3

# Test 1: Ping Google
if ping6 -c 3 google.com >/dev/null 2>&1; then
	PING_SUCCESS=true
else
	PING_SUCCESS=false
fi

# Test 2: Curl IP.sb
CURL_RESULT=$(curl -s -6 --connect-timeout 5 ip.sb)
if [[ "$CURL_RESULT" == *":"* ]]; then
	CURL_SUCCESS=true
else
	CURL_SUCCESS=false
fi

# ==========================================
# STEP 3: SUCCESS OR ROLLBACK
# ==========================================
echo -e "\n${YELLOW}--- Step 3: Result Analysis ---${NC}"

if [ "$PING_SUCCESS" = true ] || [ "$CURL_SUCCESS" = true ]; then
	echo -e "${GREEN}SUCCESS! IPv6 is enabled and working.${NC}"
	echo -e "Ping Result: ${GREEN}PASS${NC}"
	echo -e "Public IP:   ${GREEN}$CURL_RESULT${NC}"

	# Optional: Clean up backup if you want, usually better to keep it
	# rm /etc/network/interfaces.bak
else
	echo -e "${RED}FAILURE: IPv6 connectivity could not be established.${NC}"
	echo "Reverting changes..."

	# Rollback
	cp /etc/network/interfaces.bak /etc/network/interfaces
	systemctl restart networking

	echo -e "${GREEN}System reverted to IPv4-only state. Network is safe.${NC}"

	# Create Suggestion File
	SUGGESTION_FILE="ipv6_suggestion_manual.txt"
	cat <<EOF >$SUGGESTION_FILE
# IPv6 Configuration Suggestion
# The script failed to auto-enable IPv6. 
# Try adding this block manually to /etc/network/interfaces:

iface $INTERFACE inet6 static
    address $IPV6_ADDR/64
    gateway $IPV6_GATEWAY
    up ip -6 route add $IPV6_GATEWAY dev $INTERFACE
    up ip -6 route add default via $IPV6_GATEWAY dev $INTERFACE

# Note: Double check if your netmask is /64 or /48 with your provider.
EOF

	echo -e "${YELLOW}I have created a suggestion file for you to review: ./$SUGGESTION_FILE${NC}"
fi
