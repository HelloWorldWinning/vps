#!/bin/bash

# ==============================================================================
# GCP IPv6 Migration Script (Official Netplan Method)
# ==============================================================================
# 1. Backs up /etc/network/interfaces
# 2. Installs Netplan
# 3. Configures Netplan with GCP Official Dual-Stack settings
# 4. Verifies Connectivity (IPv4 & IPv6)
# 5. AUTOMATIC ROLLBACK if verification fails
# ==============================================================================

# Variables
INTERFACES_FILE="/etc/network/interfaces"
BACKUP_FILE="/etc/network/interfaces.bak"
NETPLAN_FILE="/etc/netplan/90-gcp-default.yaml"
LOG_FILE="/var/log/v6_migration.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "$(date) [INFO] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date) [ERROR] $1" >> "$LOG_FILE"
}

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root"
  exit 1
fi

# ==============================================================================
# STEP 0: PRE-FLIGHT CHECKS & INSTALLATION
# ==============================================================================
log "Updating package list and installing prerequisites (netplan.io, curl)..."
apt-get update -qq
apt-get install -y netplan.io curl -qq

# ==============================================================================
# STEP 1: BACKUP
# ==============================================================================
if [ -f "$INTERFACES_FILE" ]; then
    log "Step 1: Backing up $INTERFACES_FILE to $BACKUP_FILE"
    cp "$INTERFACES_FILE" "$BACKUP_FILE"
else
    error "$INTERFACES_FILE not found. Cannot proceed safely."
    exit 1
fi

# ==============================================================================
# STEP 2: CONFIGURE OFFICIAL NETPLAN (THE "S4" METHOD)
# ==============================================================================
log "Step 2: Generating Official GCP Netplan configuration..."

# Create the directory if it doesn't exist
mkdir -p /etc/netplan

# Write the exact YAML configuration used by standard GCP images (s4)
cat <<EOF > "$NETPLAN_FILE"
network:
    version: 2
    ethernets:
        all-en:
            match:
                name: en*
            dhcp4: true
            dhcp4-overrides:
                use-domains: true
            dhcp6: true
            dhcp6-overrides:
                use-domains: true
        all-eth:
            match:
                name: eth*
            dhcp4: true
            dhcp4-overrides:
                use-domains: true
            dhcp6: true
            dhcp6-overrides:
                use-domains: true
EOF

log "Disabling legacy networking and applying Netplan..."

# disable legacy networking to prevent conflicts
systemctl stop networking
systemctl disable networking

# Move legacy config aside so netplan doesn't get confused
mv "$INTERFACES_FILE" "${INTERFACES_FILE}.disabled"

# Enable systemd-networkd (required for Netplan backend)
systemctl enable systemd-networkd
systemctl start systemd-networkd

# Apply Netplan
netplan generate
netplan apply

# Wait for DHCPv6 negotiation (GCP can take a few seconds)
log "Waiting 10 seconds for DHCPv6 lease negotiation..."
sleep 10

# ==============================================================================
# STEP 3: VERIFICATION
# ==============================================================================
log "Step 3: Verifying connectivity..."

V4_STATUS=0
V6_STATUS=0

# Test IPv4
if curl -4 -s --connect-timeout 5 http://www.google.com > /dev/null; then
    log "IPv4 Check: [PASS]"
    V4_STATUS=1
else
    error "IPv4 Check: [FAIL]"
fi

# Test IPv6
if curl -6 -s --connect-timeout 5 http://www.google.com > /dev/null; then
    log "IPv6 Check: [PASS]"
    V6_STATUS=1
else
    error "IPv6 Check: [FAIL]"
fi

# ==============================================================================
# STEP 4: DECISION - SUCCESS OR ROLLBACK
# ==============================================================================

if [ $V4_STATUS -eq 1 ] && [ $V6_STATUS -eq 1 ]; then
    echo ""
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN} SUCCESS! Your instance is now Dual-Stack.${NC}"
    echo -e "${GREEN} Configured using Official Netplan Method.${NC}"
    echo -e "${GREEN}==============================================${NC}"
    ip addr show ens4
    exit 0
else
    echo ""
    echo -e "${RED}==============================================${NC}"
    echo -e "${RED} FAILURE! One or both protocols failed.${NC}"
    echo -e "${RED} Initiating ROLLBACK to legacy interfaces...${NC}"
    echo -e "${RED}==============================================${NC}"
    
    # --------------------------------------------------------------------------
    # ROLLBACK LOGIC
    # --------------------------------------------------------------------------
    
    # 1. Remove Netplan config
    rm -f "$NETPLAN_FILE"
    
    # 2. Restore interfaces file
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$INTERFACES_FILE"
        rm "${INTERFACES_FILE}.disabled" 2>/dev/null
    else
        # Fallback if move happened but copy didn't? Unlikely, but safe.
        mv "${INTERFACES_FILE}.disabled" "$INTERFACES_FILE"
    fi
    
    # 3. Stop systemd-networkd
    systemctl stop systemd-networkd
    systemctl disable systemd-networkd
    
    # 4. Restart legacy networking
    systemctl enable networking
    systemctl restart networking
    
    log "Rollback complete. System returned to previous state."
    log "Verifying connectivity after rollback..."
    
    if curl -4 -s --connect-timeout 5 http://www.google.com > /dev/null; then
        log "Rollback IPv4 Status: [OK]"
    else
        error "Rollback IPv4 Status: [FAIL] - Please check manually!"
    fi
    
    exit 1
fi
