# Define the cron job command


##(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx && systemctl stop xray && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" && systemctl start nginx && systemctl start xray > /dev/null") | crontab -

#(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx && systemctl stop xray; \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" > /root/acme-cron.log 2>&1; systemctl start nginx && systemctl start xray") | crontab -
#(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx ; systemctl stop xray; \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" > /root/acme-cron.log 2>&1; systemctl start nginx ; systemctl start xray") | crontab -
(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx ; systemctl stop xray; \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" --force  > /root/acme-cron.log 2>&1; systemctl start nginx ; systemctl start xray") | crontab -


#cat >>/etc/hosts<<EOF
#$(ip route get 1.2.3.4 | awk '{print $7}')   $('hostname')
#EOF


#(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" && systemctl start nginx > /dev/null") | crontab -


apt update
apt-get update


echo "nameserver 8.8.8.8" |  tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" |  tee -a /etc/resolv.conf

apt install  -y sudo
apt-get install -y  silversearcher-ag  fd-find  ripgrep git-lfs


sudo ln -s /usr/lib/cargo/bin/fd /usr/local/bin/fd



sudo apt install -y ncdu duf ftp  dfc



apt-get install -y xsel  xclip git poppler-utils calcurse  imagemagick  apache2-utils 

git config http.postBuffer 524288000

apt-get install -y  apache2-utils lsof  wget curl  nmap neofetch exa btop
sudo apt-get -y install fd-find  httpie



git config --global core.editor "vim"



#apt install fzf -y


apt install docker-compose -y
apt install -y net-tools unzip mc lynx telnet zip lsof  vim  httpie
apt install -y sudo netcat-openbsd  tree screen htop  tmux rsync
sudo timedatectl set-timezone Asia/Shanghai
echo '--ipv4' >> ~/.curlrc
echo 'inet4_only = on'  >> ~/.wgetrc
#alias tls="tmux list-sessions"

bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)
###########

mkdir -p /data


#source /root/.bashrc




prefer_ipv4() {
  # Check for root privileges
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    return 1
  fi

  # Backup the original gai.conf file
  cp /etc/gai.conf /etc/gai.conf.bak

  # Check if the line already exists to avoid duplicate entries
  if ! grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
    # Add the precedence line to /etc/gai.conf
    echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
  else
    echo "The precedence line already exists in /etc/gai.conf"
  fi

  # Validate if networking service exists and is active
  if systemctl is-active --quiet networking; then
    # Custom pre-check: Ensure that network interfaces are up
    if ip link show | grep -q "state UP"; then
      # Actual restart of the networking service
      systemctl restart networking
      echo "IPv4 is now preferred over IPv6 and networking service is restarted."
    else
      echo "Network interfaces are not up. Aborting restart to avoid potential loss of connection."
      return 1
    fi
  else
    echo "Networking service is not active. Manually restart to apply changes."
  fi

  # If something goes wrong, instruct the user to restore the backup
  echo "If you encounter issues, restore the original gai.conf using 'cp /etc/gai.conf.bak /etc/gai.conf' and restart networking."
}

prefer_ipv4




mkdir -p /root/themes/

#wget   --inet4-only  -O  /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json


wget   --inet4-only  -O  /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json

mkdir -p ~/.vscode-server/data/Machine/
sleep 1
wget --inet4-only -O  ~/.vscode-server/data/Machine/settings.json   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/settings_vscode.json






# ipv4_v6_forwarding='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh  )'
bash <(curl  --ipv4  -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh  )
#
#
##### vim 
bash  <(curl       -4Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/nvim.sh )


bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/swapDD.sh  )





#source ~/.bashrc
bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh.sh  )
curl -4s https://ohmyposh.dev/install.sh | bash -s  

mkdir -p /root/.config/neofetch

wget -4 -O /root/.config/neofetch/config.conf https://raw.githubusercontent.com/HelloWorldWinning/vps/main/neofetch_config.conf



bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/tmux_install.sh  )





# Define the unique identifier
unique_id_bashrc="echo_To_bashrc_txt_unique_id_bashrc"

# Check if the unique identifier exists in ~/.bashrc
if grep -q "$unique_id_bashrc" ~/.bashrc; then
    echo "Unique identifier found in ~/.bashrc. Ignoring."
else
    # If the unique identifier doesn't exist, append the content to ~/.bashrc
    echo "Unique identifier not found in ~/.bashrc. Adding."
    echo  export setup_time_first=\"`date`\" >> bar.txt
    curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/echo_To_bashrc.txt >> ~/.bashrc
fi

bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/fzf_d/config_fzf.sh  ) 


reboot
