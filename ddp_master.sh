#!/bin/bash

# Prompt for user input or use environment variables
read -p "Enter MASTER_ADDR [default: 34.84.75.37]: " MASTER_ADDR
read -p "Enter MASTER_PORT [default: 29500]: " MASTER_PORT
read -p "Enter rank [default: 0]: " RANK
read -p "Enter size [default: 2]: " SIZE

# Use default values if no input provided
MASTER_ADDR=${MASTER_ADDR:-34.84.75.37}
MASTER_PORT=${MASTER_PORT:-29500}
RANK=${RANK:-0}
SIZE=${SIZE:-2}

# Export environment variables
export MASTER_ADDR
export MASTER_PORT
export RANK
export SIZE

# Download the script using wget with IPv4 only
if [ "$RANK" -eq 0 ]; then
    wget -4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ddp_master.py -O master.py
else
    wget -4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ddp_master.py -O client_${RANK}.py
fi

echo "Download completed. MASTER_ADDR=$MASTER_ADDR, MASTER_PORT=$MASTER_PORT, rank=$RANK, size=$SIZE"

