apt update
apt install resolvconf -y

echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolvconf/resolv.conf.d/base
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolvconf/resolv.conf.d/base

resolvconf -u

systemctl restart networking

ping google.com -c 3
