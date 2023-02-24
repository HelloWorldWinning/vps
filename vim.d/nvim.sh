# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/ Linux 下 Neovim 配置 Python 开发环境指南
# https://juejin.cn/post/6844904118948118536 如何将你的 neovim 打造成 vscode 一般的 Python IDE?
# https://github.com/ellisonleao/gruvbox.nvim  ellisonleao / gruvbox.nvim
# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/
#
set debian timezone shanghai

curl  --ipv4 -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

pip install neovim
pip install pynvim


curl  --ipv4 -Lo  /usr/bin/nvim.appimage https://github.com/neovim/neovim/releases/latest/download/nvim.appimage

chmod u+x /usr/bin/nvim.appimage
#./nvim.appimage
ln -s /usr/bin/nvim.appimage /usr/bin/nvim


curl  --ipv4 -fLo  /root/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

curl  --ipv4 -fsSL https://deb.nodesource.com/setup_19.x | bash - &&\

apt-get update
apt-get install -y nodejs git

apt update
apt install -y node 

#apt-get update && apt-get install -y git

# neovim

apt install python3-pip -y

#pip install --upgrade pip
pip3 install neovim  pynvim jedi
pip install neovim  pynvim jedi


mkdir  -p /root/.config/nvim
mkdir -p ~/.vim
#git clone https://github.com/tyrannicaltoucan/vim-quantum.git  ~/.vim

cd  ~/.vim &&  git clone https://github.com/tyrannicaltoucan/vim-quantum.git
cd ~


#wget --inet4-only -O  /root/.config/nvim/init.vim  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/init.vim.ulovem
wget --inet4-only -O  ~/.vimrc  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/vimrc.use
wget --inet4-only -O  ~/.config/nvim/init.vim  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/nvim.use

# cat>/root/.config/nvim/init.vim<<EOF
# EOF



#wget -O ripgrep.deb https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb
#dpkg -i ripgrep.deb


#alias _g='git add . && git commit -m   " Sun 15 Jan 2023 05:27:01 PM CST " && git push'

cat >>~/.bashrc<<EOF
alias v='vim'
alias c='clear'
alias l='ls -lrth'
alias s='ls -lhSr'
alias nm='ls -lh'
alias p='python'
alias _GP='git  pull'
alias _G='git add . && git commit -m   " Sun 15 Jan 2023 05:27:01 PM CST " && git push ;echo " ";date;echo " "'
alias n='/usr/bin/nvim.appimage'
alias _ai='docker ps --format "{{.Names}}" |grep  "code_love_bot\|Codex_openai_bot\|openAI_Smart_Wisdom\|text_davinci_003_high_bot\|text_davinci_003_low_bot" |xargs -I {} docker restart {}'
EOF

source /root/.bashrc

cat  <<- EOF
#######  neovim  install :
:CocInstall coc-python
:CocInstall coc-snippets
:CocInstall coc-bookmark
:PlugInstall
:UpdateRemotePlugins

https://github.com/Shougo/deoplete.nvim#install
Write call deoplete#enable() or let g:deoplete#enable_at_startup = 1 in your init.vim
~/.config/nvim/init.vim

##########
vim  install  :
PlugInstall

EOF



