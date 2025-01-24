#!/bin/bash
# Color codes
BLACK="\e[30m"      # Black
RED="\e[31m"        # Red
GREEN="\e[32m"      # Green
YELLOW="\e[33m"     # Yellow
BLUE="\e[34m"       # Blue
MAGENTA="\e[35m"    # Magenta
CYAN="\e[36m"       # Cyan
WHITE="\e[37m"      # White
YELLOW="\e[33m"     # Yellow
RED_BG="\e[41m"
RED_FONT="\e[31m"
WHITE_TEXT="\e[97m"
GREEN_BG="\e[42m"
BLACK_TEXT="\e[30m"
BOLD="\e[1m"
RESET="\e[0m"
YELLOW="\e[93m"
BLUE="\e[94m"

# Function to print status messages
print_status() {
    echo -e "${BLUE}${BOLD}[STATUS]${RESET} $1"
}

# Function to print success messages
print_success() {
    echo -e "${RED_FONT}${BOLD}SUCCESS${RESET} $1"
}

# Function to calculate time difference in seconds
calculate_duration() {
    local start=$1
    local end=$2
    # Using awk for floating point arithmetic
    awk -v start="$start" -v end="$end" 'BEGIN {printf "%.2f", end - start}'
}

# Function to calculate and display MD5 with timing
calculate_md5() {
    local file="$1"
    local start_time
    local end_time
    local duration
    
    if [ -f "$file" ]; then
        print_status "Calculating MD5 checksum for $file..."
        start_time=$(date +%s.%N)
        local md5sum_output=$(md5sum "$file")
        end_time=$(date +%s.%N)
        duration=$(calculate_duration "$start_time" "$end_time")
        echo -e "${YELLOW}${BOLD}MD5 Checksum:${RESET} ${RED_FONT}${BOLD}$md5sum_output${RESET}"
        echo -e "${YELLOW}${BOLD}MD5 Computation Time:${RESET} ${CYAN}${BOLD}$duration seconds${RESET}"
    else
        echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} ${RED_FONT}${BOLD} File not found: $file${RESET}"
    fi
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local IFS='.'
        local -a ip_parts=($ip)
        [[ ${#ip_parts[@]} -eq 4 ]] && \
        [[ ${ip_parts[0]} -le 255 && ${ip_parts[1]} -le 255 && \
           ${ip_parts[2]} -le 255 && ${ip_parts[3]} -le 255 ]]
        return $?
    fi
    return 1
}

# Function to validate domain/IP using ping and host command
validate_address() {
    local input=$1
    local is_valid=1

    # Method 1: Try ping
    if ping -c 1 -W 2 "$input" >/dev/null 2>&1; then
        is_valid=0
    fi

    # Method 2: Try host command if available
    if command -v host >/dev/null 2>&1; then
        if host "$input" >/dev/null 2>&1; then
            is_valid=0
        fi
    # Fallback to nslookup if host is not available
    elif command -v nslookup >/dev/null 2>&1; then
        if nslookup "$input" >/dev/null 2>&1; then
            is_valid=0
        fi
    fi

    return $is_valid
}

# Check if nc (netcat) is installed; if not, install it
if ! command -v nc &> /dev/null
then
    print_status "nc not found, installing netcat-openbsd..."
    apt install -y netcat-openbsd
    print_success "netcat-openbsd installed successfully"
fi

# Check if awk is installed (required for calculations)
if ! command -v awk &> /dev/null
then
    print_status "awk not found, installing gawk..."
    apt install -y gawk
    print_success "gawk installed successfully"
fi

# Prompt the user with a 15-second timeout
echo -e "${BOLD}Receiver (press Enter or wait 15s) or Sender (type IP/domain):${RESET}"
read -t 15 input
status=$?

# Receiver mode if timeout occurs or empty input
if [ $status -gt 128 ] || [ -z "$input" ]; then
    # Receiver mode
    echo -e "${RED_BG}${WHITE_TEXT}${BOLD}  Receiver Mode  ${RESET}"
    read -p "Filename to save data: " filename
    
    print_status "Starting receiver on port 9..."
    print_status "Waiting for sender to connect..."
    
    # Record start time for receiving
    start_time=$(date +%s.%N)
    
    # Create a temporary file for nc output
    temp_file=$(mktemp)
    
    # Use pv to show progress if available
    if command -v pv &> /dev/null; then
        nc -l -p 9 | pv > "$temp_file"
        nc_status=${PIPESTATUS[0]}
    else
        nc -l -p 9 > "$temp_file"
        nc_status=$?
    fi
    
    # Move temp file to destination if transfer was successful
    if [ $nc_status -eq 0 ] && [ -s "$temp_file" ]; then
        mv "$temp_file" "$filename"
        transfer_success=true
    else
        rm -f "$temp_file"
        transfer_success=false
    fi
    
    # Record end time for receiving
    end_time=$(date +%s.%N)
    receive_duration=$(calculate_duration "$start_time" "$end_time")
    
    if [ "$transfer_success" = true ]; then
        print_success "File received successfully"
        echo -e "${YELLOW}${BOLD}Receiving Time:${RESET} ${CYAN}${BOLD}$receive_duration seconds${RESET}"
        calculate_md5 "$filename"
    else
        echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File transfer failed"
    fi
else
    # Validate if input is IP/domain or filename
    is_ip_or_domain=0
    
    # Check if input is valid IP
    if validate_ip "$input"; then
        is_ip_or_domain=1
    else
        # Try to validate as domain using ping and host/nslookup
        if validate_address "$input"; then
            is_ip_or_domain=1
        fi
    fi
    
    # If input is not IP/domain, assume it's a filename for receiving
    if [ $is_ip_or_domain -eq 0 ]; then
        echo -e "${RED_BG}${WHITE_TEXT}${BOLD}  Receiver Mode  ${RESET}"
        filename="$input"
        
        print_status "Starting receiver on port 9..."
        print_status "Waiting for sender to connect..."
        
        # Record start time for receiving
        start_time=$(date +%s.%N)
        
        # Create a temporary file for nc output
        temp_file=$(mktemp)
        
        # Use pv to show progress if available
        if command -v pv &> /dev/null; then
            nc -l -p 9 | pv > "$temp_file"
            nc_status=${PIPESTATUS[0]}
        else
            nc -l -p 9 > "$temp_file"
            nc_status=$?
        fi
        
        # Move temp file to destination if transfer was successful
        if [ $nc_status -eq 0 ] && [ -s "$temp_file" ]; then
            mv "$temp_file" "$filename"
            transfer_success=true
        else
            rm -f "$temp_file"
            transfer_success=false
        fi
        
        # Record end time for receiving
        end_time=$(date +%s.%N)
        receive_duration=$(calculate_duration "$start_time" "$end_time")
        
        if [ "$transfer_success" = true ]; then
            print_success "File received successfully"
            echo -e "${YELLOW}${BOLD}Receiving Time:${RESET} ${CYAN}${BOLD}$receive_duration seconds${RESET}"
            calculate_md5 "$filename"
        else
            echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File transfer failed"
        fi
    else
        # Sender mode
        echo -e "${GREEN_BG}${BLACK_TEXT}${BOLD}  Sender Mode  ${RESET}"
        # Use the initial input as IP/domain
        ip="$input"
        read -p "Filename to send: " filename
        
        if [ ! -f "$filename" ]; then
            echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File not found: $filename"
            exit 1
        fi
        
        print_status "Calculating source file MD5..."
        calculate_md5 "$filename"
        
        print_status "Starting file transfer to $ip:9..."
        
        # Record start time for sending
        start_time=$(date +%s.%N)
        
        # Use pv to show progress if available
        if command -v pv &> /dev/null; then
            pv "$filename" | nc -q 1 "$ip" 9
            nc_status=${PIPESTATUS[1]}
        else
            print_status "Sending file... Please wait..."
            nc -q 1 "$ip" 9 < "$filename"
            nc_status=$?
        fi
        
        # Record end time for sending
        end_time=$(date +%s.%N)
        send_duration=$(calculate_duration "$start_time" "$end_time")
        
        if [ $nc_status -eq 0 ]; then
            print_success "File transfer completed"
            echo -e "${YELLOW}${BOLD}Sending Time:${RESET} ${CYAN}${BOLD}$send_duration seconds${RESET}"
            print_status "Please verify the MD5 checksum on the receiving end matches"
        else
            echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File transfer failed"
        fi
    fi
fi
