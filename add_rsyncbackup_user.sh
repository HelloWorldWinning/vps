#!/bin/bash

# Function to log messages with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   log "This script must be run as root"
   exit 1
fi

# Create rsyncbackup user (if it doesn't already exist)
if id rsyncbackup &>/dev/null; then
    log "User 'rsyncbackup' already exists. Skipping creation."
else
    log "Creating rsyncbackup user..."
    useradd -m -s /bin/bash rsyncbackup
fi

# Create .ssh directory for rsyncbackup user
log "Setting up SSH directory..."
mkdir -p /home/rsyncbackup/.ssh
chmod 700 /home/rsyncbackup/.ssh

# Copy SSH files from root
log "Copying SSH keys from root..."
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/rsyncbackup/.ssh/
fi

if ls /root/.ssh/id_rsa* &>/dev/null; then
    cp -r /root/.ssh/id_rsa* /home/rsyncbackup/.ssh/
else
    log "No private keys found to copy (normal if this is VPS2)."
fi

# Set correct ownership and permissions
log "Setting correct permissions..."
chown -R rsyncbackup:rsyncbackup /home/rsyncbackup/.ssh
chmod 600 /home/rsyncbackup/.ssh/authorized_keys 2>/dev/null || true
find /home/rsyncbackup/.ssh -name 'id_rsa*' -exec chmod 600 {} \; 2>/dev/null

# Create minimal .bashrc
log "Creating minimal .bashrc..."
cat > /home/rsyncbackup/.bashrc << 'EOF'
# Minimal .bashrc for rsyncbackup user
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
chown rsyncbackup:rsyncbackup /home/rsyncbackup/.bashrc

# Create backup directory if this is VPS2
if [ ! -d "/data/Backup" ]; then
    log "Creating backup directory..."
    mkdir -p /data/Backup
    chown rsyncbackup:rsyncbackup /data/Backup
fi

# Add rsyncbackup user to the sudo group (so it can sudo)
log "Adding user 'rsyncbackup' to the sudo group..."
usermod -aG sudo rsyncbackup

# Set up sudoers entry for commands that the rsyncbackup user will need
log "Setting up sudoers entry for 'rsyncbackup'..."
cat > /etc/sudoers.d/rsyncbackup << 'EOF'
# Allow rsyncbackup to run 'borg' and the following commands without password:
# - mv, mkdir, chown, chmod (for file management in the script)
# - systemctl (to enable/start the service/timer)
rsyncbackup ALL=(ALL) NOPASSWD: /usr/bin/borg, /bin/mv, /bin/mkdir, /bin/chown, /bin/chmod, /usr/bin/systemctl
EOF

chmod 440 /etc/sudoers.d/rsyncbackup

log "Setup completed successfully!"
log "Notes:"
log "- Run this script on BOTH VPS1 and VPS2 as root."
log "- The rsyncbackup user is now set up with root's SSH keys."
log "- A minimal .bashrc has been created."
log "- The /data/Backup directory has been created (if not existing)."
log "- The rsyncbackup user can run necessary commands without password."





# Get and display hostname information
HOSTNAME=$(hostname)
log "-----------------------------------------------------"
log "Current server hostname: $HOSTNAME"
log "-----------------------------------------------------"
log "If this is your backup SOURCE server (VPS1), enter 'y' to continue with backup setup."
log "If this is your backup DESTINATION server (VPS2), enter 'n' to finish setup."

read -p "Do you want to proceed with setting up the backup configuration? [y/N] " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    log "Downloading setup_rsync_backup.sh..."
    curl -s https://raw.githubusercontent.com/HelloWorldWinning/vps/main/setup_rsync_backup.sh -o /tmp/setup_rsync_backup.sh
    chmod +x /tmp/setup_rsync_backup.sh
    log "Running setup_rsync_backup.sh..."
    bash /tmp/setup_rsync_backup.sh
yes|    rm -f /tmp/setup_rsync_backup.sh
else
    log "Setup completed. No backup configuration will be performed on this server."
fi
