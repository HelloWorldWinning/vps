#!/bin/bash

# iptables_55000_rules.sh
# Description: Deploys persistent iptables and ip6tables rules for UDP ports 55000-60000.
# Usage: bash <(curl -fSsL https://your_domain.com/iptables_55000_rules.sh)

#set -e  # Exit immediately if a command exits with a non-zero status

# Variables
IF_PRE_UP_SCRIPT="/etc/network/if-pre-up.d/iptables_55000_rules"
LOG_FILE="/var/log/iptables_55000_rules.log"

# Function to check if the script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root." >&2
#       exit 1
    fi
}

# Function to create the if-pre-up script
create_if_pre_up_script() {
    echo "Creating if-pre-up script at ${IF_PRE_UP_SCRIPT}..."

    cat << 'EOF' | sudo tee "${IF_PRE_UP_SCRIPT}" > /dev/null
#!/bin/sh
### BEGIN INIT INFO
# Provides:          iptables_55000_rules
# Required-Start:    $network
# Required-Stop:
# Default-Start:     PRE_UP
# Default-Stop:
# Short-Description: Apply iptables and ip6tables rules before network is up
### END INIT INFO

# Exit immediately if a command exits with a non-zero status
set -e

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/iptables_55000_rules.log
}

log "Applying iptables and ip6tables rules for interface: $IFACE"

# Apply iptables rule for IPv4
/sbin/iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 55000:60000 -j DNAT --to-destination :65503 2>/dev/null || \
/sbin/iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 55000:60000 -j DNAT --to-destination :65503

# Apply ip6tables rule for IPv6
/sbin/ip6tables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 55000:60000 -j DNAT --to-destination :65503 2>/dev/null || \
/sbin/ip6tables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 55000:60000 -j DNAT --to-destination :65503

log "Rules applied successfully for interface: $IFACE"

#exit 0
EOF

    # Make the if-pre-up script executable
    sudo chmod +x "${IF_PRE_UP_SCRIPT}"
    echo "if-pre-up script created and made executable."
}

# Function to apply iptables rules immediately to all active interfaces
apply_rules_now() {
    echo "Applying iptables rules to all active interfaces..."

    # Get all active non-loopback interfaces
    active_interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$")

    for iface in ${active_interfaces}; do
        echo "Applying rules to interface: ${iface}"

        # Apply iptables rule for IPv4 if not already present
        if ! /sbin/iptables -t nat -C PREROUTING -i "${iface}" -p udp --dport 55000:60000 -j DNAT --to-destination :65503 2>/dev/null; then
            /sbin/iptables -t nat -A PREROUTING -i "${iface}" -p udp --dport 55000:60000 -j DNAT --to-destination :65503
            echo "Applied IPv4 rule to interface: ${iface}"
        else
            echo "IPv4 rule already exists for interface: ${iface}"
        fi

        # Apply ip6tables rule for IPv6 if not already present
        if ! /sbin/ip6tables -t nat -C PREROUTING -i "${iface}" -p udp --dport 55000:60000 -j DNAT --to-destination :65503 2>/dev/null; then
            /sbin/ip6tables -t nat -A PREROUTING -i "${iface}" -p udp --dport 55000:60000 -j DNAT --to-destination :65503
            echo "Applied IPv6 rule to interface: ${iface}"
        else
            echo "IPv6 rule already exists for interface: ${iface}"
        fi
    done

    echo "Immediate iptables rules application completed."
}

# Function to create the log file if it doesn't exist
create_log_file() {
    if [ ! -f "${LOG_FILE}" ]; then
        sudo touch "${LOG_FILE}"
        sudo chmod 644 "${LOG_FILE}"
        echo "Log file created at ${LOG_FILE}."
    fi
}

# Main Execution Flow
echo "Starting deployment of persistent iptables and ip6tables rules..."

check_root
create_log_file
create_if_pre_up_script
apply_rules_now

echo "Deployment completed successfully."
echo "iptables and ip6tables rules will now persist across reboots."

exit 0

