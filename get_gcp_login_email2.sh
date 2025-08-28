#!/usr/bin/env bash
# get_gcp_login_email.sh
# Fetches and echoes the Gmail address used for gcloud auth (from SSH keys metadata), outputting the email in red with custom separators.

# ANSI color codes
red='\033[0;31m'
reset='\033[0m'
sep='-------------------------'

# Metadata endpoint for SSH keys
metadata_url="http://169.254.169.254/computeMetadata/v1/instance/attributes/ssh-keys"
header="Metadata-Flavor: Google"

# Check for curl
if ! command -v curl &>/dev/null; then
	echo "Error: curl is not installed." >&2
	exit 1
fi

## Check for gcloud
#if ! command -v gcloud &>/dev/null; then
#	echo "Error: gcloud CLI is not installed." >&2
#	exit 1
#fi

 
# Function to install gcloud CLI
install_gcloud() {
    echo "gcloud CLI not found. Installing..."
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux installation
        echo "Installing gcloud CLI for Linux..."
        
        # Add Google Cloud SDK repository
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
        
        # Install required packages
        sudo apt-get install -y apt-transport-https ca-certificates gnupg
        
        # Import Google Cloud public key
        curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
        
        # Update and install
        sudo apt-get update && sudo apt-get install -y google-cloud-cli
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS installation
        echo "Installing gcloud CLI for macOS..."
        
        if command -v brew &>/dev/null; then
            # Use Homebrew if available
            brew install --cask google-cloud-sdk
        else
            # Direct download method
            curl https://sdk.cloud.google.com | bash
            exec -l $SHELL
        fi
        
    else
        echo "Unsupported operating system: $OSTYPE"
        echo "Please install gcloud CLI manually: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Verify installation
    if command -v gcloud &>/dev/null; then
        echo "✓ gcloud CLI installed successfully!"
        gcloud version
    else
        echo "✗ Failed to install gcloud CLI"
        exit 1
    fi
}

# Check for gcloud
if ! command -v gcloud &>/dev/null; then
    install_gcloud
else
    echo "✓ gcloud CLI is already installed"
    gcloud version
fi

# Continue with your script logic here
echo "Ready to use gcloud commands..."



# Retrieve and extract the email address
email=$(curl -s -H "$header" "$metadata_url" |
	grep -oE '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]+' |
	head -n1)

# Display
if [[ -n "$email" ]]; then
	echo -e "$sep"
	echo -e "${red}${email}${reset}"
	echo -e "$sep"
	exit 0
else
	echo "No email address found in SSH keys metadata." >&2
	exit 1
fi
