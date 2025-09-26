#!/bin/bash

# Create temp file and download data
temp_file=$(mktemp)
#curl -A "Mozilla/5.0" -s "https://weather.cma.cn/web/weather/57516" > "$temp_file"
curl -A "Mozilla/5.0" -s "https://weather.cma.cn/web/weather/57687" > "$temp_file"

# Extract Day 1 data
# Get the weather conditions between "day-item"> and <, looking at lines after "actived"
day1_day_weather=$(grep -A 5 'pull-left day actived' "$temp_file" | grep 'day-item">' | grep -v "星期" | grep -v "dayicon" | head -1 | sed 's/.*day-item">\([^<]*\)<.*/\1/')

# Get high temperature
day1_high=$(grep -A 20 'pull-left day actived' "$temp_file" | grep 'high' | head -1 | sed 's/.*high">\([0-9]*\)℃.*/\1/')

# Get night weather
day1_night_weather=$(grep -A 20 'pull-left day actived' "$temp_file" | grep 'day-item">' | grep -v "星期" | grep -v "icon" | grep -v "微风" | tail -1 | sed 's/.*day-item">\([^<]*\)<.*/\1/')

# Get low temperature
day1_low=$(grep -A 20 'pull-left day actived' "$temp_file" | grep 'low' | head -1 | sed 's/.*low">\([0-9]*\)℃.*/\1/')

# Extract Day 2 data
# Get section for second day and extract data
day2_section=$(grep -A 20 'pull-left day "' "$temp_file" | head -n 20)

# Get weather from day2 section
day2_day_weather=$(echo "$day2_section" | grep 'day-item">' | grep -v "星期" | grep -v "dayicon" | head -1 | sed 's/.*day-item">\([^<]*\)<.*/\1/')

# Get high temperature from day2 section
day2_high=$(echo "$day2_section" | grep 'high' | head -1 | sed 's/.*high">\([0-9]*\)℃.*/\1/')

# Get night weather from day2 section
#day2_night_weather=$(echo "$day2_section" | grep 'day-item">' | grep -v "星期" | grep -v "icon" | grep -v "微风" | tail -1 | sed 's/.*day-item">\([^<]*\)<.*/\1/')

day2_night_weather=$(echo "$day2_section" | grep 'day-item">' | tail -n 3 | head -n 1 | sed -n 's/.*day-item">\([^<]*\)<.*/\1/p')
# Get low temperature from day2 section
day2_low=$(echo "$day2_section" | grep 'low' | head -1 | sed 's/.*low">\([0-9]*\)℃.*/\1/')

# Format and output the result
result="${day1_day_weather}${day1_high}${day1_night_weather}${day1_low}_${day2_day_weather}${day2_high}${day2_night_weather}${day2_low}"
if [ "$result" = "_" ]; then
    result=""
fi

# Save to file and display result
echo "$result" > /root/.weather_temperature
echo "$result"

# Cleanup
rm -f "$temp_file"
