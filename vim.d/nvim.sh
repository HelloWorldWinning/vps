# 1) Make sure venv is available
sudo apt update
sudo apt install -y python3-venv # (on some systems: python3.11-venv or python3.12-venv)

# 2) Make a venv (any path/name is fine)
python3 -m venv ~/.venvs/vim_nvim_pip_related

# 3) Activate it (your prompt should show "(vim_nvim_pip_related)")
source ~/.venvs/vim_nvim_pip_related/bin/activate

# 4) Upgrade pip and install your packages
python -m pip install --upgrade pip

apt install -y sudo
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg git vim
# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/ Linux 下 Neovim 配置 Python 开发环境指南
# https://juejin.cn/post/6844904118948118536 如何将你的 neovim 打造成 vscode 一般的 Python IDE?
# https://github.com/ellisonleao/gruvbox.nvim  ellisonleao / gruvbox.nvim
# https://jdhao.github.io/2018/09/05/centos_nvim_install_use_guide/
#
set debian timezone shanghai

curl --ipv4 -fLo ~/.vim/autoload/plug.vim --create-dirs \
	https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

pip install neovim
pip install pynvim

pip3 install neovim
pip3 install pynvim

#curl  --ipv4 -Lo  /usr/bin/nvim.appimage https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
#chmod u+x /usr/bin/nvim.appimage
#./nvim.appimage
#
#

# Check that jq is installed
if ! command -v jq >/dev/null; then
	echo "Error: 'jq' is required but not installed. Please install jq and try again."
	sudo apt-get install -y jq
	apt-get install -y jq
	sudo apt install -y jq
	apt install -y jq
fi

echo "Fetching stable Neovim release info..."
# This endpoint returns the latest stable release (not a pre-release)
RELEASE_JSON=$(curl -sL "https://api.github.com/repos/neovim/neovim/releases/latest")

# Get the stable release tag
STABLE_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
echo "Stable release: $STABLE_TAG"

# Define the asset name (change this if you need a different build, e.g. arm64)
ASSET_NAME="nvim-linux-x86_64.appimage"

# Extract the download URL for the desired asset
APPIMAGE_URL=$(echo "$RELEASE_JSON" | jq -r --arg asset "$ASSET_NAME" '.assets[] | select(.name == $asset) | .browser_download_url')

if [ -z "$APPIMAGE_URL" ]; then
	echo "Error: Asset '$ASSET_NAME' not found in the stable release."
	exit 1
fi

echo "Downloading $ASSET_NAME from: $APPIMAGE_URL"
curl --ipv4 -Lo /usr/bin/nvim.appimage "$APPIMAGE_URL"

echo "Setting executable permissions..."
chmod u+x /usr/bin/nvim.appimage

echo "Neovim AppImage has been downloaded and installed at /usr/bin/nvim.appimage"

#

NVIM_PATH="/usr/bin/nvim.appimage"
SYMLINK_PATH="/usr/bin/nvim"
sudo ln -sf $NVIM_PATH $SYMLINK_PATH
#####sudo ln -s /usr/bin/nvim.appimage /usr/bin/nvim

curl --ipv4 -fLo /root/.local/share/nvim/site/autoload/plug.vim --create-dirs \
	https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

#curl  --ipv4 -fsSL https://deb.nodesource.com/setup_19.x | bash - &&\
#apt-get update
#apt-get install -y nodejs git
#
#apt update
#apt install -y node

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt-get update
sudo apt-get install nodejs -y

#apt-get update && apt-get install -y git

# neovim

apt install python3-pip -y

#pip install --upgrade pip
pip3 install neovim pynvim jedi

sudo apt install python3-jedi

pip install neovim pynvim jedi

mkdir -p /root/.config/nvim
mkdir -p ~/.vim
#git clone https://github.com/tyrannicaltoucan/vim-quantum.git  ~/.vim

cd ~/.vim && git clone https://github.com/tyrannicaltoucan/vim-quantum.git
cd ~

#wget --inet4-only -O  /root/.config/nvim/init.vim  https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/init.vim.ulovem
wget --inet4-only -O ~/.vimrc https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/vimrc.use
wget --inet4-only -O ~/.config/nvim/init.vim https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/nvim.use

# cat>/root/.config/nvim/init.vim<<EOF
# EOF

#wget -O ripgrep.deb https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb
#dpkg -i ripgrep.deb

#
#alias _g='git add . && git commit -m   " Sun 15 Jan 2023 05:27:01 PM CST " && git push'

#read  -p "default OPENAI_API_KEY  belongs to keubahkmc@outlook.com " OPENAI_API_KEY
#[[ -z "${OPENAI_API_KEY}" ]] &&  OPENAI_API_KEY=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
OPENAI_API_KEY=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

#cat >>~/.bashrc<<EOF
#alias v='vim'
#alias c='clear'
#alias l='ls -lrth'
#alias s='ls -lhSr'
#alias nm='ls -lh'
#alias p='python'
#alias _GP='git  pull'
#alias _G='git add . && git commit -m   " Sun 15 Jan 2023 05:27:01 PM CST " && git push ;echo " ";date;echo " "'
#alias _F='git pull && git add . && git commit -m   " Sun 15 Jan 2023 05:27:01 PM CST " && git push ;echo " ";date;echo " "'
#alias n='/usr/bin/nvim.appimage'
#alias _ai='docker ps --format "{{.Names}}" |grep  "code_love_bot\|Codex_openai_bot\|openAI_Smart_Wisdom\|text_davinci_003_high_bot\|text_davinci_003_low_bot" |xargs -I {} docker restart {}'
#export OPENAI_API_KEY=${OPENAI_API_KEY}
#EOF
#
#source /root/.bashrc
#source ~/.bashrc

git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
#cd ~/.vim/bundle

####### rm link vim to nvim
#!/bin/bash

# Remove existing vim symlink
sudo rm -f /usr/bin/vim

# Find the path to the original vim executable
vim_path=$(readlink -f $(which vim.basic || which vim.tiny))

if [ -z "$vim_path" ]; then
	echo "Error: Could not find vim executable"
	exit 1
fi

# Create new symlink to the original vim
sudo ln -sf "$vim_path" /usr/bin/vim

# Verify the change
echo "Verifying the change:"
ls -l /usr/bin/vim
vim --version | head -n 1

echo "Vim symlink has been updated. Please check the output above to ensure it's correct."
#########

cat <<-EOF
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

/root/miniconda3/bin/python -m pip install pynvim
/root/miniconda3/bin/python -m pip install neovim
python -m pip install pynvim
python -m pip install neovim

pip install pynvim
pip install jedi

pip3 install pynvim
pip3 install jedi

bash <(curl -L4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/handle_nvim_pluges.sh)

sudo apt update
sudo apt install -y nodejs npm
sudo npm install -g pyright

rustup update
rustup toolchain install stable
rustup component add rust-analyzer
