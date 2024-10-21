#!/bin/bash

# Function to check if a file exists
check_file_exists() {
    if [ -f "$1" ]; then
        echo "File $1 exists."
    else
        echo "Error: File $1 does not exist."
        exit 1
    fi
}

# Ask user which ISO to boot from
echo "Which ISO would you like to boot from?"
echo "1. Latest Debian ISO (default)"
echo "2. netboot.xyz ISO"
read -p "Enter your choice (1 or 2): " choice

# Set the ISO URL based on user choice
if [ "$choice" = "2" ]; then
    ISO_URL="https://boot.netboot.xyz/ipxe/netboot.xyz.iso"
    ISO_FILE="/boot/images/netboot.xyz.iso"
else
    # URL of the Debian download page
    DEBIAN_URL="https://www.debian.org/"
    # Fetch the webpage content
    webpage_content=$(curl -s "$DEBIAN_URL")
    # Extract the latest ISO URL using grep and sed
    ISO_URL=$(echo "$webpage_content" | grep -oP 'href="\K[^"]+(?=.*class="os-dl-btn")' | sed 's/&amp;/\&/g')
    
    if [ -z "$ISO_URL" ]; then
        echo "Failed to extract the latest Debian ISO URL. The website structure might have changed."
        exit 1
    fi
    
    ISO_FILE="/boot/images/debian_latest.iso"
fi

echo "Using ISO URL: $ISO_URL"

# Install grub-imageboot
apt install -y grub-imageboot

# Create directory for ISO images
mkdir -p /boot/images

# Download the selected ISO
echo "Downloading ISO..."
wget -O "$ISO_FILE" "$ISO_URL"

# Check if the ISO file was downloaded successfully
check_file_exists "$ISO_FILE"

# Update GRUB menu to include this ISO
update-grub2

echo "ISO downloaded and GRUB updated. The system will now reboot."
echo "After reboot, select the downloaded ISO from the GRUB menu to boot from it."

# Reboot the system
reboot
