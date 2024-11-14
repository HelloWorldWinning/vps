#!/bin/bash

# Function to log messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to get container ID from scope name
get_container_id() {
    echo "$1" | grep -o "docker-[a-f0-9]\+" | cut -d'-' -f2
}

log "Starting PHP-FPM container cleanup process..."

# Get all PHP-FPM related container scopes
php_fpm_scopes=$(ps aux | grep "php-fpm" | grep -v grep | grep "docker-" | awk '{print $12}' | sort | uniq)

if [ -z "$php_fpm_scopes" ]; then
    log "No PHP-FPM containers found."
    exit 0
fi

# Array to store unique container IDs
declare -A containers

# Process each scope and get container ID
while read -r scope; do
    container_id=$(get_container_id "$scope")
    if [ ! -z "$container_id" ]; then
        containers["$container_id"]=1
    fi
done <<< "$php_fpm_scopes"

log "Found ${#containers[@]} containers running PHP-FPM"

# Process each container
for container_id in "${!containers[@]}"; do
    log "Processing container: $container_id"
    
    # Stop the container
    docker stop $container_id
    log "Stopped container $container_id"
    
    # Clean up and secure the container
    docker exec -it $container_id /bin/sh -c '
        # Kill any existing kdevtmpfsi processes
        pkill -9 kdevtmpfsi
        
        # Remove malicious files
        rm -f /tmp/kdevtmpfsi
        rm -f /tmp/.ZendSem.*
        rm -f /tmp/.*.sock
        
        # Create immutable blocker
        touch /tmp/kdevtmpfsi
        chmod 000 /tmp/kdevtmpfsi
        chattr +i /tmp/kdevtmpfsi
        
        # Secure PHP-FPM configuration if exists
        if [ -f /etc/php7/php-fpm.d/www.conf ]; then
            # Backup original config
            cp /etc/php7/php-fpm.d/www.conf /etc/php7/php-fpm.d/www.conf.bak
            
            # Update PHP-FPM configuration
            sed -i "s/^pm.max_children = .*/pm.max_children = 50/" /etc/php7/php-fpm.d/www.conf
            sed -i "s/^pm.start_servers = .*/pm.start_servers = 5/" /etc/php7/php-fpm.d/www.conf
            sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/" /etc/php7/php-fpm.d/www.conf
            sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/" /etc/php7/php-fpm.d/www.conf
            
            # Add security restrictions
            echo "php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source" >> /etc/php7/php-fpm.d/www.conf
            echo "php_admin_flag[allow_url_fopen] = off" >> /etc/php7/php-fpm.d/www.conf
        fi
    ' || log "Failed to execute commands in container $container_id"
    
    # Update container security options
    docker update --security-opt=no-new-privileges \
                 --read-only \
                 --tmpfs /tmp:size=100M,noexec,nosuid \
                 $container_id || log "Failed to update container $container_id security options"
    
    # Restart the container
    docker restart $container_id
    log "Restarted container $container_id with security measures"
done

# Create and set up host-level protection service
cat > /etc/systemd/system/kdevtmpfsi-protection.service << 'EOF'
[Unit]
Description=Protection against kdevtmpfsi malware
After=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do pkill -9 kdevtmpfsi; if [ ! -f /tmp/kdevtmpfsi ]; then touch /tmp/kdevtmpfsi; chmod 000 /tmp/kdevtmpfsi; chattr +i /tmp/kdevtmpfsi; fi; sleep 5; done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the protection service
systemctl daemon-reload
systemctl enable kdevtmpfsi-protection
systemctl start kdevtmpfsi-protection

log "Host-level protection service installed and started"

# Kill any remaining kdevtmpfsi processes
if pgrep kdevtmpfsi > /dev/null; then
    pkill -9 kdevtmpfsi
    log "Killed remaining kdevtmpfsi processes"
fi

# Create immutable blocker file on host
if [ ! -f /tmp/kdevtmpfsi ]; then
    touch /tmp/kdevtmpfsi
    chmod 000 /tmp/kdevtmpfsi
    chattr +i /tmp/kdevtmpfsi
    log "Created immutable blocker file on host"
fi

log "Cleanup process completed successfully"
log "Please monitor system for any recurring issues"

