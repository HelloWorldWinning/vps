#!/bin/bash
# ==========================================
# IPv6 Multi-Address Auto-Enabler
# ==========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INTERFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
echo -e "${GREEN}Detected Interface: $INTERFACE${NC}"

# --- Step 1: Input ---
echo -e "\n${YELLOW}Paste ALL your IPv6 addresses below.${NC}"
echo "The first one will be the PRIMARY (outgoing) address."
echo "Press ENTER, paste list, then Ctrl+D."
echo "-----------------------------------"

# Read all lines into an array
mapfile -t ALL_IPS

# Remove empty lines
ALL_IPS=("${ALL_IPS[@]}")

# Pick Primary and Gateway
PRIMARY_IP=$(echo "${ALL_IPS[0]}" | xargs)
GATEWAY=$(echo "$PRIMARY_IP" | sed 's/::.*$/::1/')

echo -e "Primary: $PRIMARY_IP"
echo -e "Gateway: $GATEWAY"

# --- Step 2: Write Config ---
echo -e "\n${YELLOW}Writing configuration...${NC}"

cat <<EOF >>/etc/network/interfaces

# IPv6 Multi-IP Configuration
iface $INTERFACE inet6 static
    address $PRIMARY_IP/64
    gateway $GATEWAY
    # Routing fixes
    up ip -6 route add $GATEWAY dev $INTERFACE
    up ip -6 route add default via $GATEWAY dev $INTERFACE
EOF

# Loop through the remaining IPs (skip the first one)
for ((i = 1; i < ${#ALL_IPS[@]}; i++)); do
	CURRENT_IP=$(echo "${ALL_IPS[$i]}" | xargs)
	if [ ! -z "$CURRENT_IP" ]; then
		echo "Adding Alias: $CURRENT_IP"
		echo "    up ip addr add $CURRENT_IP/64 dev $INTERFACE" >>/etc/network/interfaces
	fi
done

# --- Step 3: Apply ---
echo "Restarting Network..."
systemctl restart networking
sleep 2

# --- Step 4: Test ---
# Test the Primary
curl -s -6 --connect-timeout 5 ip.sb
echo "Done."
