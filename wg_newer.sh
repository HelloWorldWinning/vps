echo 'deb http://deb.debian.org/debian unstable main' | sudo tee /etc/apt/sources.list.d/unstable.list

sudo tee /etc/apt/preferences.d/limit-unstable <<'EOF'
Package: *
Pin: release a=unstable
Pin-Priority: 100
EOF

sudo apt update
apt policy wireguard-tools        # you should now see 1.0.20250521-1 available
sudo apt -t unstable install wireguard-tools -y
wg --version

