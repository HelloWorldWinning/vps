#!/bin/bash
RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

folder_name="bar"

port=545
echo -en "          ${RED}${folder_name}${PLAIN} on ${RED}${port}${PLAIN} created "
