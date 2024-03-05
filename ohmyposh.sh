

apt install  -y unzip jq wget
clear
curl -4s https://ohmyposh.dev/install.sh | bash -s
mkdir -p ~/themes/
wget   --inet4-only  -O  ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json  

wget   --inet4-only  -O  ~/themes/hostname_length_adjuster.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/hostname_length_adjuster.sh

wget   --inet4-only  -O  ~/themes/cpu_usage.sh  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/cpu_usage.sh

bash  ~/themes/hostname_length_adjuster.sh

cat >>~/.bashrc<<EOF
export country_code=\$(curl -s 'https://ipinfo.io/json?token=6d89f8e7f1a21e' | grep '\"country\":' | awk -F'\"' '{print \$4}')
#bash  ~/themes/hostname_length_adjuster.sh
eval "\$(oh-my-posh init bash --config ~/themes/gmay3.omp.json)"
EOF
