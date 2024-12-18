#!/bin/bash
update_frequency_minutes_symbol=30  # Time interval in minutes for updating second_part

# Function to format the date with padded weekday names and 'a'/'p' suffix
format_date() {
    local date_input="$1"

    # Extract date components without leading zeros
    local hour=$(date -d "$date_input" +"%-I")
    local minute=$(date -d "$date_input" +"%-M")
    local day=$(date -d "$date_input" +"%-d")
    local weekday=$(date -d "$date_input" +"%A")
    local am_pm=$(date -d "$date_input" +"%p")  # AM or PM

    # Determine 'a' or 'p' based on AM/PM
    local am_pm_symbol=""
    if [[ "$am_pm" == "AM" ]]; then
        am_pm_symbol="A"
    else
        am_pm_symbol="P"
    fi

    # Pad hour, minute, and day to two digits with leading zeros if necessary
    [ ${#hour} -eq 1 ] && hour="0$hour"
    [ ${#minute} -eq 1 ] && minute="0$minute"
    [ ${#day} -eq 1 ] && day="0$day"

    # Pad the weekday to 8 characters (left-justified)
    local padded_weekday="$weekday"
    while [ ${#padded_weekday} -lt 9 ]; do
        padded_weekday="$padded_weekday "
    done

    # Assemble the fixed-length first_part with 'a' or 'p'
 #  echo "$hour:$minute$am_pm_symbol $day-$padded_weekday"
    echo "$padded_weekday $hour:$minute$am_pm_symbol $day"
}

first_part=$(format_date "now")
# Uncomment below lines if you need to format dates like yesterday or tomorrow
#first_part=$(format_date "yesterday")
#first_part=$(format_date "tomorrow")
#first_part=$(date +"%I:%M %d-%A")
# first_part=$(date +"%-I:%M %d-%-9A")
# first_part=$(date +"%2I:%M %d-%-9A")
# first_part=$(date -d "yesterday" +"%2I:%M %d-%-9A")

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

combined_template="<b>$first_part$second_part </b>"

# Update the config file
jq --arg new_template "$combined_template" '
    .blocks[1].segments[0].template = $new_template
' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"

echo "Updated template to '$combined_template' in $config_file"

