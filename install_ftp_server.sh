#!/bin/bash

# Prompt for username, default to 'ftpuser' if nothing is input
read -p "Enter the username for the FTP user (default: ftpuser): " ftpuser
ftpuser=${ftpuser:-ftpuser}

# Create the FTP user
sudo adduser --home /home/$ftpuser --shell /bin/false $ftpuser

# Create the FTP directory
sudo mkdir -p /home/$ftpuser/ftp

# Set ownership and permissions for the FTP directory
#sudo chown nobody:nogroup /home/$ftpuser/ftp
sudo chown nobody:nogroup  "/home/$ftpuser"
sudo chmod a-w "/home/$ftpuser/ftp"


# Remove any existing vsftpd package
sudo apt remove vsftpd -y
sudo apt purge vsftpd -y

# Install vsftpd
sudo apt install vsftpd -y

# Backup the existing vsftpd configuration file
sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

# Create a new vsftpd configuration file
sudo cat <<EOF >> /etc/vsftpd.conf
local_root=/home/$ftpuser/ftp
chroot_local_user=YES
allow_writeable_chroot=YES
pam_service_name=ftp
EOF



# Restart vsftpd service
sudo systemctl restart vsftpd
sleep 1

sudo systemctl status vsftpd

echo "FTP server installation completed."
