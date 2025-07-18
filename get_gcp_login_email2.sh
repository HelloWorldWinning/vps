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

# Check for gcloud
if ! command -v gcloud &>/dev/null; then
	echo "Error: gcloud CLI is not installed." >&2
	exit 1
fi

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
