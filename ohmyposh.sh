#echo 'export country_code=$(curl -s "https://ipinfo.io/json?token=6d89f8e7f1a21e" | grep '\"country\":' | awk -F"\""' '{print $4}')" >> ~/.bashrc
#echo "export country_code=\$(curl -s 'https://ipinfo.io/json?token=6d89f8e7f1a21e' | grep '\\\"country\\\":' | awk -F'\\\"' '{print \$4}')" >> ~/.bashrc
#export country_code=$(curl -s 'https://ipinfo.io/json?token=6d89f8e7f1a21e' | grep '\"country\":' | awk -F'\"' '{print $4}')
#export weather_temperature=$(curl -s wttr.in/beijing?format="%C,+%t")


apt install  -y unzip

curl -4s https://ohmyposh.dev/install.sh | bash -s
mkdir -p /root/themes/
wget   --inet4-only  -O  /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json  
cat >>~/.bashrc<<EOF
export country_code=\$(curl -s 'https://ipinfo.io/json?token=6d89f8e7f1a21e' | grep '\"country\":' | awk -F'\"' '{print \$4}')
export weather_temperature=\$(curl -s wttr.in/shapingba?format="%t,%C" | sed 's/+//')
eval "\$(oh-my-posh init bash --config /root/themes/gmay3.omp.json)"
EOF
