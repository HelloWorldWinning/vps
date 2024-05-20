

apt install  -y unzip jq wget
clear
curl -4s https://ohmyposh.dev/install.sh | bash -s
mkdir -p ~/themes/
wget   --inet4-only  -O  ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json  

wget   --inet4-only  -O  ~/themes/hostname_length_adjuster.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/hostname_length_adjuster.sh

wget   --inet4-only  -O  ~/themes/cpu_usage.sh  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/cpu_usage.sh

########## bash  ~/themes/hostname_length_adjuster.sh

#cat >>~/.bashrc<<EOF
#export country_code=$(curl -s http://ip-api.com/line/?fields=countryCode)
##bash  ~/themes/hostname_length_adjuster.sh
#eval "\$(oh-my-posh init bash --config ~/themes/gmay3.omp.json)"
#EOF

####
####if ! grep -q "export country_code=" ~/.bashrc; then
####
####    cat >> ~/.bashrc << 'END'
####export country_code=$(curl -s http://ip-api.com/line/?fields=countryCode)
#####bash  ~/themes/hostname_length_adjuster.sh
####eval "$(oh-my-posh init bash --config ~/themes/gmay3.omp.json)"
####END
####
####fi
####
####


wget   --inet4-only  -O  ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json


country_code_weather_alias='
country_code_file=~/.country_code

if [ -f "$country_code_file" ]; then
  export country_code=$(cat "$country_code_file")
else 
  export country_code=$(curl -s http://ip-api.com/line/?fields=countryCode)
  echo "$country_code" > "$country_code_file"
fi

alias wea="source <(curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/weather_temperature.sh)"
'

if ! grep -q -F "$country_code_weather_alias" ~/.bashrc; then
  echo "$country_code_weather_alias" >> ~/.bashrc
  echo "Country code weather alias appended to ~/.bashrc"
else
  echo "Country code weather alias already exists in ~/.bashrc. No changes made."
fi



