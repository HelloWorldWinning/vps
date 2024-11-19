#!/bin/bash
# Description:
# This script removes any crontab entry tagged with '#install_1112_related_pre_tcpx_sh'

# Define the tag to search for
TAG="#install_1112_related_pre_tcpx_sh"

# Backup current crontab
echo "Backing up current crontab to crontab.bak..."
crontab -l > crontab.bak 2>/dev/null
if [ $? -ne 0 ]; then
    echo "No existing crontab found. Exiting."
    exit 1
fi

# Remove lines containing the specific tag
echo "Removing lines containing the tag: $TAG"
crontab -l | grep -v "$TAG" > crontab.tmp

# Check if any changes were made
if cmp -s crontab.bak crontab.tmp; then
    echo "No lines with the tag '$TAG' were found. No changes made."
    rm crontab.tmp
    exit 0
fi

# Install the updated crontab
crontab crontab.tmp
if [ $? -eq 0 ]; then
    echo "Crontab updated successfully."
    # Optionally, remove the backup after successful update
    # rm crontab.bak
else
    echo "Failed to update crontab."
    # Restore from backup in case of failure
    crontab crontab.bak
    exit 1
fi

# Clean up temporary file
rm crontab.tmp

#
#
#
#
#read -t 5 -p "1 vmess80 ,2 vmess80 openai " REPLY || REPLY=1
#
## Handle timeout/empty input to 1, and invalid inputs to 2
#if [[ -z "$REPLY" ]] || [[ "$REPLY" == "1" ]]; then
#    REPLY=1
#else
#    REPLY=2
# # Prompt for IP/Domain input
# read -p "Please openai ss IP or domain to replace OPENAI_IP_DOMAIN: " new_domain
#fi
#
#echo "Selected: $REPLY"





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

sudo  apt update
sudo  apt-get update

sudo apt install -y  python3-pynvim

apt-get install -y  silversearcher-ag  fd-find  ripgrep git-lfs dnsutils

sudo ln -s /usr/lib/cargo/bin/fd /usr/local/bin/fd

sudo apt install -y ncdu duf ftp  dfc

apt-get install -y xsel  xclip git poppler-utils calcurse  imagemagick  apache2-utils 

git config http.postBuffer 524288000

apt-get install -y  apache2-utils lsof  wget curl  nmap neofetch exa btop
sudo apt-get -y install fd-find  httpie



git config --global core.editor "vim"



#apt install fzf -y

apt install docker-compose -y
#####bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_docker_compose_v1_claude.sh )  

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


#### bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/swapDD.sh  )



# Set XDG_CACHE_HOME for the current session
#export XDG_CACHE_HOME="/root/.cache/oh-my-posh"


##echo 'export XDG_CACHE_HOME="/root/.cache/oh-my-posh"' >>  $HOME/.bashrc


export XDG_CACHE_HOME=$HOME/.cache/oh-my-posh 
export OMP_CACHE_DIR=$HOME/.oh-my-posh/cache
mkdir -p "$XDG_CACHE_HOME"
mkdir -p "$OMP_CACHE_DIR"

cat <<EOF >> $HOME/.bashrc 
export XDG_CACHE_HOME=$HOME/.cache/oh-my-posh
export OMP_CACHE_DIR=$HOME/.oh-my-posh/cache
EOF
source   $HOME/.bashrc

#echo "XDG_CACHE_HOME has been set to $XDG_CACHE_HOME"

####bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh.sh  )
#
#3bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh_23_7_2.sh  )

###curl -4s https://ohmyposh.dev/install.sh | bash -s  
# export env1=value1 && export env2=value2 && bash my.sh

(export XDG_CACHE_HOME=$HOME/.cache/oh-my-posh && export OMP_CACHE_DIR=$HOME/.oh-my-posh/cache  )  && (  curl -4s  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh_23_7_2.sh  |   bash -s )

mkdir -p /root/.config/neofetch

wget -4 -O /root/.config/neofetch/config.conf https://raw.githubusercontent.com/HelloWorldWinning/vps/main/neofetch_config.conf






cat <<"EOF">> /etc/sysctl.conf
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.tcp_rmem=4096 87380 26214400
net.ipv4.tcp_wmem=4096 65536 26214400
EOF

cat <<"EOF">> ~/.bashrc
alias h='htop'
alias hc='htop --sort-key PERCENT_CPU'
alias hm='htop --sort-key PERCENT_MEM'
alias bt='btop'
EOF


cat << "EOF" > /etc/resolv.conf
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF



###########  wg 

net_card=$(ip addr |grep BROADCAST|head -1|awk '{print $2; exit}'|cut -d ":" -f 1)

wgcf_card=$(ip addr | grep "wgcf:" | awk '{print $2}' | cut -d ":" -f 1)
warp_card=$(ip addr | grep "warp:" | awk '{print $2}' | cut -d ":" -f 1)

if [ "$wgcf_card" == "wgcf" ]; then
  wg_card="wgcf"
elif [ "$warp_card" == "warp" ]; then
  wg_card="warp"
#elif [ -z "$wgcf_card" ] && [ -z "$warp_card" ]; then
else
  wg_card=$net_card
fi



fix_wg_ipv6_RTNETLINK(){
cat >>/etc/sysctl.conf<<EOF
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
EOF
sysctl -p
}
sleep 5
wg='apt update -y ; apt upgrade -y ; apt install iptables wireguard -y ; wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf ;  sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg0.conf   ; wg-quick up wg0 ; systemctl enable wg-quick@wg0.service;wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf ; sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg1.conf ;  wg-quick up wg1 ; systemctl enable wg-quick@wg1.service;  wget --inet4-only -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf ; sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg2.conf ; wg-quick up wg2 ; systemctl enable wg-quick@wg2.service;sysctl -p /etc/sysctl.conf ;  sysctl -p '

wg-quick down wg0; wg-quick down wg1;wg-quick down wg2; fix_wg_ipv6_RTNETLINK ;
eval $wg 
bash  <(curl -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wgiptabels.sh ) 
bash  <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)
/sbin/sysctl -p 

###########wg  end

########### vmess 
#bash <(curl -4fSsL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_mianliu_only_vmess_80_DD.sh )

#  docker version

#if [ "$REPLY" -eq 1 ]; then
#    # commands for when REPLY equals 1
#    echo "You selected option 1"
bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_vmess_80_ws_docker_startup.sh )  
#else
#bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vmess_D/xray_vmess_80_ws_docker_openai_ss_65504.sh) 
## Define the configuration file path
#CONFIG_PATH="/root/xray_docker_d/config.yml"
#
## Check if config file exists at the specified path
#if [ ! -f "$CONFIG_PATH" ]; then
#    echo "Error: config.yml not found at $CONFIG_PATH"
#    exit 1
#fi
#
### Prompt for IP/Domain input
##read -p "Please enter the IP or domain to replace OPENAI_IP_DOMAIN: " new_domain
#
### Validate input is not empty
##if [ -z "$new_domain" ]; then
##    echo "Error: Input cannot be empty"
##    exit 1
##fi
#
## Create backup of original file
#cp "$CONFIG_PATH" "${CONFIG_PATH}.backup"
#
## Replace the text using sed
## Note: Using different delimiter (|) since the path might contain forward slashes
#sed -i "s|OPENAI_IP_DOMAIN|$new_domain|g" "$CONFIG_PATH"
#
## Check if replacement was successful
#if [ $? -eq 0 ]; then
#    echo "Successfully replaced OPENAI_IP_DOMAIN with $new_domain"
#    echo "A backup of the original file has been created as ${CONFIG_PATH}.backup"
#else
#    echo "Error occurred during replacement"
#    # Restore from backup
#    mv "${CONFIG_PATH}.backup" "$CONFIG_PATH"
#  # exit 1
#fi
#
## Make sure the config file has correct permissions
#chmod 644 "$CONFIG_PATH"
#cd /root/xray_docker_d/
#docker-compose down
#sleep 2 
#docker-compose up -d
#cd  $HOME
#fi
#




########### vmess end

#  dns_test_claude.sh
bash  <(curl -4Lk   'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/dns_test_claude.sh' )

bash  <(curl -4Lk   'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ss-rust-launch-tcp-only.sh'  )

bash  <(curl -4Lk  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/openvpn-server_z_good_claude_D/start_up_openvpn-server_z.sh )

# 106) 7777 
bash  <(curl -4Lsk  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/upload_folder_d/run_docker_compose.sh) 
# 101)
bash  <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/start_jupyter166_1666_instances.sh ) 
bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_render_dockerfile/markdown_render_docker.sh) 

#  setup_7788_web_download_docker.sh
bash  <(curl -4Lk  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/7788_web_download_docker_claude/setup_7788_web_download_docker.sh )


cat << "EOF" >> /etc/resolv.conf
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
EOF

## compose v2 install
bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_docker_compose_v2_claude.sh )  

bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/tmux_install.sh  )

# Define the unique identifier
unique_id_bashrc="echo_To_bashrc_txt_unique_id_bashrc"

# Check if the unique identifier exists in ~/.bashrc
if grep -q "$unique_id_bashrc" ~/.bashrc; then
    echo "Unique identifier found in ~/.bashrc. Ignoring."
else
    # If the unique identifier doesn't exist, append the content to ~/.bashrc
    echo "Unique identifier not found in ~/.bashrc. Adding."
    echo  export setup_time_first=\"`date`\" >> ~/.bashrc
    curl -sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/echo_To_bashrc.txt >> ~/.bashrc
fi


bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/fzf_d/config_fzf.sh  ) 

bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/swapDD.sh  )


curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/python_D/cleanpy.sh > /usr/bin/cpy
chmod +x /usr/bin/cpy


 bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/disable_ssh_password.sh ) 


 bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vifm_installer.sh )     


reboot






