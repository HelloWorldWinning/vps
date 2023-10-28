apt-get install iptables-persistent -y

net_card=$(ip addr |grep BROADCAST|head -1|awk '{print $2; exit}'|cut -d ":" -f 1)

iptables -t nat -A PREROUTING -i ${net_card} -p udp --dport 55000:60000 -j DNAT --to-destination :65503

ip6tables -t nat -A PREROUTING -i ${net_card} -p udp --dport 55000:60000 -j DNAT --to-destination :65503

sh -c 'iptables-save > /etc/iptables/rules.v4'
sh -c 'ip6tables-save > /etc/iptables/rules.v6'

#iptables-save > /etc/iptables/rules.v4
#ip6tables-save > /etc/iptables/rules.v6

#iptables-save -f /etc/iptables/rules.v4 
#ip6tables-save -f /etc/iptables/rules.v6


crontab -l > conf && echo  -e "@reboot sleep 13; /usr/sbin/iptables-restore < /etc/iptables/rules.v4" >> conf && crontab conf && rm -f conf

crontab -l > conf && echo  -e "@reboot sleep 14; /usr/sbin/ip6tables-restore < /etc/iptables/rules.v6" >> conf && crontab conf && rm -f conf


