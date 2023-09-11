
================================
先wgcf 后 wg

PostUp =   iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o wgcf -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o wgcf -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o wgcf -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o wgcf -j MASQUERADE



