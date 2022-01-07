cat  >> /etc/sysctl.conf <<EOF 
# forward ipv4
net.ipv4.ip_forward = 1
# forward ipv6
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.eth0.accept_ra=2
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.eth0.forwarding=1
net.ipv6.conf.all.forwarding=1
EOF


sysctl -p /etc/sysctl.conf
