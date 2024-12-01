#!/bin/bash

# Function to check if iperf3 is installed
check_iperf() {
    if ! command -v iperf3 &> /dev/null; then
        echo "iperf3 is not installed. Installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y iperf3
        elif command -v yum &> /dev/null; then
            sudo yum install -y iperf3
        else
            echo "Could not install iperf3. Please install it manually."
            exit 1
        fi
    fi
}

# Function to convert domain to IP
get_ip() {
    local domain=$1
    if [[ $domain =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo $domain
    else
        echo $(dig +short $domain | head -n1)
    fi
}

# Function to run iperf server
start_server() {
    echo "Starting iperf3 server..."
    iperf3 -s -D
    sleep 2  # Wait for server to start
}

# Function to stop iperf server
stop_server() {
    echo "Stopping iperf3 server..."
    pkill -f "iperf3 -s"
}

# Function to run iperf client test
run_client_test() {
    local server_ip=$1
    echo "Running iperf3 client test to $server_ip..."
    iperf3 -c $server_ip -t 30 -J > "iperf_result_$(date +%Y%m%d_%H%M%S).json"
}

# Main script
echo "iPerf Network Speed Test"
echo "======================="

# Check if iperf3 is installed
check_iperf

# Initialize variables
SERVER_IP=""
IS_SERVER=false

# Prompt for remote IP with 5-second timeout
echo "Enter remote VPS IP/domain (5s timeout - no input = this VPS becomes server):"
read -t 5 remote_input

if [ -z "$remote_input" ]; then
    echo "No input received - this VPS will be the server"
    IS_SERVER=true
else
    SERVER_IP=$(get_ip $remote_input)
    if [ -z "$SERVER_IP" ]; then
        echo "Could not resolve IP address for $remote_input"
        exit 1
    fi
    echo "Using remote IP address: $SERVER_IP"
fi

# Execute based on role
if [ "$IS_SERVER" = true ]; then
    echo "Running as SERVER"
    start_server
    echo "Server started. Waiting for client connection..."
    # Keep script running
    while true; do
        if ! pgrep -f "iperf3 -s" > /dev/null; then
            echo "Server stopped. Exiting..."
            break
        fi
        sleep 5
    done
else
    echo "Running as CLIENT"
    echo "Waiting 5 seconds for server to be ready..."
    sleep 5
    run_client_test $SERVER_IP
fi

echo "Test complete!"
