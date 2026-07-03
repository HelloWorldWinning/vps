# 1) Make sure venv is available
sudo apt update
sudo apt install -y python3-venv # (on some systems: python3.11-venv or python3.12-venv)

clean_install() {
	echo
	echo "========== clean_install: post-install cleanup =========="

	# Use sudo only when needed
	local SUDO=""
	if [ "$(id -u)" -ne 0 ]; then
		SUDO="sudo"
	fi

	# Helper functions
	_exists() {
		command -v "$1" >/dev/null 2>&1
	}

	_warn() {
		echo "WARNING: $*" >&2
	}

	_info() {
		echo "-- $*"
	}

	# ------------------------------------------------------------
	# 1) Security warning: detect hardcoded API keys in this script
	# ------------------------------------------------------------
	if [ -f "$0" ] && grep -qE 'OPENAI_API_KEY=.*sk-' "$0" 2>/dev/null; then
		_warn "This script appears to contain a hardcoded OpenAI API key."
		_warn "Remove it from nvim_dc.sh and rotate the key immediately."
	fi

	# ------------------------------------------------------------
	# 2) Normalize Neovim AppImage install
	# ------------------------------------------------------------
	_info "Normalizing Neovim binary links..."

	if [ -x /usr/bin/nvim.appimage ]; then
		$SUDO chmod 755 /usr/bin/nvim.appimage
		$SUDO ln -sfn /usr/bin/nvim.appimage /usr/bin/nvim
	elif _exists nvim; then
		_info "nvim already exists at: $(command -v nvim)"
	else
		_warn "Neovim executable was not found."
	fi

	# ------------------------------------------------------------
	# 3) Restore Vim so /usr/bin/vim does not point to Neovim
	# ------------------------------------------------------------
	_info "Restoring vim symlink to the system Vim executable..."

	local vim_real=""
	if _exists vim.basic; then
		vim_real="$(command -v vim.basic)"
	elif _exists vim.tiny; then
		vim_real="$(command -v vim.tiny)"
	fi

	if [ -n "$vim_real" ]; then
		$SUDO ln -sfn "$vim_real" /usr/bin/vim
	else
		_warn "Could not find vim.basic or vim.tiny; leaving /usr/bin/vim unchanged."
	fi

	# ------------------------------------------------------------
	# 4) Ensure required config directories exist
	# ------------------------------------------------------------
	_info "Ensuring Vim/Neovim config directories exist..."

	for home_dir in "$HOME" /root; do
		[ -d "$home_dir" ] || continue

		mkdir -p "$home_dir/.vim/autoload"
		mkdir -p "$home_dir/.vim/bundle"
		mkdir -p "$home_dir/.config/nvim"
		mkdir -p "$home_dir/.local/share/nvim/site/autoload"

		# Remove Python cache files from editor config directories only
		find "$home_dir/.vim" \
			"$home_dir/.config/nvim" \
			"$home_dir/.local/share/nvim" \
			-type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
	done

	# ------------------------------------------------------------
	# 5) Clean duplicate/partial plugin repo states safely
	# ------------------------------------------------------------
	_info "Checking plugin repository state..."

	for home_dir in "$HOME" /root; do
		[ -d "$home_dir" ] || continue

		if [ -d "$home_dir/.vim/vim-quantum/.git" ]; then
			git -C "$home_dir/.vim/vim-quantum" remote -v >/dev/null 2>&1 ||
				_warn "$home_dir/.vim/vim-quantum exists but is not a healthy git repo."
		fi

		if [ -d "$home_dir/.vim/bundle/Vundle.vim/.git" ]; then
			git -C "$home_dir/.vim/bundle/Vundle.vim" remote -v >/dev/null 2>&1 ||
				_warn "$home_dir/.vim/bundle/Vundle.vim exists but is not a healthy git repo."
		fi
	done

	# ------------------------------------------------------------
	# 6) Fix permissions for NodeSource apt files
	# ------------------------------------------------------------
	_info "Fixing apt keyring/source permissions..."

	[ -f /etc/apt/keyrings/nodesource.gpg ] &&
		$SUDO chmod 644 /etc/apt/keyrings/nodesource.gpg

	[ -f /etc/apt/sources.list.d/nodesource.list ] &&
		$SUDO chmod 644 /etc/apt/sources.list.d/nodesource.list

	# ------------------------------------------------------------
	# 7) Clean pip/npm/apt caches
	# ------------------------------------------------------------
	_info "Cleaning package-manager caches..."

	if _exists python3; then
		python3 -m pip cache purge >/dev/null 2>&1 || true
	fi

	if _exists python; then
		python -m pip cache purge >/dev/null 2>&1 || true
	fi

	if _exists npm; then
		npm cache verify >/dev/null 2>&1 || npm cache clean --force >/dev/null 2>&1 || true
	fi

	if _exists apt-get; then
		$SUDO apt-get autoremove -y >/dev/null 2>&1 || true
		$SUDO apt-get autoclean -y >/dev/null 2>&1 || true
		$SUDO apt-get clean >/dev/null 2>&1 || true
		$SUDO rm -rf /var/lib/apt/lists/* 2>/dev/null || true
	fi

	# ------------------------------------------------------------
	# 8) Remove temporary installer leftovers
	# ------------------------------------------------------------
	_info "Removing temporary installer leftovers..."

	find /tmp /var/tmp \
		-maxdepth 1 \
		-type f \
		\( -name "nvim*.appimage" -o -name "ripgrep*.deb" -o -name "*.deb" \) \
		-mtime +1 \
		-delete 2>/dev/null || true

	# ------------------------------------------------------------
	# 9) Final verification
	# ------------------------------------------------------------
	echo
	echo "========== clean_install: verification =========="

	if _exists nvim; then
		echo "Neovim:"
		nvim --version | head -n 3 || true
	else
		_warn "nvim command not found."
	fi

	echo

	if _exists vim; then
		echo "Vim:"
		vim --version | head -n 1 || true
	else
		_warn "vim command not found."
	fi

	echo

	if _exists python3; then
		echo "Python provider check:"
		python3 - <<'PY' || true
import sys

mods = ["pynvim", "jedi"]
for mod in mods:
    try:
        __import__(mod)
        print(f"{mod}: OK")
    except Exception as e:
        print(f"{mod}: MISSING ({e})")

print("python:", sys.executable)
PY
	fi

	echo

	if _exists node; then
		echo "Node: $(node --version)"
	else
		_warn "node command not found."
	fi

	if _exists npm; then
		echo "npm: $(npm --version)"
	else
		_warn "npm command not found."
	fi

	if _exists pyright; then
		echo "Pyright: $(pyright --version)"
	else
		_warn "pyright command not found."
	fi

	echo
	echo "========== clean_install: done =========="
}

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
#sudo npm install -g pyright
npm install -g basedpyright

#source "$HOME/.cargo/env" && rustup update
#source "$HOME/.cargo/env" && rustup toolchain install stable
#source "$HOME/.cargo/env" && rustup component add rust-analyzer

#source "$HOME/.cargo/env"
#
#rustup set profile minimal
#
#rustup update
#rustup component add rust-src
#rustup component add rust-analyzer

if [ -f "$HOME/.cargo/env" ]; then
	source "$HOME/.cargo/env"

	rustup set profile minimal
	rustup toolchain install stable --profile minimal
	rustup default stable

	rustup component add rust-analyzer

	# Remove Rust HTML docs if rustup installed them earlier
	rustup component remove rust-docs --toolchain stable 2>/dev/null || true
	rm -rf "$HOME/.rustup/toolchains"/*/share/doc/rust/html
fi

pip3 install neovim pynvim jedi
sudo apt install python3-jedi
pip install neovim pynvim jedi
pip install jedi
pip3 install jedi
#python3 -m pip install tiktoken
#python -m pip install tiktoken

pip install --break-system-packages tiktoken

clean_install
