echo 'iptables -t nat -L PREROUTING --line-numbers'
iptables -t nat -L

net_card=$(ip addr |grep BROADCAST|head -1|awk '{print $2; exit}'|cut -d ":" -f 1)

read -p "tcp/udp default:udp: " tcp_udp
if [[ -z ${tcp_udp} ]]; then
  tcp_udp=udp
fi

read -p "dport from: " dport
if [[ -z ${dport}  ]]; then
echo "no d port from"
	exit
fi       

read -p "destination " destination
if [[ -z ${destination}  ]]; then 
echo "no destination port from"
	exit
fi   


#echo "iptables -t nat -A PREROUTING -i $net_card -p $tcp_udp --dport $dport -j DNAT --to-destination :$destination"
iptables -t nat -A PREROUTING -i $net_card -p $tcp_udp --dport $dport -j DNAT --to-destination :$destination

iptables-save -f /etc/iptables/rules.v4
ip6tables-save -f /etc/iptables/rules.v6

iptables -t nat -L

