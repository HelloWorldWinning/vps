#!/bin/bash

# Color codes
RED_BG="\e[41m"
WHITE_TEXT="\e[97m"
GREEN_BG="\e[42m"
BLACK_TEXT="\e[30m"
BOLD="\e[1m"
RESET="\e[0m"

# Check if nc (netcat) is installed; if not, install it
if ! command -v nc &> /dev/null
then
    echo -e "${BOLD}nc not found, installing netcat-openbsd...${RESET}"
    sudo apt install -y netcat-openbsd
fi

# Prompt the user with a 4-second timeout
echo -e "${BOLD}Receiver (press Enter or wait 4s) or Sender (type anything):${RESET}"
read -t 4 input

if [ $? -gt 128 ] || [ -z "$input" ]; then
    # Receiver mode
    echo -e "${RED_BG}${WHITE_TEXT}${BOLD}  Receiver Mode  ${RESET}"
    read -p "Filename to save data: " filename
    nc -l -p 9 > "$filename"
else
    # Sender mode
    echo -e "${GREEN_BG}${BLACK_TEXT}${BOLD}  Sender Mode  ${RESET}"
    read -p "IP or domain to send to: " ip
    read -p "Filename to send: " filename
    nc -q 1 "$ip" 9 < "$filename"
fi

