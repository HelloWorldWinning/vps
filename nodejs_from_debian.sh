# Remove NodeSource Node.js completely
sudo apt remove -y nodejs npm
sudo apt autoremove -y

# Clean up any remaining NodeSource packages
sudo dpkg --purge nodejs npm 2>/dev/null || true

# Update package lists
sudo apt update

# Install the required library first
sudo apt install -y libuv1t64

# Now install Node.js from Debian
sudo apt install -y nodejs npm

# Verify
node --version
npm --version
