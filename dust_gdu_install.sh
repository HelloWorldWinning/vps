#!/bin/bash

# Script to install the latest version of dust and clean up

set -e # Exit on any error

echo "Fetching latest dust release information..."

# Get the latest release info from GitHub API
LATEST_RELEASE=$(curl -s https://api.github.com/repos/bootandy/dust/releases/latest)

# Extract the latest version tag
LATEST_VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

# Determine architecture
ARCH=$(dpkg --print-architecture)

# Construct download URL
DEB_FILENAME="du-dust_${LATEST_VERSION#v}-1_${ARCH}.deb"
DOWNLOAD_URL="https://github.com/bootandy/dust/releases/download/${LATEST_VERSION}/${DEB_FILENAME}"

echo "Latest version: $LATEST_VERSION"
echo "Architecture: $ARCH"
echo "Download URL: $DOWNLOAD_URL"

# Download the .deb file
echo "Downloading $DEB_FILENAME..."
wget -q --show-progress "$DOWNLOAD_URL"

# Install the package
echo "Installing dust..."
sudo dpkg -i "$DEB_FILENAME"

# Fix any dependency issues if they exist
sudo apt-get install -f -y 2>/dev/null || true

# Clean up - remove the downloaded .deb file
echo "Cleaning up..."
rm -f "$DEB_FILENAME"

echo "✅ Dust $LATEST_VERSION installed successfully and .deb file removed!"

# Verify installation
if command -v dust >/dev/null 2>&1; then
	echo "Verification: $(dust --version)"
else
	echo "⚠️  Warning: dust command not found in PATH"
fi

# Example for v5, check for the latest version
curl -L https://github.com/dundee/gdu/releases/latest/download/gdu_linux_amd64.tgz | tar xz
chmod +x gdu_linux_amd64
sudo mv gdu_linux_amd64 /usr/local/bin/gdu

echo "========gdu========="
gdu --version
