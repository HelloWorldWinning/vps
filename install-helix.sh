#!/bin/bash
# Remove existing helix directory
echo 'export COLORTERM=truecolor' >> ~/.bashrc
mkdir -p ~/.config/helix/
cat > ~/.config/helix/config.toml << "EOF"
theme = "acme"
#inherits = "gruvbox"
[editor]
line-number = "relative"
mouse = true
EOF

mkdir -p ~/src
cd ~/src
/usr/bin/rm -rf helix

# Clone fresh
git clone https://github.com/helix-editor/helix
cd helix

# Build with grammars disabled initially
export HELIX_DISABLE_AUTO_GRAMMAR_BUILD=1
cargo install --path helix-term --locked

# Set up runtime
mkdir -p ~/.config/helix
ln -sf ~/src/helix/runtime ~/.config/helix/runtime

# Fetch and build grammars
hx --grammar fetch
hx --grammar build




# Error handling
set -e

echo "Starting Helix installation..."

# Function to check command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 could not be found, installing..."
        return 1
    else
        echo "$1 is already installed"
        return 0
    fi
}

# Install prerequisites
install_prerequisites() {
    echo "Installing prerequisites..."
    sudo apt update
    sudo apt install -y build-essential git pkg-config libpython3-dev curl
}

# Install Rust if not present
install_rust() {
    if ! check_command cargo; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
}

# Create necessary directories
setup_directories() {
    echo "Setting up directories..."
    mkdir -p ~/src
    mkdir -p ~/.config/helix
}

# Clean existing installation if needed
clean_existing() {
    echo "Cleaning any existing installation..."
    if [ -d "~/src/helix" ]; then
        rm -rf ~/src/helix
    fi
    if [ -d "~/.cargo/registry/src/*/helix-*" ]; then
        rm -rf ~/.cargo/registry/src/*/helix-*
    fi
}

# Clone and build Helix
build_helix() {
    echo "Cloning and building Helix..."
    cd ~/src
    git clone https://github.com/helix-editor/helix
    cd helix
    
    # Set environment variable to skip grammar build during initial compilation
    export HELIX_DISABLE_AUTO_GRAMMAR_BUILD=1
    
    # Build with locked dependencies
    cargo install --path helix-term --locked
    
    # Unset the environment variable
    unset HELIX_DISABLE_AUTO_GRAMMAR_BUILD
}

# Configure runtime
configure_runtime() {
    echo "Configuring Helix runtime..."
    if [ -L ~/.config/helix/runtime ]; then
        echo "Runtime symlink exists, removing..."
        rm ~/.config/helix/runtime
    fi
    ln -s ~/src/helix/runtime ~/.config/helix/runtime
}

# Setup language support with error handling
setup_languages() {
    echo "Setting up language support..."
    
    # First, fetch grammars
    hx --grammar fetch || {
        echo "Warning: Some grammars failed to fetch. Continuing..."
    }
    
    # Then build grammars, excluding problematic ones
    RUST_BACKTRACE=1 hx --grammar build || {
        echo "Warning: Some grammars failed to build. This is normal for certain languages."
        echo "Basic editor functionality will still work."
    }
}

# Add to PATH and set environment variables
setup_path() {
    if ! grep -q "HELIX_RUNTIME" ~/.bashrc; then
        echo "Adding Helix runtime to ~/.bashrc..."
        echo 'export HELIX_RUNTIME=~/src/helix/runtime' >> ~/.bashrc
    fi
}

# Create basic config
create_basic_config() {
    echo "Creating basic configuration..."
    mkdir -p ~/.config/helix
    cat > ~/.config/helix/config.toml << EOF
theme = "base16"

[editor]
line-number = "relative"
mouse = true
auto-completion = true

[editor.cursor-shape]
insert = "bar"
normal = "block"
select = "underline"

[editor.file-picker]
hidden = false
EOF
}

# Validate installation
validate_installation() {
    echo "Validating installation..."
    if command -v hx &> /dev/null; then
        echo "Helix successfully installed!"
        hx --version
        echo "Installation complete! Please restart your terminal or run 'source ~/.bashrc'"
    else
        echo "Installation failed!"
        exit 1
    fi
}

# Main installation process
main() {
    install_prerequisites
    install_rust
    setup_directories
    clean_existing
    build_helix
    configure_runtime
    setup_languages
    setup_path
    create_basic_config
    validate_installation
}

# Run the installation
main


sudo /usr/bin/rm  -rf /root/src/helix

