#!/bin/bash

# Prompt user for the size of the new swap file in gigabytes
#read -p "Enter the size of the swap file in GB (e.g., '1' for 1GB, '1.5' for 1.5GB, default is 5): " SWAP_SIZE
#SWAP_SIZE=${SWAP_SIZE:-5}G  # Append 'G' to make it GB

# Get disk size in GB (assumes disk size is reported in bytes)
DISK_SIZE=$(df --output=size / | tail -n 1)
DISK_SIZE_GB=$((DISK_SIZE / 1024 / 1024)) # Convert to GB

# Set SWAP_SIZE based on disk size conditions
if [ $DISK_SIZE_GB -lt 10 ]; then
    SWAP_SIZE="1G"
elif [ $DISK_SIZE_GB -lt 30 ]; then
    SWAP_SIZE="2G"
elif [ $DISK_SIZE_GB -lt 50 ]; then
    SWAP_SIZE="3G"
elif [ $DISK_SIZE_GB -lt 70 ]; then
    SWAP_SIZE="4G"
else
    SWAP_SIZE="5G"
fi

# Export the SWAP_SIZE variable
#  export SWAP_SIZE

# Print the selected SWAP_SIZE for verification
# echo "Disk size: ${DISK_SIZE_GB}G"
# echo "Selected SWAP_SIZE: $SWAP_SIZE"

##################################################################
#SWAP_SIZE=5G
#SWAP_SIZE=1G

# Identify the active swap partition(s)
SWAP_PARTITIONS=$(swapon --show=NAME --noheadings)

# Deactivate and remove the existing swap file
if swapon --show=NAME | grep -q '/swapfile'; then
    sudo swapoff /swapfile
    sudo rm /swapfile
    # Comment out the old swap file entry from /etc/fstab
    sudo sed -i '/\/swapfile/d' /etc/fstab
    echo "Removed old swap file."
fi

# Deactivate other swap partitions and comment them out from /etc/fstab
for PARTITION in $SWAP_PARTITIONS; do
    sudo swapoff $PARTITION
    sudo sed -i "\|$PARTITION| s/^/#/" /etc/fstab
    echo "Deactivated swap partition: $PARTITION"
done

# Create a new swap file
sudo fallocate -l $SWAP_SIZE /swapfile

# Secure the swap file by setting the correct permissions
sudo chmod 600 /swapfile

# Make the file a swap file
sudo mkswap /swapfile

# Activate the new swap file
sudo swapon /swapfile

# Add the new swap file to /etc/fstab
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Adjust the swappiness value
sudo sysctl vm.swappiness=10

# Make swappiness value permanent
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

echo "New swap file of size $SWAP_SIZE created and activated."

