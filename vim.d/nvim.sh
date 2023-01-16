# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/ Linux 下 Neovim 配置 Python 开发环境指南
# https://juejin.cn/post/6844904118948118536 如何将你的 neovim 打造成 vscode 一般的 Python IDE?
# https://github.com/ellisonleao/gruvbox.nvim  ellisonleao / gruvbox.nvim
# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/
#

curl -Lo  /usr/bin/nvim.appimage https://github.com/neovim/neovim/releases/latest/download/nvim.appimage

chmod u+x /usr/bin/nvim.appimage
#./nvim.appimage
ln -s /usr/bin/nvim.appimage /usr/bin/nvim


curl -fLo  /root/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

curl -fsSL https://deb.nodesource.com/setup_19.x | bash - &&\
apt-get update
apt-get install -y nodejs
apt install -y node 

apt-get update && apt-get install -y

# neovim

apt install python3-pip -y

#pip install --upgrade pip
pip3 install neovim  pynvim jedi
pip install neovim  pynvim jedi


mkdir  -p /root/.config/nvim

#wget -O  /root/.config/nvim/init.vim  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/init.vim.ulovem
wget --inet4-only -O  /root/.config/nvim/init.vim  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/init.vim.ulovem

# cat>/root/.config/nvim/init.vim<<EOF
# EOF



#wget -O ripgrep.deb https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb
#dpkg -i ripgrep.deb


cat >>~/.bashrc<<EOF
#alias n='nvim'
alias l='ls -lrth'
alias c='clear'
alias s='ls -lhSr'
alias n='/usr/bin/nvim.appimage'
alias _g='git add . && git commit -m   " `date` " && git push'
EOF

source /root/.bashrc


cat  <<- EOF

:CocInstall coc-python
:CocInstall coc-snippets
:CocInstall coc-bookmark
:PlugInstall
:UpdateRemotePlugins


https://github.com/Shougo/deoplete.nvim#install
Write call deoplete#enable() or let g:deoplete#enable_at_startup = 1 in your init.vim
~/.config/nvim/init.vim
EOF



