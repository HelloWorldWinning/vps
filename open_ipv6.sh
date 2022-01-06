cat > /etc/network/interfaces <<EOF 
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

# Cloud images dynamically generate config fragments for newly
# attached interfaces. See /etc/udev/rules.d/75-cloud-ifupdown.rules
# and /etc/network/cloud-ifupdown-helper. Dynamically generated
# configuration fragments are stored in /run:
source-directory /run/network/interfaces.d
 

auto lo
iface lo inet loopback
EOF



cat > /etc/network/interfaces.d/eth0 <<EOF 

auto eth0
allow-hotplug eth0

iface eth0 inet dhcp

iface eth0 inet6 dhcp
EOF

/etc/init.d/networking restart



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
