#!/bin/bash

sudo apt update
sudo apt  -y install libegl1 libopengl0 libxcb-cursor0 libxkbcommon0 libgl1-mesa-glx



sudo -v && wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sudo sh /dev/stdin

calibre --version

mkdir -p  /data/ebook_d
# mkdir -p  /data/calibre-library




# Set variables
REPO_URL="https://github.com/HelloWorldWinning/books.git"
REPO_PATH="default_d"
LOCAL_PATH="/data/ebook_d"

# Create the local directory if it doesn't exist
mkdir -p "$LOCAL_PATH"

# Change to the local directory
cd "$LOCAL_PATH" || exit

# Clone the repository
git clone --depth 1 --filter=blob:none --sparse "$REPO_URL" temp_repo

# Change to the cloned repository
cd temp_repo || exit

# Enable sparse checkout
git sparse-checkout set "$REPO_PATH"

# Pull the content
git pull origin main

# Move the contents to the desired location
mv "$REPO_PATH"/* ..

# Clean up
cd ..
rm -rf temp_repo

echo "Download completed. Files are now in $LOCAL_PATH"

calibredb add -r /data/ebook_d/* --library-path /data/calibre-library
 
calibre-server --manage-users -- add a a 


# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi


# Ensure the library directory exists
LIBRARY_DIR="/data/calibre-library"
mkdir -p "$LIBRARY_DIR"
chown -R calibre:calibre "$LIBRARY_DIR"
echo "Library directory set to '$LIBRARY_DIR' with appropriate permissions."

# Create the systemd service file
SERVICE_FILE="/etc/systemd/system/calib.service"
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Calibre eBook Server
After=network.target

[Service]
Type=simple
User=root
Group=root
Environment="PATH=/opt/calibre/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/calibre-server /data/calibre-library --port=188 --enable-auth --disable-use-bonjour
StandardOutput=append:/var/log/calibre-server.log
StandardError=append:/var/log/calibre-server.error.log
Restart=always
RestartSec=30

RuntimeDirectory=calibre-server
RuntimeDirectoryMode=0755
RuntimeDirectoryPreserve=yes
ExecStopPost=/bin/sh -c 'echo "Service stopped with exit code $EXIT_CODE" >> /var/log/calibre-stop.log'

[Install]
WantedBy=multi-user.target

EOL


echo "Created systemd service file at '$SERVICE_FILE'."

sudo chown -R root:root /data/calibre-library
sudo chmod -R 755 /data/calibre-library


# Reload systemd daemon to recognize the new service
systemctl daemon-reload
echo "Reloaded systemd daemon."

# Enable the 'calib' service to start on boot
systemctl enable calib
echo "Enabled 'calib' service to start on boot."

# Start the 'calib' service
systemctl start calib
echo "Started 'calib' service."

# Display the status of the 'calib' service
echo "Service 'calib' status:"
systemctl status calib --no-pager

