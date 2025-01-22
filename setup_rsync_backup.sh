#!/bin/bash

# Function to log messages with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Function to resolve domain to IP
resolve_ip() {
    local domain=$1
    local ip
    ip=$(dig +short "$domain" | grep -E '^[0-9.]+$' | head -n 1)
    if [[ -z "$ip" ]]; then
        log "Failed to resolve domain '$domain' to an IP address."
        exit 1
    fi
    echo "$ip"
}

# Prompt for VPS2 IP or Domain
read -p "Enter the IP address or domain of VPS Destination: " vps2_input
if [[ -z "$vps2_input" ]]; then
    log "VPS Destination  IP or domain is required."
    exit 1
fi

# Check if input is a valid IP
if [[ "$vps2_input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    VPS2_IP="$vps2_input"
else
    # Assume it's a domain and resolve to IP
    VPS2_IP=$(resolve_ip "$vps2_input")
    log "Resolved domain '$vps2_input' to IP '$VPS2_IP'."
fi

# Define REMOTE_BACKUP_PATH as /data/Backup/<hostname>
REMOTE_BACKUP_PATH="/data/Backup/$(hostname)"
log "Remote backup path set to: $REMOTE_BACKUP_PATH"

# Prompt for Backup Path on VPS1
read -t 10 -p "Enter the backup path on VPS Source [Default: current directory]: " LOCAL_BACKUP_PATH
if [[ -z "$LOCAL_BACKUP_PATH" ]]; then
    LOCAL_BACKUP_PATH="$(pwd)"
    log "No input provided. Using current directory: $LOCAL_BACKUP_PATH"
else
    log "Backup path on VPS1 set to: $LOCAL_BACKUP_PATH"
fi

# Define variables
RSYNC_USER="rsyncbackup"
RSYNC_PORT=54322
BACKUP_SCRIPT="/usr/local/bin/rsync_backup.sh"
CRON_JOB="0 */12 * * * $BACKUP_SCRIPT"

# Ensure the remote backup directory exists on VPS2 using sudo
log "Ensuring remote backup directory exists on VPS Destination..."
ssh -p "$RSYNC_PORT" "$RSYNC_USER@$VPS2_IP" "sudo mkdir -p '$REMOTE_BACKUP_PATH' && sudo chown -R $RSYNC_USER:$RSYNC_USER '$REMOTE_BACKUP_PATH'"
if [[ $? -ne 0 ]]; then
    log "Failed to create remote backup directory on VPS Destination. Please check SSH connectivity and permissions."
    exit 1
fi
log "Remote backup directory is ready."

# Create the backup script
log "Creating backup script at $BACKUP_SCRIPT..."
cat > "$BACKUP_SCRIPT" << EOF
#!/bin/bash

# Function to log messages with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$*"
}

# Perform rsync
log "Starting backup from '$LOCAL_BACKUP_PATH' to '$RSYNC_USER@$VPS2_IP:$REMOTE_BACKUP_PATH'..."
rsync -avz -e "ssh -p $RSYNC_PORT" "$LOCAL_BACKUP_PATH/" "$RSYNC_USER@$VPS2_IP:$REMOTE_BACKUP_PATH/"

if [[ \$? -eq 0 ]]; then
    log "Backup completed successfully."
else
    log "Backup failed. Check the logs for more details."
fi
EOF

# Make the backup script executable
chmod +x "$BACKUP_SCRIPT"
log "Backup script created and made executable."

# Add cron job
log "Adding cron job to run the backup every 12 hours..."
# Check if the cron job already exists
(crontab -l 2>/dev/null | grep -F "$BACKUP_SCRIPT") && EXISTS=true || EXISTS=false

if [ "$EXISTS" = false ]; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    log "Cron job added successfully."
else
    log "Cron job already exists. Skipping addition."
fi

    log "Running backup script now..."
    bash "$BACKUP_SCRIPT"
log "Setup completed successfully!"
