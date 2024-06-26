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
sudo chown -R ftpuser:ftpuser "/home/$ftpuser"
sudo chown -R ftpuser:ftpuser "/home/$ftpuser/ftp"
sudo chmod -R 777  "/home/$ftpuser"
sudo chmod -R 777  "/home/$ftpuser/ftp"


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

write_enable=YES
local_umask=0000
file_open_mode=0777
local_enable=YES
listen_port=54321

EOF


sudo apt install -y  ftp

# Restart vsftpd service
sudo systemctl stop vsftpd
sudo systemctl restart vsftpd
sleep 2

sudo systemctl status vsftpd

echo "FTP server installation completed."
