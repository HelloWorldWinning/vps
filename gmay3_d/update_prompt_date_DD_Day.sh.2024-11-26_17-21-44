#!/bin/bash

update_frequency_minutes_symbol=30  # Time interval in minutes for updating second_part

#first_part=$(date +"%I:%M %d-%A")
#first_part=$(date +"%-I:%M %d-%-9A")
first_part=$(date +"%2I:%M %d-%-9A")

symbols=(" ☰" " ☱" " ☲" " ☳" " ☴" " ☵" " ☶" " ☷")
config_file="/root/themes/gmay3.omp.json"
symbol_state_file="/tmp/current_symbol.txt"

# Function to check if 'update_frequency_minutes_symbol' minutes have passed since last symbol change
need_symbol_update() {
    if [ ! -f "$symbol_state_file" ]; then
        return 0  # File doesn't exist, needs update
    fi

    last_update=$(stat -c %Y "$symbol_state_file")
    current_time=$(date +%s)
    time_diff=$((current_time - last_update))

    interval_seconds=$((update_frequency_minutes_symbol * 60))

    # Return 0 (true) if 'update_frequency_minutes_symbol' minutes have passed
    [ $time_diff -ge $interval_seconds ]
}

# Get or update the symbol
if need_symbol_update; then
    second_part="${symbols[$RANDOM % ${#symbols[@]}]}"
    echo "$second_part" > "$symbol_state_file"
else
    second_part=$(cat "$symbol_state_file")
fi

#combined_template="    $first_part$second_part"
combined_template="    <b>$first_part$second_part</b>"

# Update the config file
jq --arg new_template "$combined_template" '
    .blocks[1].segments[0].template = $new_template
' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"

echo "Updated template to '$combined_template' in $config_file"

