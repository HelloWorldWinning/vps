#!/bin/bash

# Display menu options
echo "Select an option:"
echo "1. Configure NFS Server (VPS $(tput bold)$(tput setaf 1)Data$(tput sgr0))"
echo "2. Configure NFS Client (VPS $(tput bold)$(tput setaf 1)Accessor$(tput sgr0))"
read -p "Enter your choice (1 or 2): " choice
case $choice in
  1)
    # Prompt for the IP address of the client VPS that will access this server
    read -p "Enter the IP address of the VPS $(tput bold)$(tput setaf 1)Accessor$(tput sgr0) to grant access to the NFS server: " accessor_vps_ip

    # Install NFS Server
    sudo apt update -y
    sudo apt install -y  nfs-kernel-server

    # Configure NFS Exports
    echo "/ ${accessor_vps_ip}(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports

    # Export the NFS Shares and Restart the NFS Server
    sudo exportfs -ra
    sudo systemctl restart nfs-kernel-server
    # Adjust Firewall Settings (Optional, if applicable)
    sudo ufw allow from ${accessor_vps_ip} to any port nfs
    sudo ufw enable
    sudo ufw status
    ;;
  2)
    # Prompt for the IP address of the NFS server VPS
    read -p "Enter the IP address of the NFS Server VPS $(tput bold)$(tput setaf 1)Data$(tput sgr0) to mount its shared resources: " data_vps_ip

    echo "Existing mount points:"
    find /mnt -maxdepth 1 -type d -name "vps_provider_shared_data_*" -print 2>/dev/null

    # Step 2: Prompt for custom string input
    read -p "Enter a custom string for the remote data server (leave blank for default): " custom_string

    if [ -z "$custom_string" ]; then
      mount_point="/mnt/vps_provider_shared_data_"
    else
      mount_point="/mnt/vps_provider_shared_data_${custom_string}"
    fi

    # Create Mount Point
    sudo mkdir -p "$mount_point"

    # Install NFS Client
    sudo apt update -y
    sudo apt -y  install nfs-common

    # Add Mount Entry in /etc/fstab
    echo "${data_vps_ip}:/ $mount_point nfs defaults 0 0" | sudo tee -a /etc/fstab

    # Mount Manually for the First Time
    sudo mount -a

    # Verify the Mount
    df -h
    ;;
  *)
    echo "Invalid choice. Please enter 1 or 2."
    ;;
esac
