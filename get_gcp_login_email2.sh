#!/usr/bin/env bash
# get_gcp_login_email2.sh
# Fetches and echoes the Gmail address used for gcloud auth from GCP VM metadata

# ANSI color codes
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
reset='\033[0m'
sep='-------------------------'

# Function to check if running on GCP VM
is_gcp_vm() {
    # Check if we can reach Google metadata server
    if curl -s --connect-timeout 3 -H "Metadata-Flavor: Google" \
       "http://169.254.169.254/computeMetadata/v1/instance/id" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to install gcloud CLI
install_gcloud() {
    echo -e "${yellow}gcloud CLI not found. Installing...${reset}"
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux installation
        echo "Installing gcloud CLI for Linux..."
        
        # Create keyring directory if it doesn't exist
        sudo mkdir -p /usr/share/keyrings
        
        # Add Google Cloud SDK repository
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
        
        # Install required packages
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
        
        # Import Google Cloud public key
        curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
        
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
            # Source the path
            source ~/google-cloud-sdk/path.bash.inc
        fi
        
    else
        echo -e "${red}Unsupported operating system: $OSTYPE${reset}"
        echo "Please install gcloud CLI manually: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Verify installation
    if command -v gcloud &>/dev/null; then
        echo -e "${green}✓ gcloud CLI installed successfully!${reset}"
    else
        echo -e "${red}✗ Failed to install gcloud CLI${reset}"
        exit 1
    fi
}

# Function to get email from multiple sources
get_gcp_email() {
    local email=""
    
    # Method 1: Try to get from gcloud auth list
    if command -v gcloud &>/dev/null; then
        email=$(gcloud auth list --format="value(account)" --filter="status:ACTIVE" 2>/dev/null | head -n1)
    fi
    
    # Method 2: Try SSH keys metadata if first method fails
    if [[ -z "$email" ]]; then
        local metadata_url="http://169.254.169.254/computeMetadata/v1/instance/attributes/ssh-keys"
        local header="Metadata-Flavor: Google"
        
        email=$(curl -s -H "$header" "$metadata_url" 2>/dev/null | \
                grep -oE '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]+' | \
                head -n1)
    fi
    
    # Method 3: Try service account from metadata
    if [[ -z "$email" ]]; then
        local sa_url="http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/email"
        email=$(curl -s -H "Metadata-Flavor: Google" "$sa_url" 2>/dev/null)
    fi
    
    echo "$email"
}

# Main script logic
main() {
    # Step 1: Check if we are in GCP VM
    echo "Checking if running on GCP VM..."
    if ! is_gcp_vm; then
        echo -e "${yellow}Info: Not running on a Google Cloud Platform VM.${reset}"
        echo "This script is designed to work on GCP VMs to extract authentication email."
        exit 0
    fi
    
    echo -e "${green}✓ Running on GCP VM${reset}"
    
    # Step 2: Check if gcloud CLI is installed
    echo "Checking gcloud CLI..."
    if ! command -v gcloud &>/dev/null; then
        # Step 3: Install gcloud CLI if not present
        install_gcloud
    else
        echo -e "${green}✓ gcloud CLI is already installed${reset}"
    fi
    
    # Step 4: Get and display the email
    echo "Retrieving authentication email..."
    local email=$(get_gcp_email)
    
    if [[ -n "$email" ]]; then
        echo -e "$sep"
        echo -e "${red}${email}${reset}"
        echo -e "$sep"
        exit 0
    else
        echo -e "${red}No email address found from any source.${reset}" >&2
        echo "Tried:"
        echo "- gcloud auth list"
        echo "- SSH keys metadata" 
        echo "- Service account metadata"
        exit 1
    fi
}

# Run main function
main "$@"
