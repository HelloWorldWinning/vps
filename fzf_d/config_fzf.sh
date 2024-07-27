apt-get -y  git
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
#~/.fzf/install
sudo yes | ~/.fzf/install

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

cat >> ~/.bashrc <<'EOF'
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
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fdfind --hidden --follow -E ".git" -E "node_modules" . 
}
# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fdfind --type d --hidden --follow -E ".git" -E "node_modules" . 
}


####### Press Alt+F to search through command history using fzf
__fzf_history() {
  local selected_command
  selected_command=$(history | fzf | awk '{$1=""; print $0}')
  if [ -n "$selected_command" ]; then
    echo "$selected_command"
    eval "$selected_command"
  fi
}
bind -x '"\ev": __fzf_history'
bind '"\ef": "\C-uvim \C-t\C-m"'
#####bind '"\er": "\C-unvim \C-t\C-m"'
bind '"\er": "\C-un \C-t\C-m"'

#fzf_bat() {
#  local file
#  file=$(fzf)
#  if [ -n "$file" ]; then
#    bat "$file"
#  fi
#}
#
#bind '"\es": "\C-u fzf_bat\C-m"'


fzf_bat() {
  local file
  file=$(fzf)
  if [ -n "$file" ]; then
    bat "$file"
  fi
}

bind '"\es": "\C-ufzf_bat\C-m"'



fzf_cat() {
  local file
  file=$(fzf)
  if [ -n "$file" ]; then
    cat "$file"
  fi
}
bind '"\ea": "\C-u fzf_cat\C-m"'



__fzf_cd__() {
  local dir
  dir=$(find ${1:-.} -type d 2> /dev/null | fzf +m) && cd "$dir"
}
bind '"\ec": "__fzf_cd__\C-m"'

## New Ctrl+arrow key bindings as per user request
bind '"\e[1;5A": "\ev"'   # Ctrl+Up for history
bind '"\e[1;5B": "\ec"'   # Ctrl+Down for change directory
bind '"\e[1;5C": "\ef"'   # Ctrl+Right for vim
bind '"\e[1;5D": "\er"'   # Ctrl+Left for run command

# New Meta+arrow key bindings as per user requestbind '"\e[1;3A": "\ev"'   # Meta+Up for history
bind '"\e[1;3B": "\ec"'   # Meta+Down for change directory
bind '"\e[1;3C": "\ef"'   # Meta+Right for vim
bind '"\e[1;3D": "\er"'   # Meta+Left for run command

# New bindings for Meta (Alt) + hjkl
bind '"\eh": "\e[1;5D"'   # Meta+h for Ctrl+Left (run command)
bind '"\ej": "\e[1;5B"'   # Meta+j for Ctrl+Down (change directory)
bind '"\ek": "\e[1;5A"'   # Meta+k for Ctrl+Up (history)
bind '"\el": "\e[1;5C"'   # Meta+l for Ctrl+Right (vim)

#### https://yaozhijin.gitee.io/Linux模糊搜索神器fzf终极配置.html
####   https://www.jianshu.com/p/aeebaee1dd2b

  #####   #####   ##### 
  #####   #####   ##### 
  #####   #####   ##### 
EOF


####echo 'bind "\"\C-v\": \"\C-uvim \C-t\C-m\""' >> ~/.bashrc

#########echo 'bind '"\ev": "\C-uvim \C-t\C-m"'' >> ~/.bashrc 
#
#
#cat >> ~/.bashrc << 'EOF'
#EOF





git clone https://github.com/wting/autojump.git
cd autojump
./install.py
#cd ..
#rm -r autojump

echo "[[ -s /root/.autojump/etc/profile.d/autojump.sh ]] && source /root/.autojump/etc/profile.d/autojump.sh" >> ~/.bashrc
echo "export FZF_COMPLETION_TRIGGER='~~'" >> ~/.fzf.bash


curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
echo 'export PATH="$PATH:/root/.local/bin"' >> ~/.bashrc
echo 'eval "$(zoxide init bash)"' >> ~/.bashrc
##cat << 'EOF' >> ~/.bashrc
##export PATH="$PATH:/root/.local/bin"
##eval "$(zoxide init bash)"
##EOF

eval "$(oh-my-posh init bash --config /root/themes/gmay3.omp.json)"

