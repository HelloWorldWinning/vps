#!/bin/bash

## WARNING: This script will WIPE ALL DATA on this machine and install the current stable Debian OS!
#echo -e "WARNING: Running this script will erase ALL data on the machine and \ninstall the current stable Debian OS."
#echo "Are you sure you want to continue? (Type 'YES' to proceed)"
#
## Read user input for confirmation
#read -r user_input
#
#if [ "$user_input" != "YES" ]; then
#    echo "Installation aborted. No changes were made."
#    exit 1
#fi

echo -e "WARNING: Running this script will erase ALL data on the machine and \ninstall the current stable Debian OS."

# Get hostname and align with fixed padding
hostname=$(hostname)
padding=15  # Fixed padding to align vertically

# Display hostname
#printf "\n%${padding}s\033[1;34m%s\033[0m" "" "$hostname"
printf "\n%${padding}s\033[1;31m%s\033[0m" "" "$hostname"

# Add a line below hostname
printf "\n%${padding}s%s\n" "" "----------------------------------------"

# Display prompt with same padding
printf "%${padding}s%s\n" "" "Are you sure you want to continue?"

# Create the formatted prompt with red background, white bold text
printf "%${padding}s\033[1;41;37mDD %s\033[0m\n" "" "$hostname"

# Read user input with same padding
printf "%${padding}sInput: " "" 
read -r user_input
if [ "$user_input" != "DD $hostname" ]; then
    echo "Installation aborted. No changes were made."
    exit 1
fi







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
bash InstallNET.sh -debian 12 -password '1' -port 54322 --ip-addr "$ipAddr" --ip-gate "$ipGate" --ip-mask "$ipMask" -swap "2048"


echo "sleep 5 ;  to reboot,"

sleep 5

reboot


