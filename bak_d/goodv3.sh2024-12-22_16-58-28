#!/usr/bin/bash
#!/bin/bash

# Get country code (e.g., HK, TW, JP)
country_code_UPPER=$(echo "$country_code" | tr '[:lower:]' '[:upper:]')  # Ensure uppercase

# Convert to flag emoji
# This works by converting each letter to its regional indicator Unicode character
first_char=$(printf "\U$(printf %x $(( $(printf "%d" "'${country_code_UPPER:0:1}") + 127397 )) )")
second_char=$(printf "\U$(printf %x $(( $(printf "%d" "'${country_code_UPPER:1:1}") + 127397 )) )")

# Display the emoji
flag_emoji="${first_char}${second_char}"
#echo "$flag_emoji"

docker_vmess_80_openai_65504(){
#!/bin/bash
#read -p "Please enter the IP or domain to replace OPENAI_IP_DOMAIN: " new_domain
read -p "openai: ss 65504  IP or domain: " new_domain
bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vmess_D/xray_vmess_80_ws_docker_openai_ss_65504.sh ) 

# Define the configuration file path
CONFIG_PATH="/root/xray_docker_d/config.yml"

# Check if config file exists at the specified path
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: config.yml not found at $CONFIG_PATH"
    exit 1
fi

# Prompt for IP/Domain input

# Validate input is not empty
if [ -z "$new_domain" ]; then
    echo "Error: Input cannot be empty"
    exit 1
fi

# Create backup of original file
cp "$CONFIG_PATH" "${CONFIG_PATH}.backup"

# Replace the text using sed
# Note: Using different delimiter (|) since the path might contain forward slashes
sed -i "s|OPENAI_IP_DOMAIN|$new_domain|g" "$CONFIG_PATH"

# Check if replacement was successful
if [ $? -eq 0 ]; then
    echo "Successfully replaced OPENAI_IP_DOMAIN with $new_domain"
    echo "A backup of the original file has been created as ${CONFIG_PATH}.backup"
else
    echo "Error occurred during replacement"
    # Restore from backup
    mv "${CONFIG_PATH}.backup" "$CONFIG_PATH"
    exit 1
fi

# Make sure the config file has correct permissions
chmod 777 "$CONFIG_PATH"

cd /root/xray_docker_d/
docker-compose down
docker-compose pull
sleep 3
docker-compose up -d
}





#`echo -e "        \e[1;38;2;252;33;137m$(hostname)\e[0m         \e[38;2;247;47;244m$(pwd)\e[0m            "
#  `  今天运行/总运行 $today_hit / $all_hit
##`echo -e "    \e[1;38;2;252;33;137m$(hostname)\e[0m    "`  今天运行/总运行 $today_hit / $all_hit
#	eval  'rm -fr  ~/.ssh ;mkdir  ~/.ssh ; echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lMkBC39ZW0RFnZZQCrfW2g2mGa2a8TvVd9d+UAfC13oybzrQ4oTEGnJbfhUneDHlo2/sPqN+WsI+xV9bKvUqfv8UfzBk12gB8JRH+gEaj98GqMdiF7YsHLOTDSyUZOEF0WdGORjAFPYOylEQWG/4rDJz7HHTNVoFp5qt8l542ldbSRTNWu8XWsSivEDDkYeb0FeAntn/biz3wXQmwz3myKNcEEBy3UfeysMGDvy/1noL9SQIuyB0Biwtuw4AstykUvoH0AP3nlSc4Cey/n3neCl8di+SBjzWUsICPmJkUQY7szzkFYUbChSO3A9lfmHpJsEGzDiLsF3v2Xdi3UfmfB1MumarW5byR18+KGL2QhCESqLffSONuCQ9UjJdVgdhyKfTTYkjIg8gJ9+1zJbJQq0MBQZw3WQCvyeiaxK/lOAL8CgHGuWDMfshwBgAxiU5mnGICdc253Bdr0pYG3R8CYJZvRmdSfygSZXv3EYDXu1Cz3NBDfdeAU2x6SFygE8= " > ~/.ssh/authorized_keys; sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/g"  /etc/ssh/sshd_config;sed -i "s/#Port 22/Port 54322/g"  /etc/ssh/sshd_config ;sed -i "s/Port 22/Port 54322/g"  /etc/ssh/sshd_config ; sed -i "s/PermitRootLogin no/PermitRootLogin yes/g"  /etc/ssh/sshd_config ; systemctl restart sshd' ;

#	echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdbCXW2H3AwV6g9N1FXJp1/8EfWQbSJUuIbdHPoBgMU" >> ~/.ssh/authorized_keys; 

Bold_prefix="\033[1m"

Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"



ps_filter() {
    read -p "Enter a string to filter: " input_string
    if [ -z "$input_string" ]; then
        ps aux
    else
        ps aux | grep "$input_string"
    fi
}

#       netstat -lpntuae
netstat_filter() {
    read -p "Enter a string to filter: " input_string
    if [ -z "$input_string" ]; then
	    netstat -lpntu
    else
        netstat -lpntu | grep "$input_string"
    fi
}


netstat_filter_quick() {
    netstat -lpntu | grep -v "Active" | grep -v "Proto" | \
    awk '{
        # Add line type for sorting (1=udp6, 2=udp, 3=tcp6, 4=tcp)
        if ($1=="udp6") type=1;
        else if ($1=="udp") type=2;
        else if ($1=="tcp6") type=3;
        else if ($1=="tcp") type=4;
        # Extract port number after colon
        split($4,port,":");
        # Print with type and port for sorting
        printf "%d %s %s\n", type, port[2], $0;
    }' | \
    sort -k1,1n -k2,2n | \
    cut -d' ' -f3-
}




# Function to resolve domain to IP address
resolve_domain_to_ip() {
  local domain="$1"
  local ip_address=$(dig +short "$domain")
  if [[ -n "$ip_address" ]]; then
    echo ""  >&2 
    echo "$ip_address"
  else
    echo "Failed to resolve IP for domain $domain."
    return 1
  fi
}

# Function to get the fraud score
get_fraud_score() {
  local input="$1"
  local curl_output
  local fraud_score
  local ip_address

  if [[ -z "$input" ]]; then
    ip_address=$(curl -s ifconfig.me)
  elif [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip_address="$input"
  else
    ip_address=$(resolve_domain_to_ip "$input")
    if [[ $? -ne 0 ]]; then
      echo "Failed to resolve domain to IP."
      return 1
    fi
  fi

  curl_output=$(curl -s "https://scamalytics.com/ip/${ip_address}")
  fraud_score=$(echo "$curl_output" | perl -nle 'print $& if m{Fraud Score: (\d+)}')

  if [[ -n "$fraud_score" ]]; then
    echo ""
    echo "IP: ${ip_address}"
    echo "${fraud_score}"
    echo ""
  else
    echo "Fraud Score could not be determined."
  fi
}




## Function to resolve domain to IP address using nslookup
#resolve_domain_to_ip() {
#  local domain="$1"
#  local ip_address=$(nslookup "$domain" | awk '/^Address: / { print $2 }')
#  echo " "
#  echo "$ip_address"
#}
#
## Function to get the fraud score
#get_fraud_score() {
#  local input="$1"
#  local curl_output
#  local fraud_score
#  local ip_address
#
#  if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
#    ip_address="$input"
#  else
#    ip_address=$(resolve_domain_to_ip "$input")
#    if [[ -z "$ip_address" ]]; then
#      echo "Failed to resolve domain to IP."
#      return 1
#    fi
#  fi
#
#  curl_output=$(curl -s "https://scamalytics.com/ip/${ip_address}")
#  fraud_score=$(echo "$curl_output" | perl -nle 'print $& if m{Fraud Score: (\d+)}')
#
#  if [[ -n "$fraud_score" ]]; then
#    echo ""
#    echo "IP: ${ip_address}"
#    echo "${fraud_score}"
#    echo ""
#  else
#    echo ""
#    echo "Fraud Score could not be determined."
#    echo ""
#  fi
#}




## Function to get the fraud score
#get_fraud_score() {
#  local input="$1"
#  local curl_output
#  local fraud_score
#  local ip_address
#
#  if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
#    ip_address="$input"
#  else
#    ip_address=$(resolve_domain_to_ip "$input")
#    if [[ -z "$ip_address" ]]; then
#      echo "Failed to resolve domain to IP."
#      return 1
#    fi
#  fi
#
#  curl_output=$(curl -s "https://scamalytics.com/ip/${ip_address}")
#  fraud_score=$(echo "$curl_output" | grep -oP 'Fraud Score: \K\d+')
#  
#  if [[ -n "$fraud_score" ]]; then
#    echo "IP: ${ip_address}"
#    echo "Fraud Score: ${fraud_score}"
#  else
#    echo "Fraud Score could not be determined."
#  fi
#}




## Function to get the fraud score
#get_fraud_score() {
#  local input="$1"
#  local curl_output
#  local fraud_score
#  local ip_address
#
#  if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
#    ip_address="$input"
#  else
#    ip_address=$(resolve_domain_to_ip "$input")
#    if [[ -z "$ip_address" ]]; then
#      echo "Failed to resolve domain to IP."
#      return 1
#    fi
#  fi
#
#  curl_output=$(curl -s "https://scamalytics.com/ip/${ip_address}")
#  fraud_score=$(echo "$curl_output" | grep -oP 'Fraud Score: \K\d+')
#  
#  if [[ -n "$fraud_score" ]]; then
#    echo "Fraud Score: ${fraud_score}"
#  else
#    echo "Fraud Score could not be determined."
#  fi
#}

# Function to be triggered by the 88th option
option_88_function() {
  echo "Enter IP or Domain (Leave blank for current VPS IP):"
  read user_input

  if [[ -z "$user_input" ]]; then
    # Automatically get the IP address of the current VPS
    user_input=$(curl -s ifconfig.me)
  fi

  get_fraud_score "$user_input"
}



#prefer_ipv4() {
#  # Check for root privileges
#  if [ "$EUID" -ne 0 ]; then
#    echo "Please run as root"
#    return 1
#  fi
#
#  # Add the precedence line to /etc/gai.conf
#  echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
#
#  # Restart the networking service
#  systemctl restart networking
#
#  echo "IPv4 is now preferred over IPv6 and networking service is restarted."
#}


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







#https://bodhilinux.boards.net/thread/450/wireguard-rtnetlink-answers-permission-denied
fix_wg_ipv6_RTNETLINK(){
cat >>/etc/sysctl.conf<<EOF
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
EOF
sysctl -p

}


today_all=$(curl -s --max-time 10 "https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fraw.githubusercontent.com%2FHelloWorldWinning%2Fvps&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false" | tail -3 | head -n 1 | awk '{print $5,$7}')
#echo $today_all

today_hit=$(echo "${today_all}"|cut -d" " -f1)
all_hit=$(echo "${today_all}"|cut -d" " -f2)




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





# apt-get install wget --inet4-only 
# 26)eval 'apt update;apt install -y wget --inet4-only curl git  vim tree lsof sudo htop rsync screen jq net-tools telnet' ;;


get_az_api='方法1：使用cloudshell by Powershell
多订阅：az ad sp create-for-rbac --role owner --scopes /subscriptions/订阅ID
单订阅：$sub_id=$(az account list --query [].id -o tsv) ; az ad sp create-for-rbac --role owner --scopes /subscriptions/$sub_id

方法2：cloudshell by Bash

sub_id=$(az account list --query [].id -o tsv) && az ad sp create-for-rbac --role contributor --scopes /subscriptions/$sub_id'


#80_VLESS-WSS-Nginx='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/80_VLESS-WSS-Nginx.sh)'

new_nginx_conf='bash <(curl -4 -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/new_nginx_conf.sh )'
new_nginx_conf_docker='bash <(curl -4 -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/new_nginx_conf_docker.sh )'

tuic='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tuic.sh )'
hy_mine='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/hy_mine.sh )'
probe_x='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/probe_x.sh )'

modify_id_of_v2ray='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/modify_id_of_v2ray.sh)'
install_freenom='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_freenom.sh)'
install_nginx='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_nginx.sh)'

docker_socks5_serjs='docker run -d --name socks5 -p 10869:1080 -e PROXY_USER=10869 -e PROXY_PASSWORD=10869 serjs/go-socks5-proxy'


#aws_arm_dd='bash <(wget --inet4-only --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 12 -v 64 -p "1" -port "54322" -console ttyS0,115200'
aws_arm_dd='bash <(wget --inet4-only --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 12 -v 64 -p "weijingweiyi" -port "54322" -console ttyS0,115200'


realm2='wget --inet4-only -N --no-check-certificate https://git.io/realm.sh && chmod +x realm.sh && ./realm.sh'


azure_create='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/azure_create.sh)'

html='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/html.sh)'

ping_local_fast='bash <(curl -sSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ping_local_fast.sh)'

ss_rust2='bash <(curl -fsSL  https://raw.githubusercontent.com/xOS/Shadowsocks-Rust/master/ss-rust.sh)'


pre_InstallNET_modified_chu='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/pre_InstallNET_modified_chu.sh)'
pre_InstallNET_modified_chu_debian12='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/pre_InstallNET_modified_chu_debian12.sh )'


dd_debian11='bash <(wget --inet4-only --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 11 -v 64 -p "1" -port "54322"'

xray_mianliu='bash <(curl -fsSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_mianliu.sh)'


trojan_go_mianliu='bash <(curl -fsSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/trojan_go_mianliu.sh)'

tcpx121721='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tcp131721.sh)'

jobs_spiders='wget --inet4-only --no-check-certificate -O ~/jobs_spiders.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jobs_spiders.sh   && chmod +x ~/jobs_spiders.sh  && ~/jobs_spiders.sh && source ~/.bashrc  '


ping_local='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ping_local.sh)'



superspeed_uxh='bash <(curl -fsSL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/superspeed_uxh.sh)'


hysteria='bash <(curl -fsSL https://git.io/hysteria.sh)'


delete_user='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/delete_user.sh)'

rdp='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/rdp.sh)'





ss_rust='wget --inet4-only -N --no-check-certificate -c -t3 -T60 -O ss-plugins.sh https://git.io/fjlbl && chmod +x ss-plugins.sh && ./ss-plugins.sh'

#Linux_tools='wget --inet4-only -N --no-check-certificate https://raw.githubusercontents.com/Misaka-blog/MisakaLinuxToolbox/master/MisakaToolbox.sh && bash MisakaToolbox.sh'
Linux_tools='wget --inet4-only -N --no-check-certificate https://gitlab.com/misakablog/vps-toolbox/-/raw/main/MisakaToolbox.sh && bash MisakaToolbox.sh'

 
iptables_rules='bash <(curl -sL   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/iptables.sh)'
 
disable_all_wg_servers='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/disable_all_wg_servers.sh)'


latest_arm_kernel='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/latest_arm_kernel.sh)'


debian_tools='source <(curl -ipv4 -sL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/debian_tools ) '

bashrc='source <(curl -sL   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/bashrc ) '


jupyter_notebook_remote_access='bash <(curl -sL     https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jupyter_notebook_remote_access.sh)'

install_docker_ccaa='bash <(curl -sL     https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_docker_ccaa.sh)'


install_docker='yes|bash <(curl -sL     https://raw.githubusercontent.com/HelloWorldWinning/vps/main/docker.sh)'

ping_ip='bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ping_ip.sh)'

#isp_checker2='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/isp_checker)'

isp_checker2='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/credit.sh)'





#bierendegongju='wget --inet4-only -O jcnfbox.sh https://raw.githubusercontent.com/Netflixxp/jcnf-box/main/jcnfbox.sh && chmod +x jcnfbox.sh && clear && ./jcnfbox.sh'

bierendegongju1='bash <(curl -Ss https://www.idleleo.com/install.sh)'
bierendegongju2='wget --inet4-only -P /root -N --no-check-certificate "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh'

update_Aria2='crontab -l > conf && echo  -e "* */4 * * *   bash /etc/ccaa/upbt.sh >> /tmp/tmp.txt" >> conf && crontab conf && rm -f conf'

Aria2='bash <(curl -Lsk https://raw.githubusercontent.com/helloxz/ccaa/master/ccaa.sh)'

isp_ip='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/isp_ip.sh) | head -25'

ipv4_v6_forwarding='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)'

oc_ipv4_v6_forwarding='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/oc_ip_forwarding.sh)'


open_ipv6='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/open_ipv6.sh)'

xui='bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)'

ss_rust='wget --inet4-only -N --no-check-certificate -c -t3 -T60 -O ss-plugins.sh https://git.io/fjlbl && chmod +x ss-plugins.sh && bash ss-plugins.sh'

#nfFree='wget --inet4-only -N https://cdn.jsdelivr.net/gh/fscarmen/warp/menu.sh && bash menu.sh '
#nfFree='wget -N https://raw.githubusercontent.com/fscarmen/warp/main/menu.sh && bash menu.sh'
nfFree='wget -N               https://cdn.jsdelivr.net/gh/fscarmen/warp/menu.sh && bash menu.sh'

#nf_free2='wget --inet4-only -N https://cdn.jsdelivr.net/gh/kkkyg/CFwarp/CFwarp.sh && bash CFwarp.sh'
nf_free2='bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)'
nf_free3='bash <(curl -fsSL git.io/warp.sh) menu'

#nfFree='bash <(curl -sSL https://raw.githubusercontent.com/fscarmen/tools/main/a.sh)'

#nf='bash <(curl -L -s https://raw.githubusercontent.com/lmc1000/RegionRestrictionCheck/main/check.sh)'
#nf='bash <(curl -L -s check.unlock.media)'
nf='bash <(curl -L -s media.ispvps.com)'

s5='wget --inet4-only --no-check-certificate -O gost.sh https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh && chmod +x gost.sh && ~/gost.sh'


# dd_oracle='bash <(wget --inet4-only --no-check-certificate -qO- 'https://moeclub.org/attachment/LinuxShell/InstallNET.sh') -d 11 -v 64 -a -p  1'


dd_oracle='bash <(wget --inet4-only --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/dd_oracle_arm.sh') -d 11 -v 64 -a -p  1'

# dd_1='wget --inet4-only --no-check-certificate -O AutoReinstall.sh https://git.io/AutoReinstall.sh && bash AutoReinstall.sh'

dd_1='wget --inet4-only --no-check-certificate -O AutoReinstall.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/AutoReinstall2.sh && bash AutoReinstall.sh'

dd='wget --inet4-only --no-check-certificate -O AutoReinstall.sh https://raw.githubusercontent.com/HelloWorldWinning/vps/main/AutoReinstall.sh && chmod a+x AutoReinstall.sh && bash AutoReinstall.sh'

# tcpx='wget --inet4-only -N --no-check-certificate "https://github.000060000.xyz/tcpx.sh" && chmod +x tcpx.sh && ./tcpx.sh'

tcpx='bash <(curl -fSsL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tcpx_modified.sh)'



realm='wget --inet4-only -N --no-check-certificate https://git.io/realm.sh && chmod +x realm.sh && ./realm.sh'
xray='bash <(curl -sL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xrayMINE)'
# xray='bash <(curl -sL  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_vless.sh)'

#trojan='bash <(curl -sL https://s.hijk.art/trojan-go.sh)'

trojan='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/trojan-go.sh)'

# speed='curl -Lso- -no-check-certificate https://raw.githubusercontent.com/oooldking/script/master/superbench.sh | bash'

speed='curl -Lso- -no-check-certificate https://raw.githubusercontent.com/HelloWorldWinning/vps/main/speed5.sh | bash'
# speed2='bash <(curl -Lso- https://git.io/Jlkmw)'
speed2='bash <(curl -Lso-  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/speed17.sh) |tee speed2.log'
#speed3='wget --inet4-only -qO- bench.sh | bash |tee speed3.log'
speed3='bash <(curl -Lso-  bench.sh) |tee speed3.log'

# wg='wget --inet4-only --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -r && bash  ~/wireguard.sh  -u && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf &&  sed -i 's/eth0/${net_card}/g'  /etc/wireguard/wg0.conf   &&wg-quick up wg0 && wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf && sed -i 's/eth0/${net_card}/g'  /etc/wireguard/wg1.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service'
# wg='wget --inet4-only --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -s && bash  ~/wireguard.sh  -u && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf &&  sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg0.conf   &&wg-quick up wg0 && wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf && sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg1.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service;  wget --inet4-only -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf && sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg2.conf && wg-quick up wg2 && systemctl enable wg-quick@wg2.service'

wg61='wget --inet4-only --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh ; chmod 755  ~/wireguard.sh ; bash ~/wireguard.sh -s ; bash  ~/wireguard.sh  -u ; wg-quick down wg0  ; mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111_oringal.conf  ; wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf ;  sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg0.conf   ; wg-quick up wg0 ; systemctl enable wg-quick@wg0.service;wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf ; sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg1.conf ;  wg-quick up wg1 ; systemctl enable wg-quick@wg1.service;  wget --inet4-only -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf ; sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg2.conf ; wg-quick up wg2 ; systemctl enable wg-quick@wg2.service; sysctl -p /etc/sysctl.conf '

#backup wg='apt update -y && apt upgrade -y && apt install iptables wireguard -y ; wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf ;  sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg0.conf   ; wg-quick up wg0 ; systemctl enable wg-quick@wg0.service;wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf ; sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg1.conf ;  wg-quick up wg1 ; systemctl enable wg-quick@wg1.service;  wget --inet4-only -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf ; sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg2.conf ; wg-quick up wg2 ; systemctl enable wg-quick@wg2.service;sysctl -p /etc/sysctl.conf ;  sysctl -p '

#wg='apt update -y && apt upgrade -y && apt install iptables wireguard -y ; wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf ;  sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg0.conf   ; wg-quick up wg0 ; systemctl enable wg-quick@wg0.service;wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf ; sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg1.conf ;  wg-quick up wg1 ; systemctl enable wg-quick@wg1.service;  wget --inet4-only -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf ; sed -i "s/eth0/${net_card}/g"  /etc/wireguard/wg2.conf ; wg-quick up wg2 ; systemctl enable wg-quick@wg2.service;sysctl -p /etc/sysctl.conf ;  sysctl -p '

#### good wg='apt update -y && apt upgrade -y && apt install iptables wireguard -y ; wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf ;  sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg0.conf   ; wg-quick up wg0 ; systemctl enable wg-quick@wg0.service;wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf ; sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg1.conf ;  wg-quick up wg1 ; systemctl enable wg-quick@wg1.service;  wget --inet4-only -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf ; sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg2.conf ; wg-quick up wg2 ; systemctl enable wg-quick@wg2.service;sysctl -p /etc/sysctl.conf ;  sysctl -p '
wg='apt update -y ; apt upgrade -y ; apt install iptables wireguard -y ; wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0.conf ;  sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg0.conf   ; wg-quick up wg0 ; systemctl enable wg-quick@wg0.service;wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1.conf ; sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg1.conf ;  wg-quick up wg1 ; systemctl enable wg-quick@wg1.service;  wget --inet4-only -O  /etc/wireguard/wg2.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg2.conf ; sed -i "s/eth0/${wg_card}/g"  /etc/wireguard/wg2.conf ; wg-quick up wg2 ; systemctl enable wg-quick@wg2.service;sysctl -p /etc/sysctl.conf ;  sysctl -p '

wg_to_wgcf='wget --inet4-only --no-check-certificate -O ~/wireguard.sh https://raw.githubusercontent.com/teddysun/across/master/wireguard.sh && chmod 755  ~/wireguard.sh && bash ~/wireguard.sh -s && wg-quick down wg0   &&  mv  /etc/wireguard/wg0.conf   /etc/wireguard/wg111.conf   && wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_wgcf.conf && wg-quick up wg0 && wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_wgcf.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service'

wg_after_warp=' wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_wgcf.conf && wg-quick up wg0  && wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_wgcf.conf && wg-quick up wg1 && systemctl enable wg-quick@wg1.service  && systemctl enable wg-quick@wg0.service'

wg_for_oracle='wget --inet4-only -O  /etc/wireguard/wg0.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg0_enp0s3.conf && wg-quick up wg0  ; wget --inet4-only -O  /etc/wireguard/wg1.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg1_enp0s3.conf ; wg-quick up wg1; systemctl enable wg-quick@wg1.service  ; systemctl enable wg-quick@wg0.service'

openvpn='bash <(curl -sL https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh )'
openvpn2='wget --inet4-only https://git.io/vpn -O openvpn-install.sh && bash openvpn-install.sh'
v2ray='bash <(curl -s -L https://git.io/v2ray.sh)'

#kcptun='wget --inet4-only --no-check-certificate https://github.com/kuoruan/shell-scripts/raw/master/kcptun/kcptun.sh &&chmod +x ~/kcptun.sh &&bash ~/kcptun.sh'
kcptun='bash <(curl -s -L https://raw.githubusercontent.com/HelloWorldWinning/vps/main/kcptun_modified.sh)'

ss_go='wget --inet4-only -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ss-go.sh && chmod +x ss-go.sh && bash ss-go.sh'
ss_latest='bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ss.sh)'
ssr='wget --inet4-only -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/ssr.sh && chmod +x ssr.sh && bash ssr.sh'
 




##		#6.1) eval $wg ; eval $ipv4_v6_forwarding;crontab -l > conf && echo  -e "50 5 * * *   bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/restart_wg_everyday.sh)  >/root/feedback_restart_wg_everyday.txt" >> conf && crontab conf && rm -f conf; bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/restart_wg_everyday.sh) ;;
##		6) eval $wg61 ; eval $ipv4_v6_forwarding;crontab -l > conf && echo  -e "55 5 * * *   bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/restart_wg_everyday.sh)  >/root/feedback_restart_wg_everyday.txt" >> conf && crontab conf && rm -f conf; bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/restart_wg_everyday.sh) ;;







while true
do
read  -p "$(echo -e "请选择

${Red_font_prefix}222${Font_color_suffix} tcpx
${Red_font_prefix}62${Font_color_suffix} trojan
${Red_font_prefix}63${Font_color_suffix} xray
${Red_font_prefix}64${Font_color_suffix} realm 中转用
${Red_font_prefix}5${Font_color_suffix} network_monitor_openai.sh  
${Red_font_prefix}55${Font_color_suffix} 回程路由测试 https://github.com/vpsxb/testrace
${Red_font_prefix}555${Font_color_suffix}  wget -qO- bench.sh | bash | tee benchspeed.log
${Red_font_prefix}6${Font_color_suffix} apt install wireguard
${Red_font_prefix}6.1${Font_color_suffix} wg teddysun/across/master/wireguard.sh https://github.com/teddysun/across 
${Red_font_prefix}7z${Font_color_suffix} docker: start_up_openvpn-server_z.sh
${Red_font_prefix}7.0${Font_color_suffix} openvpn angristan/openvpn-install/
${Red_font_prefix}7.1${Font_color_suffix} openvpn Nyr / openvpn-install
${Red_font_prefix}50${Font_color_suffix} v2ray
${Red_font_prefix}8.1${Font_color_suffix} modify_id_of_v2ray
${Red_font_prefix}999${Font_color_suffix} kcptun
${Red_font_prefix}10${Font_color_suffix} ss_go
${Red_font_prefix}11o${Font_color_suffix} dd  aws/aws windows   ,甲骨文, 用默(DHCP) , , GCP 子网掩码mask 255.255.255.0
${Red_font_prefix}11${Font_color_suffix} bash <(wget --inet4-only --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/InstallNET_modified_chu.sh') -d 11 -v 64 -p "1" -port "54322"  --ip-mask     --ip-gate  255.255.255.0    --ip-addr   
${Red_font_prefix}12${Font_color_suffix} dd_1 azure用默认
${Red_font_prefix}13${Font_color_suffix} gost s5 socks5代理用
${Red_font_prefix}13.1${Font_color_suffix}reaml2 转发
${Red_font_prefix}14${Font_color_suffix} netflix available test
${Red_font_prefix}15${Font_color_suffix} nf freedom
${Red_font_prefix}16${Font_color_suffix} ss_rust
${Red_font_prefix}17${Font_color_suffix} speed2   of vps 全网/三网
${Red_font_prefix}18${Font_color_suffix} wg to wgcf 有wgcf 解锁nf 情况用
${Red_font_prefix}19${Font_color_suffix} x ui 面板
${Red_font_prefix}20${Font_color_suffix} open ipv6
${Red_font_prefix}21${Font_color_suffix} 甬哥 netflix free
${Red_font_prefix}221${Font_color_suffix} P3terx  netflix free
${Red_font_prefix}23${Font_color_suffix} 先 warp 再 wg
${Red_font_prefix}24${Font_color_suffix} ipv4 v6转发
${Red_font_prefix}25${Font_color_suffix} xray 换统一的uuid 并且 重启
${Red_font_prefix}26${Font_color_suffix} 安装   wget --inet4-only curl vim tree lsof  sudo htop rsync screen jq net-tools
${Red_font_prefix}27${Font_color_suffix} dd后. /etc/ssh/sshd_config  systemctl restart sshd 新建 ~/.ssh,覆盖安装
${Red_font_prefix}28${Font_color_suffix} wg 甲骨文网卡enp0s3专用
${Red_font_prefix}29${Font_color_suffix} dd甲骨文 debian 11 密码是:1
${Red_font_prefix}30${Font_color_suffix} 秋水逸冰大佬的写的Bench.sh脚本
${Red_font_prefix}31${Font_color_suffix} s.hijk.art的最新ss脚本
${Red_font_prefix}32${Font_color_suffix} ssr 多用户脚本
${Red_font_prefix}33${Font_color_suffix} isp ipdata.co check
${Red_font_prefix}34${Font_color_suffix} 网盘 Aria2秘密安装时候设定。ccaa:进入CCAA操作界面 ；文件管理默认用户名为ccaa，密码为admin，登录后可在后台修改
${Red_font_prefix}35${Font_color_suffix} 自动更新${Red_font_prefix}34${Font_color_suffix}的Aria2，bash /etc/ccaa/upbt.sh >> /tmp/tmp.txt
${Red_font_prefix}36${Font_color_suffix} 甲骨文 ipv4 v6转发 enp0s3网卡
${Red_font_prefix}37${Font_color_suffix} 37.1 37.2 别人的vps 工具包 
${Red_font_prefix}38${Font_color_suffix} https://www.ip2location.com/ check
${Red_font_prefix}39${Font_color_suffix} https://www.boce.com/ping/  | jq 'del(.. | .report_source?)'
${Red_font_prefix}40${Font_color_suffix} sysctl -p /etc/sysctl.conf
${Red_font_prefix}41${Font_color_suffix} install docker
${Red_font_prefix}41.1${Font_color_suffix} install nginx
${Red_font_prefix}41.2${Font_color_suffix} docker MySQL MyNodeQuery
${Red_font_prefix}42${Font_color_suffix} install_docker_ccaa
${Red_font_prefix}43${Font_color_suffix} wget --inet4-only bashrc 。手工输入  source  ~/.bashrc
${Red_font_prefix}44${Font_color_suffix} enable jupyter_notebook_remote_access  jupyter notebook   --port=16666 --ip 0.0.0.0 --no-browser --allow-root
${Red_font_prefix}45${Font_color_suffix} 升级到最新的 armv8 debian系统
${Red_font_prefix}46${Font_color_suffix} systemctl stop wg-quick@${wg_i} systemctl disable wg-quick@${wg_i}   systemctl stop and disable all wg
${Red_font_prefix}47${Font_color_suffix} iptables -P  INPUT/OUTPUT/FORWARD  ACCEPT
${Red_font_prefix}48${Font_color_suffix} Misaka Linux VPS tools
${Red_font_prefix}49${Font_color_suffix} shadowrocket rust + many plugins(kcptun...)
${Red_font_prefix}8${Font_color_suffix} eval "netstat -lpntu"
${Red_font_prefix}tt${Font_color_suffix} "read -p "script to run ":  ${x}"
${Red_font_prefix}56${Font_color_suffix} rdp_docker_33399.sh
${Red_font_prefix}566${Font_color_suffix} (amd64)一键安装 远程桌面 echo xfce4-session>/home/<rdp_username>/.xsession ; sudo service xrdp stop /status
${Red_font_prefix}57${Font_color_suffix} delete user  'getent passwd | awk -F: '{ print \$1}'|sort'
${Red_font_prefix}58${Font_color_suffix} bash <(curl -fsSL https://git.io/hysteria.sh)
${Red_font_prefix}581${Font_color_suffix} install_hysteria HyNetwork  
${Red_font_prefix}582${Font_color_suffix} install_hysteria mine
${Red_font_prefix}59${Font_color_suffix} superspeed_uxh.sh 
${Red_font_prefix}60${Font_color_suffix} ping_local
${Red_font_prefix}611${Font_color_suffix} 一键工作爬虫搞定 source ~/.bashrc  jobs_spiders  jupyter notebook password
${Red_font_prefix}61${Font_color_suffix} mini_conda.sh
${Red_font_prefix}1111${Font_color_suffix} 一键搞定13 17 21,需要reboot
${Red_font_prefix}1${Font_color_suffix} tcpc 脚本
${Red_font_prefix}mianliu2${Font_color_suffix} trojan_go ws ${Red_font_prefix}免流${Font_color_suffix}
${Red_font_prefix}3${Font_color_suffix} xray ${Red_font_prefix}免流${Font_color_suffix}
${Red_font_prefix}d80${Font_color_suffix} docker xray ${Red_font_prefix}免流${Font_color_suffix}  xray_vmess_80_ws_docker_startup.sh 
${Red_font_prefix}d80ai${Font_color_suffix} docker xray ${Red_font_prefix}免流${Font_color_suffix}  xray_vmess_80_ws_docker_startup.sh 
${Red_font_prefix}65504${Font_color_suffix} docker ss-rust-launch-tcp-only.sh
${Red_font_prefix}444${Font_color_suffix} 可以检查mask ip gate ${Red_font_prefix}DD${Font_color_suffix}
${Red_font_prefix}412${Font_color_suffix} 可以检查mask ip gate ${Red_font_prefix}DD debian12${Font_color_suffix}
${Red_font_prefix}65${Font_color_suffix} ss_rust
${Red_font_prefix}66${Font_color_suffix} parallel ping_local_fast.sh
${Red_font_prefix}67${Font_color_suffix} html
${Red_font_prefix}68${Font_color_suffix} azure relative
${Red_font_prefix}69${Font_color_suffix} aws_arm_dd ${Red_font_prefix}ARM${Font_color_suffix}
${Red_font_prefix}70${Font_color_suffix} docker_socks5_serjs
${Red_font_prefix}71${Font_color_suffix} install_freenom.sh
${Red_font_prefix}72${Font_color_suffix} rename vps
${Red_font_prefix}7${Font_color_suffix} receive on 9
${Red_font_prefix}9${Font_color_suffix} send on 9
${Red_font_prefix}75${Font_color_suffix} docker azure panel ip:8888  1 19860826
${Red_font_prefix}75.1${Font_color_suffix} echo get az  api 
${Red_font_prefix}76${Font_color_suffix} aws   panel http://ip:8011 admin admin123456
${Red_font_prefix}1777${Font_color_suffix} tuic
${Red_font_prefix}78${Font_color_suffix} new_nginx_conf.sh
${Red_font_prefix}79${Font_color_suffix} docker nginx 
${Red_font_prefix}80${Font_color_suffix} check commands new_nginx_conf.txt.sh
${Red_font_prefix}81${Font_color_suffix} neovim and  to install: :PlugInstall :UpdateRemotePlugins ~/.config/nvim/init.vim
${Red_font_prefix}81a${Font_color_suffix} add vundle.sh to  ~/.vim/bundle
${Red_font_prefix}82${Font_color_suffix} git clone vps
${Red_font_prefix}83${Font_color_suffix} md file to html
${Red_font_prefix}84${Font_color_suffix} ports  转发
${Red_font_prefix}85${Font_color_suffix} clean_footprint
${Red_font_prefix}86${Font_color_suffix} 融合怪命令
${Red_font_prefix}87${Font_color_suffix} prefer_ipv4
${Red_font_prefix}88${Font_color_suffix} get_fraud_score
${Red_font_prefix}89${Font_color_suffix} some notes
${Red_font_prefix}90${Font_color_suffix} ohmyposh.sh
${Red_font_prefix}91${Font_color_suffix} hysteria2.sh
${Red_font_prefix}92${Font_color_suffix} install_cloudreve.sh
${Red_font_prefix}93${Font_color_suffix} install_resolvconf.sh
${Red_font_prefix}94${Font_color_suffix} ${Red_font_prefix}freqtrade ${Font_color_suffix} install folder 
${Red_font_prefix}944${Font_color_suffix} docker_path.sh
${Red_font_prefix}95${Font_color_suffix} change Swap
${Red_font_prefix}96${Font_color_suffix} pdf_txt.sh
${Red_font_prefix}97${Font_color_suffix} tika.sh
${Red_font_prefix}981${Font_color_suffix}${Red_font_prefix} 一 docker token page 6868 6969  docker:Token 6868 web 6969 backend deploy_token_service_backend_webpage.sh ${Font_color_suffix}  
${Red_font_prefix}98${Font_color_suffix} ${Red_font_prefix} 二 docker tika ${Font_color_suffix}   : bridge, setup_docker_compose_google_todynalist_pdftotxt.sh
${Red_font_prefix}980${Font_color_suffix} ${Red_font_prefix}三 docker:9977 webpage of tika${Font_color_suffix}    for 9966(9998) deploy-extractor_docker.sh
${Red_font_prefix}988${Font_color_suffix} pdf_to_html_combined_tika.sh
${Red_font_prefix}sncli${Font_color_suffix} sncli install
${Red_font_prefix}lab${Font_color_suffix} ${Red_font_prefix}jupyter_lab lab_install.sh  ${Font_color_suffix}
${Red_font_prefix}100${Font_color_suffix} ${Red_font_prefix}jupyter: jupyter16666.sh${Font_color_suffix}
${Red_font_prefix}1007${Font_color_suffix} ${Red_font_prefix}jupyter notebook7 : notebook7_install.sh  ${Font_color_suffix}
${Red_font_prefix}101${Font_color_suffix} ${Red_font_prefix}docker: startup_port16_py_jupyter.sh   jupyter1666.sh jupyter166.sh  markdown.sh${Font_color_suffix}
${Red_font_prefix}d88${Font_color_suffix}  ${Red_font_prefix} docker: typecho_docker_setup.sh ${Font_color_suffix}  
${Red_font_prefix}1011${Font_color_suffix} ${Red_font_prefix}calibre_linux_setup_ebook_online_reader.sh${Font_color_suffix}
${Red_font_prefix}d189${Font_color_suffix} Docker 189 readwise  setup-readwise_highlights_viewer.sh
${Red_font_prefix}10111${Font_color_suffix} Docker start_book_docker_instance.sh 
${Red_font_prefix}10112${Font_color_suffix} Docker  public_everyone_start_book_docker_instance.sh
${Red_font_prefix}187${Font_color_suffix} docker 187  : calibre_highlights_converter_dockerup.sh
${Red_font_prefix}102${Font_color_suffix} 中文编码问题 txt
${Red_font_prefix}103${Font_color_suffix} bash  <(curl -sLk  yabs.sh  ) -i
${Red_font_prefix}104${Font_color_suffix} TA-Lib install
${Red_font_prefix}105${Font_color_suffix} git new branch.sh 
${Red_font_prefix}7777${Font_color_suffix} ${Red_font_prefix}docker 7777  :upload_folder.py ${Font_color_suffix}
${Red_font_prefix}7788${Font_color_suffix} ${Red_font_prefix}docker 7788 setup_7788_web_download_docker.sh  ${Font_color_suffix}
${Red_font_prefix}107${Font_color_suffix} curl -sL yabs.sh | bash -s -- -i
${Red_font_prefix}108${Font_color_suffix} ddp_master.sh pytorch ddp distribution  computing
${Red_font_prefix}109${Font_color_suffix} ray_install3.sh
${Red_font_prefix}0${Font_color_suffix} ip checker
${Red_font_prefix}2${Font_color_suffix} list docker_path
${Red_font_prefix}666${Font_color_suffix} temporary bash
${Red_font_prefix}a${Font_color_suffix}  177 docker  markdown_render_dockerfile/markdown_render_docker.sh
${Red_font_prefix}ax${Font_color_suffix} markdown.sh 177 render
${Red_font_prefix}b${Font_color_suffix} config_fzf.sh   install fzf
${Red_font_prefix}c${Font_color_suffix} tmux_d/tmux_install.sh
${Red_font_prefix}d${Font_color_suffix} share_data_to_accessor.sh /etc/exports /etc/fstab /mnt/vps_
${Red_font_prefix}e${Font_color_suffix} install_ftp_server.sh
${Red_font_prefix}i${Font_color_suffix} do_zip.sh zip to /data 
${Red_font_prefix}g${Font_color_suffix} distri.sh
${Red_font_prefix}h${Font_color_suffix} init_github_project.sh
${Red_font_prefix}q${Font_color_suffix} exit
sed -i 's/eth0/enp0s3/g'  /etc/sysctl.conf 
nohup command > /dev/null 2>&1 &
nc -l 9  | tar xfvz - ;tar cfzv  -   <*/filei_path> | nc -q 1   <IP> 9 
Receiver: nc -l -p 9 > bar.zip
Sender: nc -q 1 data.zhulei.eu.org 9 < bar.zip




`echo -e "                 \e[1;38;2;252;33;137m$(hostname)\e[0m            \e[1;38;2;252;33;137m$(pwd)\e[0m            \e[1;38;2;252;33;137m$(/usr/bin/ls |wc -l)\e[0m                   "
  `          $today_hit $all_hit
  \r\n\n\n              \e[1;38;2;252;33;137m$(echo "$flag_emoji")\e[0m 
\n\n
")"  choose
	case $choose in
		222) eval $tcpx  ;;
		62) eval $trojan ;;
		63) eval $xray;;
		64) eval $realm;;
#	5) eval $speed;;
		555) wget -qO- bench.sh | bash | tee benchspeed.log  ;;
		55) bash <(curl -fSsL   https://raw.githubusercontent.com/vpsxb/testrace/main/testrace.sh) ;;

		6.1)   wg-quick down wg0; wg-quick down wg1;wg-quick down wg2  ; fix_wg_ipv6_RTNETLINK;eval $wg61  ; bash  <(curl -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wgiptabels.sh )  ;
			bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh);
			/sbin/sysctl -p ;;
	        d6) bash <(curl -4LSs "https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wg_d/wireguard_docker_startup_65506.sh" )  ;;
		6) wg-quick down wg0; wg-quick down wg1;wg-quick down wg2; fix_wg_ipv6_RTNETLINK ;eval $wg ; bash  <(curl -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/wgiptabels.sh ) ; 
			bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh);
			/sbin/sysctl -p 
		       	;;

		7z) bash  <(curl -4Lk  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/openvpn-server_z_good_claude_D/start_up_openvpn-server_z.sh) ;;
		7.0) eval $openvpn;;
		7.1) eval $openvpn2;;
		50) eval $v2ray;;
		8.1) eval $modify_id_of_v2ray;;
		999) eval $kcptun;;
		99)  bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/one_file_transfer4.sh )     ;;
		10) eval $ss_go;;
		11o) eval $dd;;
		11) eval $dd_debian11;;
		12) eval $dd_1;;
#	13) eval $s5;;
 	13) bash  <(curl -4LkSs https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh )       ;;
		13.1) eval $realm2;;
		14)eval  "${nf}"  | tee netflix.log ;;
        	15) eval $nfFree;;
#       	155) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/warp3 ) ;;
        	155) wget --inet4-only -N --no-check-certificate -O /etc/wireguard/warp3  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/warp3 && chmod +x /etc/wireguard/warp3   && sudo ln -s /etc/wireguard/warp3 /usr/bin/warp3   ;;
                16) eval $ss_rust;;
#        17) eval $speed2;;
                17)  bash <(curl -Lso- https://down.wangchao.info/sh/superspeed.sh) ;;
	        18) eval $wg_to_wgcf;;
		19) eval $xui;;
		20) eval $open_ipv6;;
		21) eval $nf_free2;;
		221) eval $nf_free3;;
		23) eval $wg_after_warp;eval $ipv4_v6_forwarding;;
		24) eval $ipv4_v6_forwarding;;
		25)(sed -i 's/\w\{8\}\-\w\{4\}\-\w\{4\}\-\w\{4\}\-\w\{12\}/12345678-1234-1234-1234-123456789012/g'  /usr/local/etc/xray/config.json;echo 14 |eval $xray) ;;
		
		26)eval "$debian_tools";;
		27)eval  'rm -fr  ~/.ssh ;mkdir  ~/.ssh ; echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lMkBC39ZW0RFnZZQCrfW2g2mGa2a8TvVd9d+UAfC13oybzrQ4oTEGnJbfhUneDHlo2/sPqN+WsI+xV9bKvUqfv8UfzBk12gB8JRH+gEaj98GqMdiF7YsHLOTDSyUZOEF0WdGORjAFPYOylEQWG/4rDJz7HHTNVoFp5qt8l542ldbSRTNWu8XWsSivEDDkYeb0FeAntn/biz3wXQmwz3myKNcEEBy3UfeysMGDvy/1noL9SQIuyB0Biwtuw4AstykUvoH0AP3nlSc4Cey/n3neCl8di+SBjzWUsICPmJkUQY7szzkFYUbChSO3A9lfmHpJsEGzDiLsF3v2Xdi3UfmfB1MumarW5byR18+KGL2QhCESqLffSONuCQ9UjJdVgdhyKfTTYkjIg8gJ9+1zJbJQq0MBQZw3WQCvyeiaxK/lOAL8CgHGuWDMfshwBgAxiU5mnGICdc253Bdr0pYG3R8CYJZvRmdSfygSZXv3EYDXu1Cz3NBDfdeAU2x6SFygE8= " > ~/.ssh/authorized_keys; sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/g"  /etc/ssh/sshd_config;sed -i "s/#Port 22/Port 54322/g"  /etc/ssh/sshd_config ;sed -i "s/Port 22/Port 54322/g"  /etc/ssh/sshd_config ; sed -i "s/PermitRootLogin no/PermitRootLogin yes/g"  /etc/ssh/sshd_config ; systemctl restart sshd' ;;		
		28)eval $wg_for_oracle;;
		29)eval $dd_oracle;;
		30)eval $speed3;;
		31)eval $ss_latest;;
		32)eval $ssr;;
		33)eval $isp_ip ;;
		34)eval $Aria2;;
		35)eval "$update_Aria2";;
		36)eval "$oc_ipv4_v6_forwarding";;
		37.1)eval "$bierendegongju1";;
		37.2)eval "$bierendegongju2";;
		38)eval "$isp_checker2";;
		39)eval "$ping_ip";;		
		40)eval 'sysctl -p /etc/sysctl.conf';;	
		41)eval $install_docker;;
		41.1)eval $install_nginx;;
		41.2)eval "$probe_x" ;;
		42)eval $install_docker_ccaa;;
		43)eval "$bashrc";;
		44)eval "$jupyter_notebook_remote_access";;
		45)eval "$latest_arm_kernel";;
		46)eval "$disable_all_wg_servers";;
		47)eval "${iptables_rules}";;
		48)eval "$Linux_tools";;
		49)eval "$ss_rust";;
		7)eval netstat_filter_quick ;;
		77)eval netstat_filter ;;
		5)
bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/network_monitor_openai.sh  )    ;;
		500)eval ps_filter ;;
                r)read -p 'script to run': x && ${x};;
                566)eval "$rdp";;
                56)
bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/rdp_docker_33399.sh  )    ;;
                57)eval "$delete_user";;
                58)eval "$hysteria";
sed -i 's/8.8.8.8/8.8.4.4/g'  /etc/hihy/conf/hihyServer.json
;;
                581)
bash  <(curl -Ls https://raw.githubusercontent.com/HyNetwork/hysteria/master/install_server.sh)
;;
                582)eval "$hy_mine"  ;;
                59)eval "$superspeed_uxh | tee speeds.log";;		
                60)eval "$ping_local";;		
                61) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/mini_conda.sh )  ;;
                611)eval "$jobs_spiders" ;;
#	eval "$jupyter_notebook_remote_access" ;
#	bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jupyter26666.sh)  ;;
                1111)
	eval  'rm -fr  ~/.ssh ;mkdir  ~/.ssh ; echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lMkBC39ZW0RFnZZQCrfW2g2mGa2a8TvVd9d+UAfC13oybzrQ4oTEGnJbfhUneDHlo2/sPqN+WsI+xV9bKvUqfv8UfzBk12gB8JRH+gEaj98GqMdiF7YsHLOTDSyUZOEF0WdGORjAFPYOylEQWG/4rDJz7HHTNVoFp5qt8l542ldbSRTNWu8XWsSivEDDkYeb0FeAntn/biz3wXQmwz3myKNcEEBy3UfeysMGDvy/1noL9SQIuyB0Biwtuw4AstykUvoH0AP3nlSc4Cey/n3neCl8di+SBjzWUsICPmJkUQY7szzkFYUbChSO3A9lfmHpJsEGzDiLsF3v2Xdi3UfmfB1MumarW5byR18+KGL2QhCESqLffSONuCQ9UjJdVgdhyKfTTYkjIg8gJ9+1zJbJQq0MBQZw3WQCvyeiaxK/lOAL8CgHGuWDMfshwBgAxiU5mnGICdc253Bdr0pYG3R8CYJZvRmdSfygSZXv3EYDXu1Cz3NBDfdeAU2x6SFygE8= " > ~/.ssh/authorized_keys; sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/g"  /etc/ssh/sshd_config;sed -i "s/#Port 22/Port 54322/g"  /etc/ssh/sshd_config ;sed -i "s/Port 22/Port 54322/g"  /etc/ssh/sshd_config ; sed -i "s/PermitRootLogin no/PermitRootLogin yes/g"  /etc/ssh/sshd_config ; systemctl restart sshd' ;

echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdbCXW2H3AwV6g9N1FXJp1/8EfWQbSJUuIbdHPoBgMU" >> ~/.ssh/authorized_keys; 

read -p 'hostname =>' USER_NAME &&  hostnamectl set-hostname $USER_NAME 
cat >>/etc/hosts<<EOF
$(ip route get 1.2.3.4 | awk '{print $7}')   $('hostname')
EOF
#yes | bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/pre_tcpx.sh ) 
#bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tcpx.sh_v100.0.1.26_modified.sh ) 
tmux new-session -d -s pre_ins ' yes | bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tcpx.sh_v100.0.1.26_modified_111.sh ) '
		;;
	1112)
yes | bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/pre_tcpx.sh ) 
		;;
                1) bash  <(curl --ipv4 -Ls  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tcpx.sh_v100.0.1.26_modified.sh )  ;;
                1.1)

	eval  'rm -fr  ~/.ssh ;mkdir  ~/.ssh ; echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lMkBC39ZW0RFnZZQCrfW2g2mGa2a8TvVd9d+UAfC13oybzrQ4oTEGnJbfhUneDHlo2/sPqN+WsI+xV9bKvUqfv8UfzBk12gB8JRH+gEaj98GqMdiF7YsHLOTDSyUZOEF0WdGORjAFPYOylEQWG/4rDJz7HHTNVoFp5qt8l542ldbSRTNWu8XWsSivEDDkYeb0FeAntn/biz3wXQmwz3myKNcEEBy3UfeysMGDvy/1noL9SQIuyB0Biwtuw4AstykUvoH0AP3nlSc4Cey/n3neCl8di+SBjzWUsICPmJkUQY7szzkFYUbChSO3A9lfmHpJsEGzDiLsF3v2Xdi3UfmfB1MumarW5byR18+KGL2QhCESqLffSONuCQ9UjJdVgdhyKfTTYkjIg8gJ9+1zJbJQq0MBQZw3WQCvyeiaxK/lOAL8CgHGuWDMfshwBgAxiU5mnGICdc253Bdr0pYG3R8CYJZvRmdSfygSZXv3EYDXu1Cz3NBDfdeAU2x6SFygE8= " > ~/.ssh/authorized_keys; sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/g"  /etc/ssh/sshd_config;sed -i "s/#Port 22/Port 54322/g"  /etc/ssh/sshd_config ;sed -i "s/Port 22/Port 54322/g"  /etc/ssh/sshd_config ; sed -i "s/PermitRootLogin no/PermitRootLogin yes/g"  /etc/ssh/sshd_config ; systemctl restart sshd' ;

	echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdbCXW2H3AwV6g9N1FXJp1/8EfWQbSJUuIbdHPoBgMU" >> ~/.ssh/authorized_keys; 
        bash <(curl -Ls "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh" )

	       	;;
		

                mianliu2)eval "$trojan_go_mianliu" ;;
                3)eval "$xray_mianliu" ;;
		d80) bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/xray_vmess_80_ws_docker_startup.sh )  ;;

		d80ai) docker_vmess_80_openai_65504  ;;

		d81) bash  <(curl -4Lk  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/openvpn-server_z_good_claude_D/start_up_openvpn-server_z.sh )      ;;

		65504)  bash  <(curl -4Lk   'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ss-rust-launch-tcp-only.sh'  )  ;;
                411)eval "$pre_InstallNET_modified_chu" ;;
                444)eval "$pre_InstallNET_modified_chu_debian12" ;;
                4)  
		bash  <(curl -4Lk   'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/CHU_reinstall_debian_current.sh' ) ;;
		4441) bash <(wget --inet4-only --no-check-certificate -qO- 'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_debian_current_netboot.sh' )    ;; 
                65)eval "$ss_rust2" ;;
          #     66)eval "$ping_local_fast" ;;
#        66) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ping_ask.sh ) ;;
                66) bash  <(curl --ipv4 -Ls  http://jingyi.today:9090/ping_ask.sh )  ;;

                67)eval "$html" ;;
		68)read  -p "$(echo -e "
1   azure_create
others for input location
\r\n
")"  choose
        case $choose in
          1) eval "$azure_create" ;;
	  
          *) read  -p  "user input = ": others ;;
        esac
;;
		
		69)eval "$aws_arm_dd";;
                70)eval "$docker_socks5_serjs" ;;
                71)eval "$install_freenom" ;;
                72)read -p 'user name =>': USER_NAME &&  hostnamectl set-hostname $USER_NAME 
cat >>/etc/hosts<<EOF
$(ip route get 1.2.3.4 | awk '{print $7}')   $('hostname')
EOF
			;;

		8) echo -e "${Red_font_prefix}${Bold_prefix}Listening${Font_color_suffix}. Waiting for incoming data..." &&  nc -l 9  -q 1  | tar xfvz - ;;
 #		74)read -p 'ip or domain =>': IPIP && tar cfzv  - *  | nc -q 1 ${IPIP} 9 ;;
  		9) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/sendfiles.sh) ;;
		75)docker run -itd --name az --restart always -p 8888:8888  dqjdda/azure-manager &&  docker exec -it az flask admin  1 19860826 ;;
		75.1)
echo '
方法1：使用cloudshell by Powershell
多订阅：az ad sp create-for-rbac --role owner --scopes /subscriptions/订阅ID
单订阅：$sub_id=$(az account list --query [].id -o tsv) ; az ad sp create-for-rbac --role owner --scopes /subscriptions/$sub_id

方法2：cloudshell by Bash

sub_id=$(az account list --query [].id -o tsv) && az ad sp create-for-rbac --role contributor --scopes /subscriptions/$sub_id

账号：defaultuser
密码：Thisis.yourpassword1
https://github.com/elunez/azure-manager
https://zhile.one/archives/1404.html

'
;;

		76)
wget --inet4-only -O AWS-Panel-linux-amd64.zip https://github.com/Yuzuki616/AWS-Panel/releases/download/v0.3.6/AWS-Panel-linux-amd64.zip
unzip  AWS-Panel-linux-amd64.zip
chmod 777 AWS-Panel-linux-amd64
nohup ./AWS-Panel-linux-amd64 > /dev/null 2>&1 &
;;
                1777)eval "${tuic}";;
                78)eval "${new_nginx_conf}";;
                79)eval "${new_nginx_conf_docker}";;
		80)curl https://raw.githubusercontent.com/HelloWorldWinning/vps/main/new_nginx_conf.txt.sh ;;
		81) bash  <(curl -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/nvim.sh ) ;;
		81a) bash  <(curl -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/bundle.sh    ) ;;
		82)git clone https://github.com/HelloWorldWinning/vps.git ;;
		83) curl --ipv4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/md2html.py.sh  | bash;;
		84) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ports_transfer.sh  ) ;;
		85) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/clean_footprint.sh  ) ;;
		86) curl -4L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh |tee testvps.log ;;

		87) prefer_ipv4;;
                88) option_88_function ;;
		89) curl  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/some_notes.sh  ;;
		90) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh_23_7_2.sh   ) ;;
		900) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh.sh   ) ;;
		91) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/hysteria2.sh ) ;;
		92) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_cloudreve.sh ) ;;
		93) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_resolvconf.sh  ) ;;
		94) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ft.sh  ) ;;
		2) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/docker_path_quick.sh ) ;;
		22) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/docker_path.sh ) ;;
		0)
bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/sys_info.sh  ) 			
bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_check3.sh  ) ;;

		95) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/swap.sh  ) ;;
		96) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/pdf_txt.sh  ) ;;
		97) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tika.sh  ) ;;
		988) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/pdf_to_html_combined_tika.sh  ) ;;
		981) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/deploy_token_service_backend_webpage.sh  ) ;;
		98) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/setup_docker_compose_google_todynalist_pdftotxt.sh  ) ;;
		980) bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/url_to_text_docker_d/deploy-extractor_docker.sh  ) ;;
		sncli) bash <(curl -sL    https://raw.githubusercontent.com/HelloWorldWinning/vps/main/sncli.sh) ;;
		100) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jupyter16666.sh)  ;;
		lab) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/lab_install.sh     )  ;;
		1007) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/notebook7_install.sh )  ;;
		1011) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/calibre_linux_setup_ebook_online_reader.sh )  ;;
		10111) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/calibre_linux_setup_ebook_online_reader__docker_d2/start_book_docker_instance.sh  )  ;;
		d189) 
bash  <(curl -4Lk   'https://raw.githubusercontent.com/HelloWorldWinning/vps/main/book1321_readwise_highlight_D3/setup-readwise_highlights_viewer.sh'  )   ;;
		10112) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/calibre_linux_setup_ebook_online_reader__docker_d2/public_everyone_start_book_docker_instance.sh  )  ;;
		d88) yes| bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/typecho_docker_setup.sh  )  ;;
#	10122) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/setup_highlight_converter.sh )  ;;
#	10122) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/setup_highlight_converter__D_docker/run_docker.sh )  ;;
		187) bash <(curl -4sSL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/setup_highlight_converter__D_fastapi_docker2/calibre_highlights_converter_dockerup.sh )   ;;
#	       	bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/setup_highlight_converter_d/run_highlight_service_docker.sh )  ;;
#	       	dv2)  bash <(curl -4LSs https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_docker_compose_v2_claude.sh )      ;;
		101) 
#bash  <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jupyter1666.sh )  
#bash  <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/jupyter166.sh ) 
bash  <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/start_jupyter166_1666_instances.sh ) 
bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_render_dockerfile/markdown_render_docker.sh) 
bash <(curl -fSsL4  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/16_d/startup_port16_py_jupyter.sh   )  
echo "======================================="
        echo "sleep 3 seconds..."
        sleep 3
#netstat -tulnp |grep 166	       
netstat -tulnp | grep -E '166|177'

#netstat -tulnp |grep 166 | wc -l	       
			;;

		d16) bash <(curl -fSsL4  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/16_d/startup_port16_py_jupyter.sh   )   ;;
		102) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/cn_coding.sh )  ;;
		103) bash  <(curl -sLk  yabs.sh  ) -i ;;
		104) yes |  bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ta-lib.sh  )  ;;
		105) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/branch.sh  )  ;;
		1066) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/upload_folder.sh )  ;;
		7777)  bash  <(curl -4Lsk  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/upload_folder_d/run_docker_compose.sh)    ;;
		7788) bash  <(curl -4Lk  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/7788_web_download_docker_claude/setup_7788_web_download_docker.sh ) ;;
		107) curl -sL yabs.sh | bash -s -- -i ;;

		108) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ddp_master.sh )  ;;
		109) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ray_install3.sh )  ;;
		ax) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown.sh )  ;;
		a) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/markdown_render_dockerfile/markdown_render_docker.sh)  ;;

		b) bash <(curl -fSsL4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/fzf_d/config_fzf.sh  )  ;;
		ccc) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/tmux_d/tmux_install.sh )  ;;
		d) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/share_data_to_accessor.sh  )  ;;
		e) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/install_ftp_server.sh   )  ;;
		i) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/do_zip.sh  )  ;;
		g) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/distri.sh )  ;;
		h) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/init_github_project.sh  )  ;;
		d3010) bash <(curl -fSsL4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/start_docker_affine.sh )   ;;
		666) bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/temp_bash_d/2024-03-20_14-32-34.sh  )  ;;
		d443) bash  <(curl -4LSs  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/outline_d/outline_setup_openai.sh ) ;; 

#	00)eval "exit";;
		q)eval "exit";;
		
		*) echo "wrong input" ;;
	esac

read -p 'time to go': seconds ;
[[ -z "${seconds}" ]] && seconds=0
#sleep ${seconds}

done
exit
