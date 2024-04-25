git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
cd ~/.vim/bundle
git clone https://github.com/freeo/vim-kalisi

cat <<'EOF'>>  ~/.vimrc 
""""""Vundle""""""vim-kalisi"""""" start

set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

"Plugin statements go here
Plugin 'freeo/vim-kalisi'

" All of your Plugins must be added before the following line
call vundle#end()

filetype plugin indent on    " required
colorscheme kalisi
set background=dark
""""""Vundle""""""vim-kalisi"""""" end
EOF


