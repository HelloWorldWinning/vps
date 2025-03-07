#!/bin/bash

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

# Save the rules
echo "Saving iptables rules..."
netfilter-persistent save

# Verify the rule was added
echo "Verifying rule..."
iptables -t nat -L PREROUTING -n --line-numbers | grep 65503 || echo "No IPv4 rules found."

echo "Done!"
