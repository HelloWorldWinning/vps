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
    apt update || { echo "Error: Failed to update package list"; exit 1; }
    
    # Install chrony if not already installed
    if ! dpkg -l chrony &>/dev/null; then
        echo "Installing chrony..."
        apt install -y chrony || { echo "Error: Failed to install chrony"; exit 1; }
    else
        echo "chrony is already installed"
    fi
    
    # Force reinstall chrony to ensure service files are created
    echo "Reinstalling chrony to ensure proper service files..."
    apt reinstall -y chrony || { echo "Error: Failed to reinstall chrony"; exit 1; }
    
    # Reload systemd daemon to pick up any new service files
    echo "Reloading systemd daemon..."
    systemctl daemon-reload
    
    # Detect the correct chrony service name
    CHRONY_SERVICE=""
    echo "Detecting chrony service name..."
    
    # Check common chrony service names
    for service_name in chronyd chrony chrony.service chronyd.service; do
        if systemctl list-unit-files "$service_name" &>/dev/null; then
            CHRONY_SERVICE="${service_name%.service}"  # Remove .service suffix if present
            echo "Found chrony service: $CHRONY_SERVICE"
            break
        fi
    done
    
    # If still not found, search more broadly
    if [ -z "$CHRONY_SERVICE" ]; then
        echo "Searching for chrony-related services..."
        CHRONY_SERVICE=$(systemctl list-unit-files | grep -i chrony | head -1 | awk '{print $1}' | sed 's/\.service$//')
        if [ -n "$CHRONY_SERVICE" ]; then
            echo "Found chrony service: $CHRONY_SERVICE"
        fi
    fi
    
    # Check if chrony daemon is in PATH (alternative approach)
    if [ -z "$CHRONY_SERVICE" ] && command -v chronyd &>/dev/null; then
        echo "chronyd binary found, checking if we can start it manually..."
        
        # Create a simple systemd service for chronyd if it doesn't exist
        if [ ! -f /etc/systemd/system/chronyd.service ]; then
            echo "Creating chronyd service file..."
            cat > /etc/systemd/system/chronyd.service << EOF
[Unit]
Description=NTP client/server
Documentation=man:chronyd(8) man:chrony.conf(5)
After=ntpdate.service sntp.service ntpd.service
Conflicts=ntpd.service systemd-timesyncd.service
ConditionCapability=CAP_SYS_TIME

[Service]
Type=forking
PIDFile=/run/chrony/chronyd.pid
EnvironmentFile=-/etc/default/chronyd
ExecStart=/usr/sbin/chronyd \$DAEMON_OPTS
ExecStartPost=/bin/sh -c "sleep 0.2; /usr/bin/chronyc tracking > /dev/null || { echo 'chronyd failed to start' >&2; exit 1; }"
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            CHRONY_SERVICE="chronyd"
            echo "Created chronyd service file"
        fi
    fi
    
    if [ -z "$CHRONY_SERVICE" ]; then
        echo "Error: No chrony service found and unable to create one"
        echo ""
        echo "Debugging information:"
        echo "Chrony package contents:"
        dpkg -L chrony | grep -E "(systemd|service)" || echo "No systemd service files found"
        echo ""
        echo "Available chrony binaries:"
        find /usr -name "*chrony*" -type f 2>/dev/null || echo "No chrony binaries found"
        echo ""
        echo "Manual start attempt:"
        if command -v chronyd &>/dev/null; then
            echo "chronyd binary exists at: $(which chronyd)"
            echo "Try starting manually: sudo chronyd -d"
        else
            echo "chronyd binary not found"
        fi
        exit 1
    fi
    
    # Enable chrony service
    echo "Enabling $CHRONY_SERVICE service..."
    systemctl enable $CHRONY_SERVICE || { echo "Error: Failed to enable $CHRONY_SERVICE"; exit 1; }
    
    # Start chrony service if not running
    if ! systemctl is-active --quiet $CHRONY_SERVICE; then
        echo "Starting $CHRONY_SERVICE service..."
        systemctl start $CHRONY_SERVICE || { echo "Error: Failed to start $CHRONY_SERVICE"; exit 1; }
    else
        echo "$CHRONY_SERVICE service is already running"
    fi
    
    # Restart chrony to ensure clean state
    echo "Restarting $CHRONY_SERVICE service to ensure clean state..."
    systemctl restart $CHRONY_SERVICE || { echo "Error: Failed to restart $CHRONY_SERVICE"; exit 1; }
    
    # Wait a moment for chrony to initialize
    sleep 3
    
    # Verify chrony is running
    if systemctl is-active --quiet $CHRONY_SERVICE; then
        echo "✓ $CHRONY_SERVICE service is running successfully"
    else
        echo "✗ Error: $CHRONY_SERVICE service failed to start"
        systemctl status $CHRONY_SERVICE --no-pager
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
echo "chrony status: $(systemctl is-active $CHRONY_SERVICE 2>/dev/null || echo 'unknown')"
echo "chrony enabled: $(systemctl is-enabled $CHRONY_SERVICE 2>/dev/null || echo 'unknown')"

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
echo "  sudo systemctl status $CHRONY_SERVICE"
