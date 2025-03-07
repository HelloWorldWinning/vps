#!/bin/bash
# custom_udp_redirect.sh - A flexible UDP port redirect script
# Supports custom port ranges, destinations, and target ports

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

# Function to validate port or port range
validate_port() {
    local port=$1
    # Check if it's a single port
    if [[ $port =~ ^[0-9]+$ ]]; then
        if [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            return 0
        fi
        return 1
    # Check if it's a port range
    elif [[ $port =~ ^[0-9]+:[0-9]+$ ]]; then
        local start_port=$(echo "$port" | cut -d':' -f1)
        local end_port=$(echo "$port" | cut -d':' -f2)
        if [ "$start_port" -ge 1 ] && [ "$start_port" -le 65535 ] && 
           [ "$end_port" -ge 1 ] && [ "$end_port" -le 65535 ] && 
           [ "$start_port" -le "$end_port" ]; then
            return 0
        fi
        return 1
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

# Get UDP source port or port range from user
echo -n "Enter UDP port or port range to redirect (e.g. 777 or 777:999): "
read -r port_input

# Validate port input
if ! validate_port "$port_input"; then
    echo "Invalid port or port range. Must be between 1-65535."
    exit 1
fi

# Get target IP or domain from user
echo -n "Enter target IP address or domain name (leave empty for current VPS): "
read -r target_input

# Get current server IP if target is empty
if [ -z "$target_input" ]; then
    target_ip=$(hostname -I | awk '{print $1}')
    echo "Using current VPS IP: $target_ip"
else
    # Validate/resolve input
    if validate_ip "$target_input"; then
        target_ip=$target_input
    else
        echo "Input is not an IP address, attempting to resolve as domain..."
        target_ip=$(resolve_domain "$target_input")
        echo "Resolved to IP: $target_ip"
    fi
fi

# Get destination port from user
echo -n "Enter destination port: "
read -r dest_port

# Validate destination port
if ! [[ $dest_port =~ ^[0-9]+$ ]] || [ "$dest_port" -lt 1 ] || [ "$dest_port" -gt 65535 ]; then
    echo "Invalid destination port. Must be between 1-65535."
    exit 1
fi

# Prepare the iptables rule
if [[ $port_input =~ ^[0-9]+:[0-9]+$ ]]; then
    echo "Adding iptables rule to redirect UDP ports $port_input to $target_ip:$dest_port"
    iptables -t nat -A PREROUTING -p udp --dport "$port_input" -j DNAT --to-destination "$target_ip:$dest_port"
else
    echo "Adding iptables rule to redirect UDP port $port_input to $target_ip:$dest_port"
    iptables -t nat -A PREROUTING -p udp --dport "$port_input" -j DNAT --to-destination "$target_ip:$dest_port"
fi

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
    
    # Create systemd service for iptables restoration
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
iptables -t nat -L PREROUTING -n --line-numbers | grep "$target_ip:$dest_port" || echo "No matching IPv4 rules found. Please check for errors."

echo "UDP redirect configuration complete!"
