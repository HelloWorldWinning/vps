#!/bin/bash

set -euo pipefail

# Install iptables-persistent if not already installed
if ! dpkg -l | grep -qw iptables-persistent; then
    echo "Installing iptables-persistent..."
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
fi

# Detect the primary network interface
net_card=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$net_card" ]; then
    echo "Error: Could not detect the network interface."
#   exit 1
else
    echo "Detected network interface: $net_card"
fi

# Add iptables rules
echo "Adding iptables rules..."
iptables -t nat -A PREROUTING -i "$net_card" -p udp --dport 55000:60000 -j REDIRECT --to-ports 65503
ip6tables -t nat -A PREROUTING -i "$net_card" -p udp --dport 55000:60000 -j REDIRECT --to-ports 65503


iptables -t nat -A PREROUTING -i "$net_card" -p udp --dport  443  -j REDIRECT --to-ports 65503
ip6tables -t nat -A PREROUTING -i "$net_card" -p udp --dport 443  -j REDIRECT --to-ports 65503




# Save the rules to the correct files
echo "Saving iptables rules..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules
ip6tables-save > /etc/iptables/rules6

# Ensure iptables-persistent is configured to load rules on boot
echo "Enabling iptables-persistent service..."
systemctl enable netfilter-persistent

# Restart the netfilter-persistent service to load the new rules
echo "Reloading netfilter-persistent service..."
systemctl restart netfilter-persistent

echo "Setup completed successfully."

