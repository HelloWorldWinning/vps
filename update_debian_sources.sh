#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo." 
   exit 1
fi

# Detect Debian codename
if command -v lsb_release >/dev/null 2>&1; then
    CODENAME=$(lsb_release -cs)
elif [[ -f /etc/os-release ]]; then
    CODENAME=$(grep VERSION_CODENAME /etc/os-release | awk -F= '{print $2}')
elif [[ -f /etc/debian_version ]]; then
    CODENAME=$(grep -o '^[a-z]*' /etc/debian_version)
else
    echo "Cannot determine Debian codename."
    exit 1
fi

echo "Detected Debian codename: $CODENAME"

# Define the new sources.list content
NEW_SOURCES_LIST="deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware

deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian $CODENAME-backports main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $CODENAME-backports main contrib non-free non-free-firmware
"

# Backup existing sources.list
echo "Backing up current /etc/apt/sources.list to /etc/apt/sources.list.backup"
cp /etc/apt/sources.list /etc/apt/sources.list.backup

# Write the new sources.list
echo "Updating /etc/apt/sources.list with official Debian repositories."
echo "$NEW_SOURCES_LIST" > /etc/apt/sources.list

# Update package lists
echo "Updating package lists..."
apt update

echo "sources.list has been successfully updated."


