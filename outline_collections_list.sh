#!/bin/bash

# ==========================================
# Outline Collection Fetcher
# ==========================================

# 1. Check if jq is installed (required for clean JSON parsing)
if ! command -v jq &>/dev/null; then
	echo "Error: 'jq' is not installed."
	echo "Please install it using: sudo apt install jq (Linux) or brew install jq (Mac)"
	exit 1
fi

# 2. Collect User Inputs
echo "----------------------------------------"
read -p "Enter Outline Domain (e.g., doc.zhulei.eu.org): " USER_DOMAIN
read -s -p "Enter API Key: " API_KEY
echo "" # Print newline after secret input
echo "----------------------------------------"

# 3. Clean the domain input (remove https:// and trailing slashes)
DOMAIN="${USER_DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%/}"

# Define output file
OUTPUT_FILE="collections.txt"

# 4. Make the API Call
echo "Connecting to https://${DOMAIN}..."

RESPONSE=$(curl -s -X POST "https://${DOMAIN}/api/collections.list" \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer ${API_KEY}" \
	-d '{
    "offset": 0,
    "limit": 100,
    "sort": "updatedAt",
    "direction": "DESC"
  }')

# 5. Check if the request was successful
# We check if the JSON contains "ok": true
IS_OK=$(echo "$RESPONSE" | jq -r '.ok')

if [ "$IS_OK" != "true" ]; then
	echo "❌ API Error. Response:"
	echo "$RESPONSE"
	exit 1
fi

# 6. Process and Output Data
# clear the file first
>"$OUTPUT_FILE"

echo ""
echo "✅ Success! Found the following collections:"
echo ""
# Print Header to Console
printf "%-30s | %s\n" "COLLECTION NAME" "ID"
printf "%s\n" "-------------------------------|--------------------------------------"

# Use jq to parse name and id, separated by a tab character, then read line by line
echo "$RESPONSE" | jq -r '.data[] | "\(.name)\t\(.id)"' | while IFS=$'\t' read -r name id; do

	# Echo to Console (Formatted)
	printf "%-30s | %s\n" "$name" "$id"

	# Save to File
	echo "Name: $name | ID: $id" >>"$OUTPUT_FILE"
done

echo ""
echo "----------------------------------------"
echo "📄 Data saved to: $OUTPUT_FILE"
echo "----------------------------------------"
