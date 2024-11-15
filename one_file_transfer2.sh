#!/bin/bash

# Check if nc (netcat) is installed; if not, install it
if ! command -v nc &> /dev/null
then
    echo "nc not found, installing netcat-openbsd..."
    sudo apt install -y netcat-openbsd
fi

# Prompt the user with a 4-second timeout
echo "Press Enter to be Receiver, or type anything to be Sender (you have 4 seconds to decide):"
read -t 4 input

if [ $? -gt 128 ] || [ -z "$input" ]; then
    # Receiver mode
    echo "Receiver:"
    read -p "Enter filename to save received data: " filename
    nc -l -p 9 > "$filename"
else
    # Sender mode
    echo "Sender:"
    read -p "Enter IP or domain to send to: " ip
    read -p "Enter filename to send: " filename
    nc -q 1 "$ip" 9 < "$filename"
fi

