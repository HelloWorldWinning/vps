cat > /etc/network/interfaces <<EOF 
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
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
