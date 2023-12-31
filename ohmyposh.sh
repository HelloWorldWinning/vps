

apt install  -y unzip

curl -4s https://ohmyposh.dev/install.sh | bash -s
mkdir -p ~/themes/
wget   --inet4-only  -O  ~/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json  
cat >>~/.bashrc<<EOF
export country_code=\$(curl -s 'https://ipinfo.io/json?token=6d89f8e7f1a21e' | grep '\"country\":' | awk -F'\"' '{print \$4}')
eval "\$(oh-my-posh init bash --config ~/themes/gmay3.omp.json)"
EOF
