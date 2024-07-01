#!/bin/bash

# Define the config file path
CONFIG_FILE="user_data/config.json"

# Define the URL containing the pairs
PAIRS_URL="https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft/spot_active_pairs.txt"

# Fetch the pairs from the URL and format them
PAIRS=$(curl -s "$PAIRS_URL" | sed -e "s/\[//g" -e "s/\]//g" -e "s/'//g" -e "s/,//g")

# Create a temporary file
TEMP_FILE=$(mktemp)

# Read the config file, update the pair_whitelist, and write to the temporary file
jq --arg pairs "$PAIRS" '
  .exchange.pair_whitelist = ($pairs | split("\n") | map(select(length > 0)))
' "$CONFIG_FILE" > "$TEMP_FILE"

# Replace the original file with the updated one
mv "$TEMP_FILE" "$CONFIG_FILE"

echo "Configuration updated successfully."
