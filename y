#!/bin/bash

# Function to convert country code to flag emoji
country_to_emoji() {
    local country_code=$1
    
    # Convert to uppercase
    country_code=${country_code^^}
    
    # Convert ASCII letters to regional indicator symbols
    # Regional indicator symbols start at U+1F1E6 for 'A'
    local emoji=""
    for (( i=0; i<${#country_code}; i++ )); do
        local char=${country_code:$i:1}
        # Calculate Unicode code point for regional indicator symbol
        local unicode_point=$(printf '%x' $(( 0x1F1E6 + $(printf '%d' "'$char") - 65 )))
        emoji="$emoji\U$unicode_point"
    done
    
    # Print the emoji
    printf "$emoji\n"
}

# Get country code from environment variable or argument
code=${1:-$country_code}

if [ -z "$code" ]; then
    echo "Error: No country code provided"
    echo "Usage: $0 [country_code] or set \$country_code environment variable"
    exit 1
fi

# Convert and display emoji
country_to_emoji "$code"
