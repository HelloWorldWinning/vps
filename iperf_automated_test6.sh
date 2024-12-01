#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print section header
print_header() {
    echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   $1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}\n"
}

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to print error
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if iperf3 is installed
check_iperf() {
    print_status "Checking iperf3 installation..."
    if ! command -v iperf3 &> /dev/null; then
        print_warning "iperf3 is not installed. Installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y iperf3
        elif command -v yum &> /dev/null; then
            sudo yum install -y iperf3
        else
            print_error "Could not install iperf3. Please install it manually."
            exit 1
        fi
        print_status "iperf3 installed successfully!"
    else
        print_status "iperf3 is already installed"
    fi
}

# Function to convert domain to IP
get_ip() {
    local domain=$1
    local resolved_ip
    
    print_status "Resolving address: $domain"
    if [[ $domain =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        resolved_ip=$domain
    else
        resolved_ip=$(dig +short $domain | head -n1)
    fi
    
    if [ -z "$resolved_ip" ]; then
        print_error "Could not resolve IP for $domain"
        return 1
    fi
    
    print_status "Resolved to IP: $resolved_ip"
    echo "$resolved_ip"
}

# Function to check if server is listening
check_server() {
    local server_ip=$1
    nc -zv $server_ip 5201 >/dev/null 2>&1
    return $?
}

# Function to run iperf server
start_server() {
    print_status "Starting iperf3 server..."
    iperf3 -s -D
    if [ $? -eq 0 ]; then
        print_status "Server started successfully!"
        print_status "Waiting for incoming connections..."
    else
        print_error "Failed to start server"
        exit 1
    fi
}

# Function to stop iperf server
stop_server() {
    print_status "Stopping iperf3 server..."
    pkill -f "iperf3 -s"
}

# Function to run iperf client test and parse results
run_client_test() {
    local server_ip=$1
    local output_file="iperf_result_$(date +%Y%m%d_%H%M%S).json"
    
    print_status "Starting speed test to ${server_ip}..."
    print_status "Test duration: 30 seconds"
    echo -e "\n${YELLOW}Progress: ${NC}"

    # Check if server is accessible
    print_status "Checking server connectivity..."
    if ! check_server "$server_ip"; then
        print_error "Cannot connect to iperf3 server at $server_ip:5201"
        print_error "Please ensure the server is running and port 5201 is open"
        exit 1
    fi
    
    # Run iperf3 test
    iperf3 -c "$server_ip" -t 30 --json > "$output_file" 2>/dev/null &
    iperf3 -c "$server_ip" -t 30 | while IFS= read -r line; do
        if [[ $line == *"sender"* ]] || [[ $line == *"receiver"* ]]; then
            echo -e "${GREEN}$line${NC}"
        else
            echo "$line"
        fi
    done
    
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        print_status "Test completed successfully!"
        print_status "Results saved to: $output_file"
        
        print_header "TEST SUMMARY"
        echo -e "${GREEN}Date:${NC} $(date)"
        echo -e "${GREEN}Server IP:${NC} $server_ip"
        echo -e "${GREEN}Result File:${NC} $output_file"
    else
        print_error "Test failed or no results were generated"
        rm -f "$output_file"
    fi
}

# Main script
print_header "iPerf Network Speed Test"

# Check if iperf3 is installed
check_iperf

# Initialize variables
SERVER_IP=""
IS_SERVER=false

# Prompt for remote IP with 5-second timeout
echo -e "\n${YELLOW}Enter remote VPS IP/domain (5s timeout - no input = this VPS becomes server):${NC}"
read -t 5 remote_input

if [ -z "$remote_input" ]; then
    print_status "No input received - this VPS will be the server"
    IS_SERVER=true
else
    SERVER_IP=$(get_ip "$remote_input")
    if [ $? -ne 0 ] || [ -z "$SERVER_IP" ]; then
        print_error "Failed to resolve address. Exiting."
        exit 1
    fi
    print_status "Will connect to server at: $SERVER_IP"
fi

# Execute based on role
if [ "$IS_SERVER" = true ]; then
    print_header "SERVER MODE"
    start_server
    # Keep script running and show server status
    while true; do
        if ! pgrep -f "iperf3 -s" > /dev/null; then
            print_warning "Server stopped. Exiting..."
            break
        fi
        echo -n "."
        sleep 2
    done
else
    print_header "CLIENT MODE"
    print_status "Waiting 5 seconds for server to be ready..."
    sleep 5
    run_client_test "$SERVER_IP"
fi

print_header "Test Complete!"
