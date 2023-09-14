curl -4s https://ohmyposh.dev/install.sh | bash -s
wget   --inet4-only  -O  /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json  
cat >>~/.bashrc<<EOF
eval "\$(oh-my-posh init bash --config /root/themes/gmay3.omp.json)"
EOF
