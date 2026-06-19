#!/usr/bin/env bash
set -euo pipefail

echo "Updating package index..."
sudo apt update -y

echo "Installing required dependencies..."
sudo apt install -y curl build-essential pkg-config libssl-dev

echo "Installing Rust using rustup with minimal profile..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal

echo "Configuring Rust environment..."
# shellcheck disable=SC1090
source "$HOME/.cargo/env"

echo "Setting rustup profile to minimal..."
rustup set profile minimal

echo "Ensuring stable toolchain is installed without Rust HTML docs..."
rustup toolchain install stable --profile minimal
rustup default stable

echo "Removing Rust HTML documentation if present..."
rustup component remove rust-docs --toolchain stable 2>/dev/null || true
rm -rf "$HOME/.rustup/toolchains"/*/share/doc/rust/html

echo "Verifying Rust installation..."
rustc --version
cargo --version

echo "Checking that Rust HTML docs were removed..."
if find "$HOME/.rustup/toolchains" -path "*/share/doc/rust/html" -type d 2>/dev/null | grep -q .; then
	echo "Warning: Rust HTML docs still exist:"
	find "$HOME/.rustup/toolchains" -path "*/share/doc/rust/html" -type d 2>/dev/null
else
	echo "OK: no share/doc/rust/html directory found."
fi

echo "Rust installation completed successfully!"
