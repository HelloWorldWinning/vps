#!/bin/bash

# Function to install iperf if not installed
install_iperf() {
    if ! command -v iperf &> /dev/null; then
        echo "iperf not found. Installing iperf..."
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update
            sudo apt-get install -y iperf
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y iperf
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y iperf
        else
            echo "Package manager not found. Please install iperf manually."
            exit 1
        fi
    else
        echo "iperf is already installed."
    fi
}

# Install iperf if necessary
install_iperf

# Prompt for IP or domain
echo "Please enter the server IP or domain (or wait 7 seconds to run as server):"
read -t 7 server_input

if [ -z "$server_input" ]; then
    # No input, run as server
    echo "No input received. Running as iperf server..."
    echo "Starting iperf server..."
    iperf -s
else
    # Input received, resolve domain to IP if necessary
    echo "Input received: $server_input"
    echo "Resolving IP address..."
    server_ip=$(getent hosts "$server_input" | awk '{ print $1 }')
    if [ -z "$server_ip" ]; then
        echo "Unable to resolve IP address for $server_input"
        exit 1
    fi
    echo "Resolved IP address: $server_ip"
    echo "Running iperf client to connect to $server_ip..."
    iperf -c "$server_ip"
fi

