#!/bin/bash

# Script Name: deploy_55000_service.sh
# Description: Deploys a systemd service to persist iptables and ip6tables rules across reboots.

set -e  # Exit immediately if a command exits with a non-zero status

# Variables
SCRIPT_PATH="/usr/local/bin/iptables_55000_rules.sh"
SERVICE_PATH="/etc/systemd/system/55000.service"

# Function to create the iptables rules script
create_iptables_script() {
    echo "Creating iptables rules script at ${SCRIPT_PATH}..."

    sudo tee "${SCRIPT_PATH}" > /dev/null << 'EOF'
#!/bin/bash

# Identify the first network interface with BROADCAST capability
net_card=$(ip addr | grep BROADCAST | head -1 | awk '{print $2}' | cut -d ":" -f1)

## Apply iptables rule for IPv4
#iptables -t nat -A PREROUTING -i "${net_card}" -p udp --dport 55000:60000 -j DNAT --to-destination :65503
## Apply ip6tables rule for IPv6
#ip6tables -t nat -A PREROUTING -i "${net_card}" -p udp --dport 55000:60000 -j DNAT --to-destination :65503



iptables  -t nat -A PREROUTING -i "${net_card}" -p udp --dport 58000:60000 -j DNAT --to-destination :65503
ip6tables -t nat -A PREROUTING -i "${net_card}" -p udp --dport 58000:60000 -j DNAT --to-destination :65503


EOF

    # Make the script executable
    sudo chmod +x "${SCRIPT_PATH}"
    echo "iptables rules script created and made executable."
}

# Function to create the systemd service
create_systemd_service() {
    echo "Creating systemd service at ${SERVICE_PATH}..."

    sudo tee "${SERVICE_PATH}" > /dev/null << EOF
[Unit]
Description=Apply iptables and ip6tables Rules for Ports 55000-60000
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    echo "systemd service file created."
}

# Function to reload systemd daemon, enable and start the service
enable_and_start_service() {
    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    echo "Enabling 55000.service to run at boot..."
    sudo systemctl enable 55000.service

    echo "Starting 55000.service now..."
    sudo systemctl start 55000.service

    echo "Service enabled and started."
}

# Function to verify the service status
verify_service() {
    echo "Verifying the status of 55000.service..."
    sudo systemctl status 55000.service --no-pager

    echo "Verifying iptables rules..."
    sudo iptables -t nat -L PREROUTING -n --line-numbers | grep 65503 || echo "No IPv4 rules found."

    echo "Verifying ip6tables rules..."
    sudo ip6tables -t nat -L PREROUTING -n --line-numbers | grep 65503 || echo "No IPv6 rules found."
}

# Main Execution Flow
echo "Starting deployment of 55000.service..."

create_iptables_script
create_systemd_service
enable_and_start_service
verify_service

echo "Deployment completed successfully."

