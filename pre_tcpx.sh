apt install -y sudo netcat-openbsd  tree
sudo timedatectl set-timezone Asia/Shanghai
echo '--ipv4' >> ~/.curlrc
echo 'inet4_only = on'  >> ~/.wgetrc

bash <(curl -sL https://raw.githubusercontent.com/HelloWorldWinning/vps/main/ip_forwarding.sh)

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
EOF

source /root/.bashrc
source ~/.bashrc


