#!/bin/bash

# Function to install iperf3 if not installed
install_iperf3() {
    if ! command -v iperf3 &> /dev/null; then
        echo "iperf3 not found. Installing iperf3..."
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update
            sudo apt-get install -y iperf3
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y iperf3
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y iperf3
        else
            echo "Package manager not found. Please install iperf3 manually."
            exit 1
        fi
    else
        echo "iperf3 is already installed."
    fi
}

# Function to check if a port is in use
is_port_in_use() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 0
    else
        return 1
    fi
}

# Install iperf3 if necessary
install_iperf3

DEFAULT_PORT=5201  # Default port for iperf3

# Prompt for IP or domain
echo "Please enter the server IP or domain (or wait 7 seconds to run as server):"
read -t 7 server_input

if [ -z "$server_input" ]; then
    # No input, run as server
    echo "No input received. Running as iperf3 server..."
    # Check if port is available
    if is_port_in_use $DEFAULT_PORT; then
        echo "Port $DEFAULT_PORT is already in use. Please close the application using this port or choose a different port."
        exit 1
    fi
    echo "Starting iperf3 server..."
    iperf3 -s -1
    echo "iperf3 server has exited after one test."
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
    echo "Running iperf3 client to connect to $server_ip..."
    iperf3 -c "$server_ip"
fi

