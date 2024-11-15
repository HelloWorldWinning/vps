#!/bin/bash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Backup original sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%F-%H-%M)

# Configure SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Add these lines if they don't exist
if ! grep -q "^PasswordAuthentication" /etc/ssh/sshd_config; then
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
fi

if ! grep -q "^ChallengeResponseAuthentication" /etc/ssh/sshd_config; then
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config
fi

if ! grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config; then
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
fi

# Restart SSH service
if systemctl is-active --quiet sshd; then
    systemctl restart sshd
elif systemctl is-active --quiet ssh; then
    systemctl restart ssh
else
    service ssh restart
fi

echo "SSH has been configured to only allow key-based authentication"
echo "Original configuration backed up to /etc/ssh/sshd_config.backup.$(date +%F-%H-%M)"
echo "Please test your SSH key access before closing this session!"

# Test the configuration
sshd -t
if [ $? -eq 0 ]; then
    echo "SSH configuration test passed"
else
    echo "SSH configuration test failed! Please check your configuration"
    exit 1
fi
