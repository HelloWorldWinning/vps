##(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx && systemctl stop xray && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" && systemctl start nginx && systemctl start xray > /dev/null") | crontab -

#(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx && systemctl stop xray; \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" > /root/acme-cron.log 2>&1; systemctl start nginx && systemctl start xray") | crontab -
#(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx ; systemctl stop xray; \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" > /root/acme-cron.log 2>&1; systemctl start nginx ; systemctl start xray") | crontab -
(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx ; systemctl stop xray; \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" --force  > /root/acme-cron.log 2>&1; systemctl start nginx ; systemctl start xray") | crontab -


read -p 'host name =>': USER_NAME &&  hostnamectl set-hostname $USER_NAME 
cat >>/etc/hosts<<EOF
$(ip route get 1.2.3.4 | awk '{print $7}')   $('hostname')
EOF


#(crontab -l 2>/dev/null; echo "44 4 * * * systemctl stop nginx && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" && systemctl start nginx > /dev/null") | crontab -


apt update
apt-get update

echo "nameserver 8.8.8.8" |  tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" |  tee -a /etc/resolv.conf

apt-get install -y xsel  xclip git poppler-utils calcurse  imagemagick  apache2-utils 
git config http.postBuffer 524288000
apt-get install -y  apache2-utils lsof  wget curl  nmap neofetch

git config --global core.editor "vim"


apt install docker-compose -y
apt install -y net-tools unzip mc lynx telnet zip lsof  vim
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


bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/swap7G.sh )


cat >>~/.bashrc<<EOF
###### _pre start




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


html_content=\$(curl -m 10 -s 'http://www.weather.com.cn/weather/101040100.shtml')
weather=\$(echo "\$html_content" |   grep -oP '(?<=class="wea">).*?(?=</p>)' |head -n2 | tr '\n' ';' | sed 's/;\$//'  )
temperature=\$(echo "\$html_content" | grep -oP '(?<=<i>).*?(?=℃</i>)' |head -n 1 ) 
we_temp="\${temperature}°C \${weather}"
weather_temperature="\${temperature}°C \${weather}"

alias we='curl -m 6  wttr.in/shapingba'
alias ca='calcurse'
alias nf='neofetch'

# find . -mindepth 1 -maxdepth 1 -exec du -sh {} + | sort -h
#alias zz='du  -sh * |sort -h'
#alias zz='du -sh ./* ./.??* | sort -h'
alias zz='find . -mindepth 1 -maxdepth 1 -exec du -sh {} + | sort -h'
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

alias _G='git add . && git commit -m  "\$(date)" && git push ;echo " ";date;echo " "'
alias _F='git pull && git add . && git commit -m "\$(date)"  && git push ;echo " ";date;echo " "'



alias n='/usr/bin/nvim.appimage'
#alias _ai='docker ps --format "{{.Names}}" |grep  "code_love_bot\|Codex_openai_bot\|openAI_Smart_Wisdom\|text_davinci_003_high_bot\|text_davinci_003_low_bot" |xargs -I {} docker restart {}'
export OPENAI_API_KEY=${OPENAI_API_KEY}
alias tx='tmux'
alias txn='tx new-session -s '
alias txnm='tx new-session -s '
alias txnw='tmux new-window -t '

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

#if [ "\$TERM_PROGRAM" = "Apple_Terminal" ]; then
#if true; then

if [ -n "\$SSH_CONNECTION" ] && [ "\$TERM_PROGRAM" != "vscode" ]; then
    # Check if a tmux session named "do" exists
    tmux has-session -t do &>/dev/null
    if [ \$? -ne 0 ]; then
        # If the session does not exist, create it
        tmux new-session -s do -d
    fi
    # If we are not already inside a tmux session, attach to the "do" session
    if [ -z "\$TMUX" ]; then
        tmux attach -t do
    fi
fi

#if [ -n "\$SSH_CONNECTION" ] && [ "\$TERM_PROGRAM" = "vscode" ]; then
#    # Check if a tmux session named "vscode" exists
#    tmux has-session -t vscode &>/dev/null
#    if [ \$? -ne 0 ]; then
#        # If the session does not exist, create it
#        tmux new-session -s vscode -d
#    fi
#    # If we are not already inside a tmux session, attach to the "vscode" session
#    if [ -z "\$TMUX" ]; then
#        tmux attach -t vscode
#    fi
#fi
#

if [ -n "\$SSH_CONNECTION" ] && [ "\$TERM_PROGRAM" = "vscode" ]; then
    # Check if a tmux session named "vscode" exists
    tmux has-session -t vscode &>/dev/null
    if [ \$? -ne 0 ]; then # Fixed the condition to properly check the exit status
        # If the session does not exist, create it
        tmux new-session -s vscode -d
    fi
    # If we are not already inside a tmux session, attach to the "vscode" session
    if [ -z "\$TMUX" ]; then # Correctly check the $TMUX variable to ensure not already in a session
        tmux attach -t vscode
    fi
fi



###############
get_git_branch_name() {
    # Check if Git command exists
    if ! command -v git &> /dev/null; then
        echo "Error: Git is not installed."
        return 1
    fi

    # Use Git to determine if we're in a Git repository
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
       #echo "Error: Not a git repository."
        echo ""
        return 0
    fi

    # Use git symbolic-ref or git describe to retrieve the current branch name
    local branch_name=\$(git symbolic-ref -q HEAD || git describe --tags --exact-match 2>/dev/null)
    # Remove the 'refs/heads/' from the full ref name
    branch_name=\${branch_name##refs/heads/}

    # Check if we got a branch name
    if [ -n "\$branch_name" ]; then
        echo "\$branch_name"
    else
        echo "Error: Currently not on any branch."
        return 1
    fi
}
###### _pre end
EOF

#source ~/.bashrc
bash  <(curl --ipv4 -Ls https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ohmyposh.sh  )
curl -4s https://ohmyposh.dev/install.sh | bash -s  


mkdir -p /root/.config/neofetch

wget -4 -O /root/.config/neofetch/config.conf https://raw.githubusercontent.com/HelloWorldWinning/vps/main/neofetch_config.conf
