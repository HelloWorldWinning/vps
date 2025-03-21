#!/bin/bash
# udp_redirect54000_54999.sh - Redirects UDP ports 54000-54999 to a specified endpoint
# With persistent rules that survive system reboots

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (sudo)"
    exit 1
fi

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        return $?
    else
        return 1
    fi
}

# Function to convert domain to IP
resolve_domain() {
    local domain=$1
    local ip
    ip=$(host "$domain" | grep "has address" | head -n1 | awk '{print $NF}')
    if [ -z "$ip" ]; then
        echo "Could not resolve domain $domain"
        exit 1
    fi
    echo "$ip"
}

# Get input from user
echo -n "Enter IP address or domain name: "
read -r input

# Validate/resolve input
if validate_ip "$input"; then
    target_ip=$input
else
    echo "Input is not an IP address, attempting to resolve as domain..."
    target_ip=$(resolve_domain "$input")
    echo "Resolved to IP: $target_ip"
fi

# Add iptables rule for UDP port range redirect
echo "Adding iptables rule to redirect UDP ports 54000-54999 to $target_ip:65503"
iptables -t nat -A PREROUTING -p udp --dport 54000:54999 -j DNAT --to-destination "$target_ip:65503"

# Save the rules and ensure they persist after reboot
echo "Saving iptables rules..."

# Save rules for Debian/Ubuntu
if [ -f /etc/debian_version ]; then
    # Install iptables-persistent if not installed
    if ! dpkg -l | grep -q iptables-persistent; then
        echo "Installing iptables-persistent package..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    fi
    
    # Ensure directory exists
    mkdir -p /etc/iptables
    
    # Save current rules
    echo "Saving rules to /etc/iptables/rules.v4"
    iptables-save > /etc/iptables/rules.v4
    
    # Use netfilter-persistent if available
    if command -v netfilter-persistent &> /dev/null; then
        echo "Running netfilter-persistent save..."
        netfilter-persistent save
    fi
    
    # Create systemd service for iptables restoration if it doesn't exist
    if [ ! -f /etc/systemd/system/iptables-restore.service ]; then
        cat > /etc/systemd/system/iptables-restore.service <<EOF
[Unit]
Description=Restore iptables rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "/sbin/iptables-restore < /etc/iptables/rules.v4"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable iptables-restore.service
    fi
    
    # Add cron job for reliable restoration after reboot
    cron_job="@reboot sleep 300; /bin/systemctl restart iptables-restore.service"
    (crontab -l 2>/dev/null | grep -v "iptables-restore.service"; echo "$cron_job") | crontab -
    
    echo "Rules saved and cron job added to restart iptables service after boot"
# For RHEL/CentOS systems
elif [ -f /etc/redhat-release ]; then
    # Save rules
    service iptables save
    systemctl enable iptables
# For other systems, use fallback methods
else
    # Create directory if it doesn't exist
    mkdir -p /etc/iptables
    
    # Save rules
    echo "Saving rules to /etc/iptables/rules.v4"
    iptables-save > /etc/iptables/rules.v4
    
    # Add cron job for reliable restoration after reboot
    cron_job="@reboot sleep 300; /sbin/iptables-restore < /etc/iptables/rules.v4"
    (crontab -l 2>/dev/null | grep -v "iptables-restore"; echo "$cron_job") | crontab -
    
    echo "Rules saved and cron job added to restore rules after boot"
fi

# Verify the rule was added
echo "Verifying rule..."
iptables -t nat -L PREROUTING -n --line-numbers | grep 65503 || echo "No IPv4 rules found."
echo "Done!"
