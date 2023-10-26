apt update
apt-get update

echo "nameserver 8.8.8.8" |  tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" |  tee -a /etc/resolv.conf

apt-get install -y xsel  xclip

apt install -y net-tools unzip
apt install -y sudo netcat-openbsd  tree screen htop  tmux
sudo timedatectl set-timezone Asia/Shanghai
echo '--ipv4' >> ~/.curlrc
echo 'inet4_only = on'  >> ~/.wgetrc
#alias tls="tmux list-sessions"

bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)
###########
# ohmyposh.sh
bash <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh.sh )

cat >>~/.bashrc<<EOF
alias v='vim'
alias c='clear'
alias l='ls -lrth'
alias s='ls -lhSr'
alias nm='ls -lh'
alias ln='ls -lh'
alias p='python'
alias _GP='git  pull'
alias _G='git add . && git commit -m   "`date`"  && git push ;echo " ";date;echo " "'
alias _F='git pull && git add . && git commit -m  "`date`" && git push ;echo " ";date;echo " "'
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


export country_code=$(curl -s 'https://ipinfo.io/json' | grep '\"country\":' | awk -F'\"' '{print $4}')

bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_check2.sh  ) </dev/null
echo ""
l
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





