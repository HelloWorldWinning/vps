#!/bin/bash

# Step 1: Get the latest Debian ISO URL (Adjusted to fetch the netboot files)
DEBIAN_NETBOOT_URL="http://ftp.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"

if [ -z "$DEBIAN_NETBOOT_URL" ]; then
    echo "Failed to obtain the Debian netboot URL."
    exit 1
fi

echo "Using Debian netboot URL: $DEBIAN_NETBOOT_URL"

# Step 2: Get --ip-addr, --ip-gate, --ip-mask
# Get default network interface
interface=$(ip route | awk '/default/ {print $5; exit}')

if [ -z "$interface" ]; then
    echo "Failed to get network interface."
    exit 1
fi

echo "Using network interface: $interface"

# Get IP address and prefix length
ip_info=$(ip addr show dev "$interface" | awk '/inet / {print $2; exit}')

if [ -z "$ip_info" ]; then
    echo "Failed to get IP address."
    exit 1
fi

ipAddr=${ip_info%%/*}
prefix=${ip_info##*/}

# If prefix is 32 (mask 255.255.255.255), change it to 24 (mask 255.255.255.0)
if [ "$prefix" -eq 32 ]; then
    prefix=24
fi

ipMask="$prefix"

# Get gateway
ipGate=$(ip route | awk '/default/ {print $3; exit}')

if [ -z "$ipGate" ]; then
    echo "Failed to get gateway."
    exit 1
fi

echo "IP Address: $ipAddr"
echo "Subnet Prefix (Mask): $ipMask"
echo "Gateway: $ipGate"

# Step 3: Download InstallNET.sh
wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh'

if [ ! -f InstallNET.sh ]; then
    echo "Failed to download InstallNET.sh."
    exit 1
fi

chmod a+x InstallNET.sh

# Step 4: Run InstallNET.sh with the collected parameters
bash InstallNET.sh -debian 12 -password '1' -port 54322 --ip-addr "$ipAddr" --ip-gate "$ipGate" --ip-mask "$ipMask"


echo "sleep 5 ;  to reboot,"

sleep 5

reboot


