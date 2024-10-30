#!/bin/bash

# Get country code (e.g., HK, TW, JP)
country_code=$(echo "$country_code" | tr '[:lower:]' '[:upper:]')  # Ensure uppercase

# Convert to flag emoji
# This works by converting each letter to its regional indicator Unicode character
first_char=$(printf "\U$(printf %x $(( $(printf "%d" "'${country_code:0:1}") + 127397 )) )")
second_char=$(printf "\U$(printf %x $(( $(printf "%d" "'${country_code:1:1}") + 127397 )) )")

# Display the emoji
flag_emoji="${first_char}${second_char}"
echo "$flag_emoji"

