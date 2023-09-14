curl -4s https://ohmyposh.dev/install.sh | bash -s
wget   --inet4-only  -O  /root/themes/gmay2.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay2.omp.json  
cat >>~/.bashrc<<EOF
eval "\$(oh-my-posh init bash --config /root/themes/gmay2.omp.json)"
EOF
