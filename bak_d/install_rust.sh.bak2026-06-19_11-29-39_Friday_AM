#!/usr/bin/env bash
set -e

# Update system package index
echo "Updating package index..."
sudo apt update -y

# Install required dependencies for building Rust projects
echo "Installing required dependencies..."
sudo apt install -y curl build-essential pkg-config libssl-dev

# Download and run rustup installer
echo "Installing Rust using rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Add Rust to current shell session
echo "Configuring environment..."
source $HOME/.cargo/env

# Verify installation
echo "Verifying Rust installation..."
rustc --version
cargo --version

echo "Rust installation completed successfully!"

