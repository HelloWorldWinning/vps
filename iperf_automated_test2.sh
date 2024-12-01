#!/bin/bash

# iperf_test.sh

echo "Is this vps1 or vps2? Enter 1 or 2:"
read VPS_NUMBER

if [ "$VPS_NUMBER" == "1" ]; then
    # This is vps1

    # Start iperf server
    echo "Starting iperf server on vps1..."
    iperf -s > vps1_server_output.txt &
    SERVER_PID=$!

    # Wait for client test to complete
    echo "Waiting for client connection from vps2..."
    sleep 15  # Adjust sleep time if necessary

    # Kill iperf server
    echo "Stopping iperf server on vps1..."
    kill $SERVER_PID

    # Now start iperf client connecting to vps2
    echo "Please enter the IP or domain of vps2:"
    read VPS2_IP_OR_DOMAIN
    # Resolve IP
    VPS2_IP=$(ping -c 1 $VPS2_IP_OR_DOMAIN | head -1 | grep -oP '\((\d+\.\d+\.\d+\.\d+)\)' | tr -d '()')

    echo "Starting iperf client on vps1 connecting to vps2 ($VPS2_IP)..."
    iperf -c $VPS2_IP

elif [ "$VPS_NUMBER" == "2" ]; then
    # This is vps2

    # Ask for IP or domain of vps1
    echo "Please enter the IP or domain of vps1:"
    read VPS1_IP_OR_DOMAIN

    # Resolve IP
    VPS1_IP=$(ping -c 1 $VPS1_IP_OR_DOMAIN | head -1 | grep -oP '\((\d+\.\d+\.\d+\.\d+)\)' | tr -d '()')

    # Start iperf client connecting to vps1
    echo "Starting iperf client on vps2 connecting to vps1 ($VPS1_IP)..."
    iperf -c $VPS1_IP

    # After test is complete, start iperf server
    echo "Starting iperf server on vps2..."
    iperf -s > vps2_server_output.txt &
    SERVER_PID=$!

    # Wait for client connection from vps1
    echo "Waiting for client connection from vps1..."
    sleep 15  # Adjust sleep time if necessary

    # Kill iperf server
    echo "Stopping iperf server on vps2..."
    kill $SERVER_PID

else
    echo "Invalid input. Please enter 1 or 2."
fi

