#!/bin/bash

# Function to convert size to bytes
convert_to_bytes() {
    local size=$1
    echo $((size * 1024 * 1024 * 1024)) # Convert GB to bytes
}

# Function to get current tmpfs info
get_tmpfs_info() {
    echo "Current /run (tmpfs) information:"
    echo "--------------------------------"
    df -h /run | grep tmpfs
    echo
    echo "Detailed tmpfs mount info:"
    mount | grep tmpfs | grep "on /run"
    echo
    echo "Current processes using /run space:"
    du -sh /run/* 2>/dev/null | sort -hr | head -n 5
}

# Step 1: Show current information
get_tmpfs_info

# Step 2: Get new size input
echo
echo "Enter new size for /run tmpfs in GB (default: 3G, timeout: 9s):"
read -t 9 new_size

# Check if input was received
if [ -z "$new_size" ]; then
    new_size=3
    echo "Using default size: ${new_size}G"
fi

# Convert size to bytes
new_size_bytes=$(convert_to_bytes $new_size)

# Step 3: Apply new size and show results
echo
echo "Applying new tmpfs size..."
mount -o remount,size=${new_size}G /run
echo
echo "New /run (tmpfs) information:"
echo "----------------------------"
df -h /run | grep tmpfs

# Restart Docker to apply changes
echo
echo "Restarting Docker service to apply changes..."
systemctl restart docker

echo
echo "Docker status:"
systemctl status docker | grep Active
