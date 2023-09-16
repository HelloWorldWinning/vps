echo "Please enter a domain:"
read domain
echo "You entered: $domain"


bash <(curl -fsSL https://get.hy2.sh/)



net_card=$(ip addr | awk '/<BROADCAST,MULTICAST/{gsub(/:/,""); print $2}')

cat  >/etc/hysteria/config.yaml<<EOF
listen: :50001

acme:
  domains:
    - $domain
  email: 123@wardao.eu.org

bandwidth:
  up: 100 mbps
  down: 50 mbps

auth:
  type: password
  password: 1

masquerade:
  type: proxy
  proxy:
    url: https://www.apple.com/
    rewriteHost: true
EOF





systemctl restart hysteria-server.service


# IPv4
iptables -t nat -A PREROUTING -i ${net_card} -p udp --dport 50001:54999 -j DNAT --to-destination :50001
# IPv6
ip6tables -t nat -A PREROUTING -i ${net_card} -p udp --dport 50001:54999 -j DNAT --to-destination :50001



systemctl enable hysteria-server.service


systemctl status hysteria-server.service




