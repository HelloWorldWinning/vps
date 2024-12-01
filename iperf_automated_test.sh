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

# Get server IP/domain
read -p "Enter VPS1 IP address or domain: " vps1_input
VPS1_IP=$(get_ip $vps1_input)

if [ -z "$VPS1_IP" ]; then
    echo "Could not resolve IP address for $vps1_input"
    exit 1
fi

echo "Using IP address: $VPS1_IP"

# Round 1: VPS1 as server, VPS2 as client
echo -e "\nRound 1: VPS1 (Server) -> VPS2 (Client)"
echo "----------------------------------------"
echo "On VPS1, run: iperf3 -s -D"
echo -e "On VPS2, run: iperf3 -c $VPS1_IP -t 30 -J > iperf_result_\$(date +%Y%m%d_%H%M%S).json\n"

# Wait for first round to complete
read -p "Press Enter when Round 1 is complete..."

# Round 2: VPS2 as server, VPS1 as client
echo -e "\nRound 2: VPS2 (Server) -> VPS1 (Client)"
echo "----------------------------------------"
echo "On VPS2, run: iperf3 -s -D"
echo "On VPS1, run: iperf3 -c [VPS2_IP] -t 30 -J > iperf_result_\$(date +%Y%m%d_%H%M%S).json"

# Cleanup instructions
echo -e "\nTo stop iperf3 server on either VPS:"
echo "pkill -f 'iperf3 -s'"

echo -e "\nTest complete! Check the JSON result files for detailed performance metrics."
