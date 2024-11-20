#!/bin/bash

# Script to Completely Remove qemu-guest-agent.service and Related Components

set -e

# Function to display messages
function echo_info {
    echo -e "\e[32m[INFO]\e[0m $1"
}

function echo_warn {
    echo -e "\e[33m[WARN]\e[0m $1"
}

function echo_error {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Check if the script is run as root
if [[ "$EUID" -ne 0 ]]; then
   echo_error "This script must be run as root. Use sudo or switch to the root user."
   exit 1
fi

echo_info "Starting the removal process for qemu-guest-agent.service..."

# Stop the qemu-guest-agent service if it's running
if systemctl is-active --quiet qemu-guest-agent.service; then
    echo_info "Stopping qemu-guest-agent.service..."
    systemctl stop qemu-guest-agent.service
else
    echo_info "qemu-guest-agent.service is not running."
fi

# Disable the service to prevent it from starting on boot
if systemctl is-enabled --quiet qemu-guest-agent.service; then
    echo_info "Disabling qemu-guest-agent.service..."
    systemctl disable qemu-guest-agent.service
else
    echo_info "qemu-guest-agent.service is already disabled."
fi

# Remove the service file if it exists
SERVICE_FILE="/lib/systemd/system/qemu-guest-agent.service"
if [[ -f "$SERVICE_FILE" ]]; then
    echo_info "Removing service file: $SERVICE_FILE"
    rm -f "$SERVICE_FILE"
else
    echo_info "Service file $SERVICE_FILE does not exist."
fi

# Reload systemd daemon to apply changes
echo_info "Reloading systemd daemon..."
systemctl daemon-reload

# Identify the package name for qemu-guest-agent
# This may vary based on the distribution
PKG_NAME=""
if dpkg -l | grep -qw qemu-guest-agent; then
    PKG_NAME="qemu-guest-agent"
elif rpm -qa | grep -qw qemu-guest-agent; then
    PKG_NAME="qemu-guest-agent"
else
    echo_warn "qemu-guest-agent package not found via dpkg or rpm."
fi

# Uninstall the package if found
if [[ -n "$PKG_NAME" ]]; then
    echo_info "Uninstalling package: $PKG_NAME"
    if command -v apt-get &> /dev/null; then
        apt-get purge -y "$PKG_NAME"
        apt-get autoremove -y
    elif command -v yum &> /dev/null; then
        yum remove -y "$PKG_NAME"
    elif command -v dnf &> /dev/null; then
        dnf remove -y "$PKG_NAME"
    elif command -v pacman &> /dev/null; then
        pacman -Rns --noconfirm "$PKG_NAME"
    else
        echo_warn "Package manager not recognized. Please remove $PKG_NAME manually."
    fi
else
    echo_warn "qemu-guest-agent package not identified. Skipping package removal."
fi

# Remove any remaining related files or directories
# Common locations
RELATED_PATHS=(
    "/etc/qemu-guest-agent"
    "/var/lib/qemu-guest-agent"
    "/usr/sbin/qemu-ga"
    "/usr/lib/qemu/qemu-ga"
    "/usr/share/doc/qemu-guest-agent"
)

for path in "${RELATED_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
        echo_info "Removing $path..."
        rm -rf "$path"
    else
        echo_info "$path does not exist. Skipping."
    fi
done

# Final systemd daemon reload
echo_info "Final systemd daemon reload..."
systemctl daemon-reload

echo_info "qemu-guest-agent.service and its related components have been successfully removed."


#exit 0
############################
############################
############################
#!/bin/bash

# Stop the service
systemctl stop qemu-guest-agent.service

# Disable the service
systemctl disable qemu-guest-agent.service 2>/dev/null || true

# Remove the package
if command -v apt-get &>/dev/null; then
    apt-get purge -y qemu-guest-agent
    apt-get autoremove -y
elif command -v dnf &>/dev/null; then
    dnf remove -y qemu-guest-agent
elif command -v yum &>/dev/null; then
    yum remove -y qemu-guest-agent
fi

# Remove service files
rm -f /lib/systemd/system/qemu-guest-agent.service
rm -f /etc/systemd/system/qemu-guest-agent.service
rm -f /etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service

# Remove binary and related files
rm -f /usr/sbin/qemu-ga
rm -rf /var/run/qemu-ga/

# Remove any remaining configuration files
rm -rf /etc/qemu-ga/

# Reload systemd to recognize changes
systemctl daemon-reload

echo "QEMU Guest Agent has been completely removed."
