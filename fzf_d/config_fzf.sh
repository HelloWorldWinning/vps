apt-get -y  git
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
#~/.fzf/install
yes | ~/.fzf/install

apg-get update
apt-get -y install sudo fd-find ripgrep ranger  

sudo apt install bat -y
sudo ln -s /usr/bin/batcat /usr/bin/bat

#sudo chmod 777  /usr/share/lintian/overrides/bat

sudo mkdir  -p  /data/.fzf_d

wget -4 -O /data/.fzf_d/file_preview.py   https://raw.githubusercontent.com/HelloWorldWinning/vps/main/fzf_d/file_preview.py
sudo chmod 777 /data/.fzf_d/file_preview.py 


ranger --copy-config=all
mv ~/.config/ranger/commands.py  ~/.config/ranger/commands.py.bak
mv ~/.config/ranger/rc.conf  ~/.config/ranger/rc.conf.bak

wget -4 -O  ~/.config/ranger/commands.py  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/fzf_d/commands.py
wget -4 -O  ~/.config/ranger/rc.conf  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/fzf_d/rc.conf

cat >> ~/.bashrc <<EOF

##### fzf  ##### 


export FZF_DEFAULT_COMMAND='fdfind --hidden --follow -E ".git" -E "node_modules" . '
export FZF_DEFAULT_OPTS='--height 90% --layout=reverse --bind=alt-j:down,alt-k:up,alt-i:toggle+down --border --preview "echo {} | /data/.fzf_d/file_preview.py"  --preview-window=down'

# use fzf in bash and zsh
# Use ~~ as the trigger sequence instead of the default **
#export FZF_COMPLETION_TRIGGER='~~'

# Options to fzf command
#export FZF_COMPLETION_OPTS=''

# Use fd (https://github.com/sharkdp/fd) instead of the default find
# command for listing path candidates.
# - The first argument to the function (\$1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fdfind --hidden --follow -E ".git" -E "node_modules" . 
}
# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fdfind --type d --hidden --follow -E ".git" -E "node_modules" . 
}
### https://yaozhijin.gitee.io/Linux模糊搜索神器fzf终极配置.html
  #####   #####   ##### 
EOF


echo 'bind "\"\C-v\": \"\C-uvim \C-t\C-m\""' >> ~/.bashrc



git clone https://github.com/wting/autojump.git
cd autojump
./install.py
cd ..
rm -r autojump

echo "[[ -s /root/.autojump/etc/profile.d/autojump.sh ]] && source /root/.autojump/etc/profile.d/autojump.sh" >> ~/.bashrc

echo "export FZF_COMPLETION_TRIGGER='~~'" >> ~/.fzf.bash
