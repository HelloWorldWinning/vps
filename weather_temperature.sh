#!/bin/bash
# Create temp file and download data
temp_file=$(mktemp)
norm_file=$(mktemp)
curl -A "Mozilla/5.0" -s "https://weather.cma.cn/web/weather/57687" > "$temp_file"

# Normalize HTML: ensure each div is on its own line
sed 's/<div/\n<div/g' "$temp_file" > "$norm_file"

# Get Day 1 block (actived)
day1_items=$(grep -A 50 'pull-left day actived' "$norm_file" | grep -B 50 -m 1 'pull-left day "' | head -n -1)

# Get Day 2 block (first non-actived)  
day2_items=$(grep -A 50 'pull-left day "' "$norm_file" | head -50)

# Extract function: get text content from day-item divs after icon
get_weather_after_icon() {
    echo "$1" | grep -A 2 "$2" | grep 'day-item">' | grep -v 'icon' | head -1 | sed 's/.*day-item">\([^<]*\)<.*/\1/' | tr -d '\n\r '
}

get_temp() {
    echo "$1" | grep -o "$2\">[0-9-]*℃" | head -1 | sed 's/.*">\([0-9-]*\)℃/\1/' | tr -d '\n\r '
}

# Day 1
day1_day_weather=$(get_weather_after_icon "$day1_items" "dayicon")
day1_high=$(get_temp "$day1_items" "high")
day1_night_weather=$(get_weather_after_icon "$day1_items" "nighticon")
day1_low=$(get_temp "$day1_items" "low")

# Day 2
day2_day_weather=$(get_weather_after_icon "$day2_items" "dayicon")
day2_high=$(get_temp "$day2_items" "high")
day2_night_weather=$(get_weather_after_icon "$day2_items" "nighticon")
day2_low=$(get_temp "$day2_items" "low")

# Format and output the result
result="${day1_day_weather}${day1_high}${day1_night_weather}${day1_low}_${day2_day_weather}${day2_high}${day2_night_weather}${day2_low}"
if [ "$result" = "_" ]; then
    result=""
fi

# Save to file and display result
echo "$result" > /root/.weather_temperature
echo "$result"

# Cleanup
rm -f "$temp_file" "$norm_file"
