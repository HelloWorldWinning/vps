#!/bin/bash

wget --inet4-only -O ~/.vimrc https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/vimrc.use
wget --inet4-only -O ~/.config/nvim/init.vim https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/nvim.use

sudo rm -rf /tmp/* 2>/dev/null || true

#set -e # Exit immediately if a command exits with a non-zero status

# Define installation directory
INSTALL_DIR="$HOME/.local/nvim"
BIN_DIR="$HOME/.local/bin"

# Create necessary directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

echo "=== Installing dependencies ==="
sudo apt update
sudo apt install -y ninja-build gettext cmake unzip curl git

echo "=== Cloning Neovim repository ==="
# Use a temporary directory for building
#BUILD_DIR=$(mktemp -d)
#cd "$BUILD_DIR"

BUILD_DIR="$HOME/nvim_build_temp"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
git clone https://github.com/neovim/neovim
cd neovim

# Clean up any previous failed attempts
rm -rf neovim
git clone https://github.com/neovim/neovim
cd neovim

echo "=== Building Neovim ==="
make CMAKE_BUILD_TYPE=RelWithDebInfo CMAKE_INSTALL_PREFIX="$INSTALL_DIR"

echo "=== Installing Neovim to $INSTALL_DIR ==="
make install

echo "=== Creating symlink to $BIN_DIR ==="
ln -sf "$INSTALL_DIR/bin/nvim" "$BIN_DIR/nvim"

# Add to PATH if not already there
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
	echo "=== Adding $BIN_DIR to PATH ==="
	echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.bashrc"
	echo "Please run 'source ~/.bashrc' or start a new terminal session to update your PATH."
fi

echo "=== Cleaning up build files ==="
cd "$HOME"
rm -rf "$BUILD_DIR"

echo "=== Neovim installation completed ==="
echo "You can now run Neovim using: $BIN_DIR/nvim"
echo "Current Neovim version:"
"$BIN_DIR/nvim" --version | head -n 1

# Check if the installation was successful
if [ -x "$BIN_DIR/nvim" ]; then
	echo "=== Installation successful! ==="
else
	echo "=== Installation failed! ==="
	exit 1
fi

# Define the path to your bashrc file
BASHRC="$HOME/.bashrc"

# Comment out the old alias if it exists and is not already commented out
if grep -q "^alias k='/usr/bin/nvim.appimage'" "$BASHRC"; then
	sed -i "s|^alias k='/usr/bin/nvim.appimage'|# alias k='/usr/bin/nvim.appimage'|" "$BASHRC"
	echo "Old alias commented out."
fi

# Append the new alias if it does not already exist
if ! grep -q "^alias k='/root/.local/bin/nvim'" "$BASHRC"; then
	echo "alias k='/root/.local/bin/nvim'" >>"$BASHRC"
	echo "New alias added."
fi

/root/miniconda3/bin/python -m pip install pynvim
/root/miniconda3/bin/python -m pip install neovim
python -m pip install pynvim
python -m pip install neovim

bash <(curl -L4 https://raw.githubusercontent.com/HelloWorldWinning/vps/main/handle_nvim_pluges.sh)

# Source the updated bashrc file to apply changes immediately

source "$BASHRC"
source /root/.bashrc
echo "Bashrc reloaded."

echo "=== Cleaning up build files ==="
cd "$HOME"
rm -rf "$BUILD_DIR"

echo "=== Neovim installation completed ==="

sudo apt update
sudo apt install -y nodejs npm
sudo npm install -g pyright

rustup update
rustup toolchain install stable
rustup component add rust-analyzer
