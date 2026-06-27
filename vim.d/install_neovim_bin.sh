#!/bin/bash

wget --inet4-only -O ~/.vimrc https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/vimrc.use
wget --inet4-only -O ~/.config/nvim/init.vim https://raw.githubusercontent.com/HelloWorldWinning/vps/main/vim.d/nvim.use

sudo rm -rf /tmp/* 2>/dev/null || true

clean_install() {
	echo "=== Running clean_install cleanup ==="

	# Safety guard for rm -rf
	safe_rm_rf() {
		local target="$1"

		if [ -z "$target" ]; then
			echo "Skip empty path"
			return 0
		fi

		case "$target" in
		"/" | "$HOME" | "/root" | "/home")
			echo "Refusing to remove unsafe path: $target"
			return 1
			;;
		esac

		if [ -e "$target" ]; then
			echo "Removing: $target"
			rm -rf "$target"
		fi
	}

	# Remove Neovim build directory
	if [ -n "${BUILD_DIR:-}" ]; then
		safe_rm_rf "$BUILD_DIR"
	fi

	# Remove common temporary build leftovers
	safe_rm_rf "$HOME/nvim_build_temp"
	safe_rm_rf "/tmp/nvim_build_temp"

	# Clean package/cache leftovers, but do not remove installed Neovim
	if command -v apt >/dev/null 2>&1; then
		sudo apt clean || true
		sudo apt autoclean || true
	fi

	if command -v npm >/dev/null 2>&1; then
		npm cache clean --force >/dev/null 2>&1 || true
	fi

	if command -v pip >/dev/null 2>&1; then
		pip cache purge >/dev/null 2>&1 || true
	fi

	if [ -x "/root/miniconda3/bin/python" ]; then
		/root/miniconda3/bin/python -m pip cache purge >/dev/null 2>&1 || true
	fi

	# Clean only temporary files related to this install, not all /tmp
	find /tmp -maxdepth 1 \
		-name "nvim*" -o \
		-name "neovim*" -o \
		-name "cmake*" \
		-exec rm -rf {} + 2>/dev/null || true

	echo "=== clean_install cleanup completed ==="
}
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
#python3 -m pip install tiktoken
#python -m pip install tiktoken

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

#source "$HOME/.cargo/env" && rustup update
#source "$HOME/.cargo/env" && rustup toolchain install stable
#source "$HOME/.cargo/env" && rustup component add rust-analyzer

#source "$HOME/.cargo/env"
#rustup set profile minimal
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

/root/miniconda3/bin/python -m pip install pynvim
/root/miniconda3/bin/python -m pip install neovim
python -m pip install pynvim
python -m pip install neovim
#python3 -m pip install tiktoken
#python -m pip install tiktoken
pip install --break-system-packages tiktoken
clean_install
