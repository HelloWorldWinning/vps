#!/bin/bash

# Script to disable systemd-timesyncd and setup chrony
# Run with sudo privileges

echo "=== Switching from systemd-timesyncd to chrony ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root (use sudo)"
	exit 1
fi

# Function to safely handle systemd-timesyncd
handle_timesyncd() {
	# Check if systemd-timesyncd service exists
	if systemctl list-unit-files systemd-timesyncd.service &>/dev/null; then
		echo "systemd-timesyncd service found"

		# Check if it's active and stop it
		if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
			echo "Stopping systemd-timesyncd service..."
			systemctl stop systemd-timesyncd || echo "Warning: Failed to stop systemd-timesyncd"
		else
			echo "systemd-timesyncd is not running"
		fi

		# Check if it's enabled and disable it
		if systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null; then
			echo "Disabling systemd-timesyncd service..."
			systemctl disable systemd-timesyncd || echo "Warning: Failed to disable systemd-timesyncd"
		else
			echo "systemd-timesyncd is not enabled"
		fi

		# Mask the service to prevent it from being started accidentally
		echo "Masking systemd-timesyncd service..."
		systemctl mask systemd-timesyncd || echo "Warning: Failed to mask systemd-timesyncd"

	else
		echo "systemd-timesyncd service not found - skipping"
	fi
}

# Handle systemd-timesyncd
handle_timesyncd

# Ensure chrony is installed and running
ensure_chrony_running() {
	echo ""
	echo "=== Setting up chrony ==="

	# Update package list
	echo "Updating package list..."
	apt update || {
		echo "Error: Failed to update package list"
		exit 1
	}

	# Install chrony if not already installed
	if ! dpkg -l chrony &>/dev/null; then
		echo "Installing chrony..."
		apt install -y chrony || {
			echo "Error: Failed to install chrony"
			exit 1
		}
	else
		echo "chrony is already installed"
	fi

	# Enable chrony service
	echo "Enabling chrony service..."
	systemctl enable chrony || {
		echo "Error: Failed to enable chrony"
		exit 1
	}

	# Start chrony service if not running
	if ! systemctl is-active --quiet chrony; then
		echo "Starting chrony service..."
		systemctl start chrony || {
			echo "Error: Failed to start chrony"
			exit 1
		}
	else
		echo "chrony service is already running"
	fi

	# Restart chrony to ensure clean state
	echo "Restarting chrony service to ensure clean state..."
	systemctl restart chrony || {
		echo "Error: Failed to restart chrony"
		exit 1
	}

	# Wait a moment for chrony to initialize
	sleep 3

	# Verify chrony is running
	if systemctl is-active --quiet chrony; then
		echo "✓ chrony service is running successfully"
	else
		echo "✗ Error: chrony service failed to start"
		exit 1
	fi
}

# Setup chrony
ensure_chrony_running

# Show final status
echo ""
echo "=== Final Status ==="

# Check systemd-timesyncd final status
if systemctl list-unit-files systemd-timesyncd.service &>/dev/null; then
	echo "systemd-timesyncd status: $(systemctl is-enabled systemd-timesyncd 2>/dev/null || echo 'disabled')"
else
	echo "systemd-timesyncd: not present"
fi

# Check chrony status
echo "chrony status: $(systemctl is-active chrony)"
echo "chrony enabled: $(systemctl is-enabled chrony)"

# Show chrony operational status
echo ""
echo "=== Chrony Time Synchronization Status ==="
if command -v chronyc &>/dev/null; then
	echo "Chrony sources:"
	chronyc sources || echo "Warning: Could not get chrony sources"

	echo ""
	echo "Chrony tracking:"
	chronyc tracking || echo "Warning: Could not get chrony tracking info"
else
	echo "chronyc command not available"
fi

echo ""
echo "=== Migration completed successfully! ==="
echo "✓ systemd-timesyncd handled appropriately"
echo "✓ chrony is installed, enabled, and running"
echo ""
echo "You can monitor time synchronization with:"
echo "  sudo chronyc sources -v"
echo "  sudo chronyc tracking"
echo "  sudo systemctl status chrony"
