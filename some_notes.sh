================================================================
root@ja:/etc/wireguard# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 42:01:0a:b8:00:02 brd ff:ff:ff:ff:ff:ff
    altname enp0s4
    inet 10.184.0.2/24 brd 10.184.0.255 scope global ens4
       valid_lft forever preferred_lft forever
    inet6 fe80::4001:aff:feb8:2/64 scope link 
       valid_lft forever preferred_lft forever
8: warp: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none 
    inet 172.16.0.2/32 scope global warp
       valid_lft forever preferred_lft forever
    inet6 2606:4700:110:8765:1feb:5d0e:bf8c:4b5c/128 scope global 
       valid_lft forever preferred_lft forever

root@ja:/etc/wireguard# cat warp.conf 
[Interface]
PrivateKey = +FGIX0vqalEDHX/dPUdYp9FCTKlHPiqoG7WC3kaGYl0=
Address = 172.16.0.2/32
Address = 2606:4700:110:8765:1feb:5d0e:bf8c:4b5c/128
DNS = 1.1.1.1,8.8.8.8,8.8.4.4,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844
MTU = 1420
PostUp = ip -4 rule add from 10.184.0.2 lookup main
PostDown = ip -4 rule delete from 10.184.0.2 lookup main

#Reserved = [164, 231, 38]
#Table = off
#PostUp = /etc/wireguard/NonGlobalUp.sh
#PostDown = /etc/wireguard/NonGlobalDown.sh

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0
#AllowedIPs = ::/0
Endpoint = 162.159.195.228:2371
PersistentKeepalive = 30

先wgcf 后 wg

PostUp =   iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o wgcf -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o wgcf -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o wgcf -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o wgcf -j MASQUERADE






================================================================
