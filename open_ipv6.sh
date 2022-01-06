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
