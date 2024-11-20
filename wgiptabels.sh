#!/bin/bash

set -euo pipefail

# Install iptables-persistent if not already installed
if ! dpkg -l | grep -qw iptables-persistent; then
    echo "Installing iptables-persistent..."
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get update
    apt-get install -y iptables-persistent
fi

# Detect the primary network interface
net_card=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$net_card" ]; then
    echo "Error: Could not detect the network interface."
 #  exit 1
else
    echo "Detected network interface: $net_card"
fi

# Add iptables rules
echo "Adding iptables rules..."
iptables -t nat -A PREROUTING -i "$net_card" -p udp --dport 55000:60000 -j DNAT --to-destination ":65503"
ip6tables -t nat -A PREROUTING -i "$net_card" -p udp --dport 55000:60000 -j DNAT --to-destination ":65503"

# Save the rules
echo "Saving iptables rules..."
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

# Ensure iptables-persistent is configured to load rules on boot
echo "Enabling iptables-persistent service..."
systemctl enable netfilter-persistent

echo "Setup completed successfully."

