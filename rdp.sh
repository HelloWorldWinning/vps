#!/bin/bash

# Get network interface and IP address
net_card=$(ip addr | grep BROADCAST | head -1 | awk '{print $2; exit}' | cut -d ":" -f 1)
ip_inet=$(ifconfig $net_card | grep inet | grep -v inet6 | awk '{print $2}')
echo $ip_inet
cat >> /etc/hosts <<EOF
$ip_inet  $HOSTNAME
EOF

# Update and install necessary packages
apt update -y
apt install -y sudo curl wget
sudo apt-get install -y net-tools xrdp xfce4 tigervnc-standalone-server

# Stop XRDP service
sudo service xrdp stop

# Ask for RDP username
read -p 'input rdp user name [rdp for empty]: ' rdp_username_input
rdp_username=${rdp_username_input:-rdp}

# Create the user
sudo adduser ${rdp_username}
sudo adduser ${rdp_username} ssl-cert  
echo "${rdp_username} ALL=(ALL:ALL) ALL" | sudo tee -a /etc/sudoers

# Ensure the home directory exists
if [ -d "/home/${rdp_username}" ]; then
    echo xfce4-session > /home/${rdp_username}/.xsession
    sudo chown ${rdp_username}:${rdp_username} /home/${rdp_username}/.xsession
    sudo chmod 755 /home/${rdp_username}/.xsession
else
    echo "Home directory for ${rdp_username} not found!"
fi

# Install Google Chrome
sudo wget -O google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install ./google-chrome-stable_current_amd64.deb -y
sudo rm ./google-chrome-stable_current_amd64.deb

# Install Firefox ESR
sudo apt-get install aptitude -y 
sudo aptitude install firefox-esr -y

# Configure locales and fonts for Chinese support
echo "en_US.UTF-8 zh_CN.UTF-8 ← 选择 chose "
echo "locale zh_CN.UTF-8 ← 选择 chose  "

sleep 3
sudo apt-get install locales -y
sudo apt-get install ttf-wqy-zenhei -y  # Install fonts
sudo apt-get install ibus ibus-gtk ibus-pinyin -y  # Install input methods

# Configure XTerm
cat >>/etc/X11/app-defaults/XTerm<<EOF
xterm*faceName: Andale Mono
xterm*faceSize: 25
xterm*background: black
xterm*foreground: Green3
EOF

# Install Microsoft Edge
sudo apt update && sudo apt upgrade -y
sudo apt install software-properties-common apt-transport-https wget ca-certificates gnupg2 ubuntu-keyring -y
sudo wget -O- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-edge.gpg
echo 'deb [signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main' | sudo tee /etc/apt/sources.list.d/microsoft-edge.list
sudo apt update
sudo apt install microsoft-edge-stable -y

# Install Microsoft core fonts
wget http://ftp.de.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8_all.deb
sudo dpkg -i ttf-mscorefonts-installer_3.8_all.deb
sudo apt install cabextract -y
sudo apt --fix-broken install -y
sudo apt autoremove -y
sudo apt-get install ttf-mscorefonts-installer -y
sudo rm ttf-mscorefonts-installer_3.8_all.deb

# Configure Vim for the user
cat > /home/${rdp_username}/.vimrc <<EOF 
set tabline=%F\ %y
set laststatus=2
set number 
hi LineNr         ctermfg=DarkMagenta guifg=#f5713d guibg=#000000 
hi CursorLineNr   term=bold ctermfg=Yellow gui=bold guifg=Yellow
EOF

# Install all locales
sudo apt-get install locales-all -y

# Restart XRDP service
sudo service xrdp restart

echo "RDP setup complete. You can connect to this server using the username '${rdp_username}'."

