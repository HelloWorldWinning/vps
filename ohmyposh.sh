

apt install  -y unzip

curl -4s https://ohmyposh.dev/install.sh | bash -s
mkdir -p ~/themes/
wget   --inet4-only  -O  ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json  
cat >>~/.bashrc<<EOF

## Fetch the HTML content
html_content=\$(curl -m 10 -s 'http://www.weather.com.cn/weather/101040100.shtml')
# Extract the weather condition and temperature
weather=\$(echo "\$html_content" | grep -oP '(?<=<p title="多云" class="wea">).*?(?=</p>)' |head -n 1)
temperature=\$(echo "\$html_content" | grep -oP '(?<=<i>).*?(?=℃</i>)' |head -n 1 ) 

# Output the results
#echo "Weather condition: \$weather"
#echo "Temperature: \$temperature°C" 
we_temp="\${temperature}°C \${weather}"



export country_code=\$(curl -s 'https://ipinfo.io/json?token=6d89f8e7f1a21e' | grep '\"country\":' | awk -F'\"' '{print \$4}')
##export weather_temperature=\$(curl -s wttr.in/shapingba?format="%t,%C" | sed 's/+//')
export weather_temperature=\$we_temp
eval "\$(oh-my-posh init bash --config ~/themes/gmay3.omp.json)"
EOF
