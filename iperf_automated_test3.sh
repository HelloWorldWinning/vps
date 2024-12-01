#!/bin/bash

# iperf_test.sh

# Function to resolve IP address from hostname
resolve_ip() {
    local HOSTNAME=$1
    local IP_ADDRESS=$(getent hosts $HOSTNAME | awk '{ print $1 }')
    echo $IP_ADDRESS
}

# Function to install iperf
install_iperf() {
    echo "iperf is not installed. Attempting to install iperf..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update
        sudo apt-get install -y iperf
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y iperf
    else
        echo "Package manager not supported. Please install iperf manually."
        exit 1
    fi
}

# Check if iperf is installed, if not, install it
if ! command -v iperf &> /dev/null
then
    install_iperf
fi

echo "Is this vps1 or vps2? Enter 1 or 2 (default is 1 after 4 seconds):"
read -t 4 VPS_NUMBER
if [ -z "$VPS_NUMBER" ]; then
    VPS_NUMBER=1
fi

if [ "$VPS_NUMBER" == "1" ]; then
    # This is vps1

    # Start iperf server in one-off mode
    echo "Starting iperf server on vps1..."
    iperf -s -1 > vps1_server_output.txt &
    SERVER_PID=$!

    # Wait a moment for server to start
    sleep 2

    echo "Waiting for client connection from vps2..."
    wait $SERVER_PID

    echo "iperf server on vps1 has completed the test."

    # Now start iperf client connecting to vps2
    echo "Please enter the IP or domain of vps2:"
    read VPS2_IP_OR_DOMAIN
    # Resolve IP
    VPS2_IP=$(resolve_ip $VPS2_IP_OR_DOMAIN)

    echo "Starting iperf client on vps1 connecting to vps2 ($VPS2_IP)..."
    iperf -c $VPS2_IP

elif [ "$VPS_NUMBER" == "2" ]; then
    # This is vps2

    # Ask for IP or domain of vps1
    echo "Please enter the IP or domain of vps1:"
    read VPS1_IP_OR_DOMAIN

    # Resolve IP
    VPS1_IP=$(resolve_ip $VPS1_IP_OR_DOMAIN)

    # Start iperf client connecting to vps1
    echo "Starting iperf client on vps2 connecting to vps1 ($VPS1_IP)..."
    iperf -c $VPS1_IP

    # After test is complete, start iperf server in one-off mode
    echo "Starting iperf server on vps2..."
    iperf -s -1 > vps2_server_output.txt &
    SERVER_PID=$!

    # Wait a moment for server to start
    sleep 2

    echo "Waiting for client connection from vps1..."
    wait $SERVER_PID

    echo "iperf server on vps2 has completed the test."

else
    echo "Invalid input. Please enter 1 or 2."
    exit 1
fi

