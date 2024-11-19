#!/bin/bash

# Color codes
RED_BG="\e[41m"
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
    echo -e "${GREEN_BG}${BLACK_TEXT}${BOLD} SUCCESS ${RESET} $1"
}

# Function to calculate and display MD5
calculate_md5() {
    local file="$1"
    if [ -f "$file" ]; then
        print_status "Calculating MD5 checksum for $file..."
        local md5sum_output=$(md5sum "$file")
        echo -e "${YELLOW}${BOLD}MD5 Checksum:${RESET} $md5sum_output"
    else
        echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File not found: $file"
    fi
}

# Check if nc (netcat) is installed; if not, install it
if ! command -v nc &> /dev/null
then
    print_status "nc not found, installing netcat-openbsd..."
    apt install -y netcat-openbsd
    print_success "netcat-openbsd installed successfully"
fi

# Prompt the user with a 4-second timeout
echo -e "${BOLD}Receiver (press Enter or wait 4s) or Sender (type anything):${RESET}"
read -t 4 input

if [ $? -gt 128 ] || [ -z "$input" ]; then
    # Receiver mode
    echo -e "${RED_BG}${WHITE_TEXT}${BOLD}  Receiver Mode  ${RESET}"
    read -p "Filename to save data: " filename
    
    print_status "Starting receiver on port 9..."
    print_status "Waiting for sender to connect..."
    
    # Use pv to show progress if available
    if command -v pv &> /dev/null; then
        nc -l -p 9 | pv > "$filename"
    else
        nc -l -p 9 > "$filename"
    fi
    
    if [ -f "$filename" ]; then
        print_success "File received successfully"
        calculate_md5 "$filename"
    else
        echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File transfer failed"
    fi
else
    # Sender mode
    echo -e "${GREEN_BG}${BLACK_TEXT}${BOLD}  Sender Mode  ${RESET}"
    read -p "IP or domain to send to: " ip
    read -p "Filename to send: " filename
    
    if [ ! -f "$filename" ]; then
        echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File not found: $filename"
        exit 1
    fi
    
    print_status "Calculating source file MD5..."
    calculate_md5 "$filename"
    
    print_status "Starting file transfer to $ip:9..."
    
    # Use pv to show progress if available
    if command -v pv &> /dev/null; then
        pv "$filename" | nc -q 1 "$ip" 9
    else
        print_status "Sending file... Please wait..."
        nc -q 1 "$ip" 9 < "$filename"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "File transfer completed"
        print_status "Please verify the MD5 checksum on the receiving end matches"
    else
        echo -e "${RED_BG}${WHITE_TEXT}${BOLD} ERROR ${RESET} File transfer failed"
    fi
fi
