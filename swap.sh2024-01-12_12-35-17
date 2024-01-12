#!/bin/bash

# Prompt user for size of the new swap file with a default value
read -p "Enter like:'5G' of the swap file (default is 5G): " SWAP_SIZE
SWAP_SIZE=${SWAP_SIZE:-5G}

# Identify the active swap partition(s)
SWAP_PARTITIONS=$(swapon --show=NAME --noheadings)

# Deactivate the existing swap partition(s)
for PARTITION in $SWAP_PARTITIONS; do
    sudo swapoff $PARTITION
    # Comment out the deactivated swap partition from /etc/fstab to prevent it from activating on boot
    sudo sed -i "\|$PARTITION| s/^/#/" /etc/fstab
    echo "Deactivated swap partition: $PARTITION"
done

# Create a swap file
sudo fallocate -l $SWAP_SIZE /swapfile

# Secure the swap file by setting the correct permissions
sudo chmod 600 /swapfile

# Make the file a swap file
sudo mkswap /swapfile

# Activate the new swap file
sudo swapon /swapfile

# Make the swap file permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Adjust the swappiness value
sudo sysctl vm.swappiness=10

# Make swappiness value permanent
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

echo "New swap file of size $SWAP_SIZE created and activated."

