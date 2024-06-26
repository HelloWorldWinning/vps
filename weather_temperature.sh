html_content=$(curl -m 10 -s 'http://www.weather.com.cn/weather/101040100.shtml')
weather=$(echo "$html_content" |   grep -oP '(?<=class="wea">).*?(?=</p>)' |head -n2 | tr '\n' ';' | sed 's/;$//'  )
weather=$(echo $weather | tr ';' '_')
temperature=$(echo "$html_content" | grep -oP '(?<=<i>).*?(?=℃</i>)' |head -n 1 ) 
export we_temp="${temperature}°C ${weather}"

export weather_temperature="${temperature}°${weather}"

# Save weather_temperature to a file
echo $weather_temperature > ~/.weather_temperature

echo $weather_temperature
