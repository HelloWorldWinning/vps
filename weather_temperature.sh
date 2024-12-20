#!/bin/bash


temp_file=$(mktemp)

curl -A "Mozilla/5.0" -s "https://weather.cma.cn/web/weather/57516" > "$temp_file"

# Day 1 queries (working)
day1_day_weather=$(xmllint --html --xpath "//div[@class='pull-left day actived']/div[3]/text()" "$temp_file" 2>/dev/null)
#day1_high=$(xmllint --html --xpath "//div[@class='pull-left day actived']//div[@class='high']/text()" "$temp_file" 2>/dev/null | sed 's/℃/°/')
day1_high=$(xmllint --html --xpath "//div[@class='pull-left day actived']//div[@class='high']/text()" "$temp_file" 2>/dev/null | sed 's/℃//')
day1_night_weather=$(xmllint --html --xpath "//div[@class='pull-left day actived']/div[8]/text()" "$temp_file" 2>/dev/null)
#day1_low=$(xmllint --html --xpath "//div[@class='pull-left day actived']//div[@class='low']/text()" "$temp_file" 2>/dev/null | sed 's/℃/°/')
day1_low=$(xmllint --html --xpath "//div[@class='pull-left day actived']//div[@class='low']/text()" "$temp_file" 2>/dev/null | sed 's/℃//')

# Day 2 queries (corrected using following-sibling)
day2_day_weather=$(xmllint --html --xpath "//div[@class='pull-left day actived']/following-sibling::div[1]/div[3]/text()" "$temp_file" 2>/dev/null)
#day2_high=$(xmllint --html --xpath "//div[@class='pull-left day actived']/following-sibling::div[1]//div[@class='high']/text()" "$temp_file" 2>/dev/null | sed 's/℃/°/')
day2_high=$(xmllint --html --xpath "//div[@class='pull-left day actived']/following-sibling::div[1]//div[@class='high']/text()" "$temp_file" 2>/dev/null | sed 's/℃//')
day2_night_weather=$(xmllint --html --xpath "//div[@class='pull-left day actived']/following-sibling::div[1]/div[8]/text()" "$temp_file" 2>/dev/null)
#day2_low=$(xmllint --html --xpath "//div[@class='pull-left day actived']/following-sibling::div[1]//div[@class='low']/text()" "$temp_file" 2>/dev/null | sed 's/℃/°/')
day2_low=$(xmllint --html --xpath "//div[@class='pull-left day actived']/following-sibling::div[1]//div[@class='low']/text()" "$temp_file" 2>/dev/null | sed 's/℃//')

# Output the formatted result
echo "${day1_day_weather}${day1_high}${day1_night_weather}${day1_low}_${day2_day_weather}${day2_high}${day2_night_weather}${day2_low}" > ~/.weather_temperature

yes|  rm -r "$temp_file"
