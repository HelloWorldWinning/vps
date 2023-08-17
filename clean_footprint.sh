#!/bin/bash

# Clear system logs
sudo find /var/log -type f -delete
sudo journalctl --vacuum-time=1s

# Clear temporary files
sudo rm -rf /tmp/*
sudo rm -rf ~/.cache/*

# Clear browser histories (if applicable)
rm -rf ~/.mozilla/firefox/*.default*/Cache/*
rm -rf ~/.mozilla/firefox/*.default*/cookies.sqlite
rm -rf ~/.cache/google-chrome/*
rm -rf ~/.cache/opera/*

# Clear bash history
history -c && history -w
rm ~/.bash_history


# Wipe free space to make file recovery more difficult
sudo dd if=/dev/zero of=/tmp/zeroes bs=4096
sudo rm -f /tmp/zeroes

echo "Cleanup complete."

