apt update
apt-get update

echo "nameserver 8.8.8.8" |  tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" |  tee -a /etc/resolv.conf

#apt-get install -y resolvconf
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
alias txa='tx attach-session -t '
alias txl='tmux list-sessions'
alias txlw='tmux list-windows '

alias dc='docker-compose'

EOF

source /root/.bashrc
source ~/.bashrc

