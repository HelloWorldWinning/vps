(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" && systemctl start nginx > /dev/null") | crontab -


apt update
apt-get update

echo "nameserver 8.8.8.8" |  tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" |  tee -a /etc/resolv.conf

apt-get install -y xsel  xclip git poppler-utils calcurse  imagemagick  apache2-utils 
apt-get install apache2-utils -y

git config --global core.editor "vim"

apt install -y net-tools unzip mc lynx telnet
apt install -y sudo netcat-openbsd  tree screen htop  tmux rsync
sudo timedatectl set-timezone Asia/Shanghai
echo '--ipv4' >> ~/.curlrc
echo 'inet4_only = on'  >> ~/.wgetrc
#alias tls="tmux list-sessions"

bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)
###########

mkdir -p /data

cat >>~/.bashrc<<EOF

# start pre tcp

export EDITOR=/usr/bin/vim
export setup_time="`date`"

function check_setup_time() {
    setup_time_seconds=\$(date -d "\$setup_time" +%s)
    current_time_seconds=\$(date +%s)
    time_difference=\$((current_time_seconds - setup_time_seconds))
    days=\$((time_difference / 86400))
    hours=\$(( (time_difference % 86400) / 3600 ))
    minutes=\$(( (time_difference % 3600) / 60 ))
    seconds=\$((time_difference % 60))
    echo "\$days days, \$hours hours, \$minutes minutes, \$seconds seconds"
}


## Fetch the HTML content
html_content=\$(curl -m 10 -s 'http://www.weather.com.cn/weather/101040100.shtml')
### Extract the weather condition and temperature
###weather=\$(echo "\$html_content" | grep -oP '(?<=<p title="多云" class="wea">).*?(?=</p>)' |head -n 1)
weather=\$(echo "\$html_content" |   grep -oP '(?<=class="wea">).*?(?=</p>)' |head -n2 | tr '\n' ';' | sed 's/;\$//'  )
temperature=\$(echo "\$html_content" | grep -oP '(?<=<i>).*?(?=℃</i>)' |head -n 1 ) 
##
### Output the results
###echo "Weather condition: \$weather"
###echo "Temperature: \$temperature°C" 
we_temp="\${temperature}°C \${weather}"
export weather_temperature=$we_temp

alias we='curl -m 6  wttr.in/shapingba'
alias ca='calcurse'

alias ft='freqtrade'
alias v='vim'
alias c='clear'
alias cc='clear'
alias l='ls -lrth'
alias s='ls -lhSr'
alias nm='ls -lh'
alias ln='ls -lh'
alias p='python'
alias _GP='git  pull'
#alias _G='git add . && git commit -m   "`date`"  && git push ;echo " ";date;echo " "'
#alias _F='git pull && git add . && git commit -m  "`date`" && git push ;echo " ";date;echo " "'
#alias _G='git add . && git commit -m   "Thu Nov 16 04:01:40 PM CST 2023"  && git push ;echo " ";date;echo " "'
#alias _F='git pull && git add . && git commit -m  "Thu Nov 16 04:01:40 PM CST 2023" && git push ;echo " ";date;echo " "'

alias _G='git add . && git commit -m  "\$(date)" && git push ;echo " ";date;echo " "'
alias _F='git pull && git add . && git commit -m "\$(date)"  && git push ;echo " ";date;echo " "'



alias n='/usr/bin/nvim.appimage'
#alias _ai='docker ps --format "{{.Names}}" |grep  "code_love_bot\|Codex_openai_bot\|openAI_Smart_Wisdom\|text_davinci_003_high_bot\|text_davinci_003_low_bot" |xargs -I {} docker restart {}'
export OPENAI_API_KEY=${OPENAI_API_KEY}
alias tx='tmux'
alias txn='tx new-session -s '
alias txnm='tx new-session -s '
alias txa='tx attach-session -t '
alias txl='tmux list-sessions'
alias txlw='tmux list-windows '

alias dc='docker-compose'
#alias cc='bash  <(curl -Ls4  bit.ly/myvpsjingyi)'
alias f='bash  <(curl -Ls4   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/goodv3.sh   )'

bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/sys_info.sh  )
#bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_check2.sh  ) 

#bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_check2_simple.sh  ) </dev/null
#bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_check2.sh  ) </dev/null





cd /data

echo ""
l

# end of pre tcp
EOF

source /root/.bashrc
source ~/.bashrc




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



# ohmyposh.sh

mkdir -p /root/themes/

#wget   --inet4-only  -O  /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json

#bash <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh.sh )

wget   --inet4-only  -O  /root/themes/gmay3.omp.json https://raw.githubusercontent.com/HelloWorldWinning/vps/main/gmay3.omp.json



