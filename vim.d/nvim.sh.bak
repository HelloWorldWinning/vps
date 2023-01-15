# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/ Linux 下 Neovim 配置 Python 开发环境指南
# https://juejin.cn/post/6844904118948118536 如何将你的 neovim 打造成 vscode 一般的 Python IDE?
# https://github.com/ellisonleao/gruvbox.nvim  ellisonleao / gruvbox.nvim
# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/
#

curl -Lo  /usr/bin/nvim.appimage https://github.com/neovim/neovim/releases/latest/download/nvim.appimage

chmod u+x /usr/bin/nvim.appimage
#./nvim.appimage
ln -s /usr/bin/nvim.appimage /usr/bin/nvim


curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
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


mkdir  -p ~/.config/nvim

cat>~/.config/nvim/init.vim<<EOF
let g:deoplete#enable_at_startup = 1
let g:coc_disable_startup_warning = 1
"let g:airline_theme='badwolf'  "可以自定义主题，这里使用 badwolf

call plug#begin('~/.local/share/nvim/plugged')

Plug 'morhetz/gruvbox'

Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'zchee/deoplete-jedi'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
"Plug 'vim-airline/vim-airline'
Plug 'jiangmiao/auto-pairs'
Plug 'christoomey/vim-tmux-navigator'

Plug 'preservim/nerdtree'
Plug 'preservim/nerdcommenter' 

"Plug 'vim-airline/vim-airline'
Plug 'kkoomen/vim-doge'
Plug 'preservim/nerdcommenter' 

call plug#end()


set background=dark " or light if you want light mode
colorscheme gruvbox



syntax on
filetype plugin on
"set showtabline=2
set tabline=%F\ %y 
set number 
set relativenumber
set ruler
"set rulerformat=%l/[%L]:%v
"let g:rulerformat_filepath_format = '%f'



EOF



#wget -O ripgrep.deb https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb
#dpkg -i ripgrep.deb


cat >>~/.bashrc<<EOF
#alias n='nvim'
alias l='ls -lrth'
alias n='/usr/bin/nvim.appimage'
alias _g='git add . && git commit -m   " `date` " && git push'
EOF

source ~/.bashrc


cat  <<- EOF

:CocInstall coc-python
:CocInstall coc-snippets
:CocInstall coc-bookmark
:PlugInstall
~/.config/nvim/init.vim
EOF



