adduser copier
mkdir -p /home/copier/.ssh
cp /root/.ssh/authorized_keys /home/copier/.ssh/authorized_keys
chown -R copier:copier /home/copier/.ssh
chmod 700 /home/copier/.ssh
chmod 600 /home/copier/.ssh/authorized_keys
