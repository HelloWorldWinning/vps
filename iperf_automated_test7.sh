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
    local input=$1
    local ip=""
    
    # If input is already an IP address
    if [[ $input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$input
    else
        print_status "Resolving domain: $input"
        ip=$(dig +short "$input" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
    fi
    
    if [ -z "$ip" ]; then
        print_error "Failed to resolve IP for $input"
        return 1
    fi
    
    print_status "Using IP: $ip"
    echo "$ip"
}

# Function to check if port is open
check_port() {
    local ip=$1
    local port=5201
    timeout 5 nc -zv "$ip" "$port" >/dev/null 2>&1
    return $?
}

# Function to run iperf server
start_server() {
    print_status "Starting iperf3 server..."
    if pgrep -f "iperf3 -s" >/dev/null; then
        print_warning "iperf3 server is already running. Stopping it first..."
        pkill -f "iperf3 -s"
        sleep 2
    fi
    
    iperf3 -s -D
    sleep 2
    
    if pgrep -f "iperf3 -s" >/dev/null; then
        print_status "Server started successfully on port 5201"
        print_status "Waiting for incoming connections..."
        return 0
    else
        print_error "Failed to start server"
        return 1
    fi
}

# Function to run iperf client test
run_client_test() {
    local server_ip=$1
    local output_file="iperf_result_$(date +%Y%m%d_%H%M%S).json"
    
    print_status "Starting speed test to ${server_ip}"
    print_status "Test duration: 30 seconds"
    
    # Check server connectivity
    print_status "Checking server connectivity..."
    if ! check_port "$server_ip"; then
        print_error "Cannot connect to iperf3 server at ${server_ip}:5201"
        print_error "Please ensure the server is running and port 5201 is open"
        exit 1
    fi
    print_status "Server is reachable"
    
    echo -e "\n${YELLOW}Test Progress:${NC}"
    
    # Run the test
    iperf3 -c "$server_ip" -t 30 --json > "$output_file" 2>/dev/null &
    iperf3 -c "$server_ip" -t 30 | while IFS= read -r line; do
        if [[ $line == *"sender"* ]] || [[ $line == *"receiver"* ]]; then
            echo -e "${GREEN}$line${NC}"
        else
            echo "$line"
        fi
    done
    
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        print_header "TEST RESULTS"
        echo -e "${GREEN}Time:${NC} $(date)"
        echo -e "${GREEN}Server IP:${NC} ${server_ip}"
        echo -e "${GREEN}Results:${NC} ${output_file}"
    else
        print_error "Test failed - no results generated"
        rm -f "$output_file"
    fi
}

# Trap Ctrl+C
trap 'echo -e "\n${YELLOW}[WARN]${NC} Interrupted by user. Cleaning up..."; pkill -f "iperf3 -s"; exit 1' INT

# Main script
print_header "iPerf Network Speed Test"
check_iperf

# Prompt for remote IP with 5-second timeout
echo -e "\n${YELLOW}Enter remote VPS IP/domain (5s timeout - no input = this VPS becomes server):${NC}"
read -t 5 remote_input

# Determine role and execute
if [ -z "$remote_input" ]; then
    print_status "No input received - this VPS will be the server"
    print_header "SERVER MODE"
    
    if start_server; then
        # Keep script running until interrupted
        while true; do
            if ! pgrep -f "iperf3 -s" >/dev/null; then
                print_warning "Server stopped unexpectedly"
                break
            fi
            echo -n "." && sleep 2
        done
    fi
else
    # Client mode
    SERVER_IP=$(get_ip "$remote_input")
    if [ $? -ne 0 ] || [ -z "$SERVER_IP" ]; then
        exit 1
    fi
    
    print_header "CLIENT MODE"
    print_status "Waiting 5 seconds for server to be ready..."
    sleep 5
    run_client_test "$SERVER_IP"
fi

print_header "Test Complete!"
